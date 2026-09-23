package controllers

import (
	"database/sql"
	"fmt"
	"libra/config"
	"libra/utils"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

// ─── ADVANCED LAWYER MANAGEMENT (Super Admin only) ──────────────────────
//
// Every tab here reuses an existing real table rather than creating a
// parallel one: earnings reuse lawyer_payouts (migration 027, the same
// source of truth as the Payouts & Settlements module), bookings/
// consultation history reuse consultations, cases reuse cases, documents
// reuse documents (migration 032 only added a verification workflow to it),
// and activity reuses audit_logs. There is no ratings/reviews table
// anywhere in this schema, so that tab is a real empty state, never
// fabricated data.

// AdminGetLawyerStats - GET /admin/lawyers/stats
func AdminGetLawyerStats(c *gin.Context) {
	var out struct {
		Total              int     `json:"total_lawyers"`
		Pending            int     `json:"pending_verification"`
		Verified           int     `json:"verified"`
		Active             int     `json:"active"`
		Inactive           int     `json:"inactive"`
		TotalEarnings      float64 `json:"total_lawyer_earnings"`
		TotalConsultations int     `json:"total_consultations"`
	}
	config.DB.QueryRow(`SELECT COUNT(*) FROM users u JOIN roles r ON u.role_id=r.id WHERE r.name='lawyer'`).Scan(&out.Total)
	config.DB.QueryRow(`
		SELECT COUNT(*) FROM users u JOIN roles r ON u.role_id=r.id
		WHERE r.name='lawyer' AND COALESCE(u.verification_status,'verified')='pending'
	`).Scan(&out.Pending)
	config.DB.QueryRow(`
		SELECT COUNT(*) FROM users u JOIN roles r ON u.role_id=r.id
		WHERE r.name='lawyer' AND COALESCE(u.verification_status,'verified')='verified'
	`).Scan(&out.Verified)
	config.DB.QueryRow(`SELECT COUNT(*) FROM users u JOIN roles r ON u.role_id=r.id WHERE r.name='lawyer' AND u.is_active=true`).Scan(&out.Active)
	config.DB.QueryRow(`SELECT COUNT(*) FROM users u JOIN roles r ON u.role_id=r.id WHERE r.name='lawyer' AND u.is_active=false`).Scan(&out.Inactive)
	config.DB.QueryRow(`
		SELECT COALESCE(SUM(co.amount_paise),0)/100.0 FROM consultations co
		JOIN users u ON co.lawyer_id = u.id WHERE co.payment_status='paid'
	`).Scan(&out.TotalEarnings)
	config.DB.QueryRow(`SELECT COUNT(*) FROM consultations`).Scan(&out.TotalConsultations)
	utils.Success(c, http.StatusOK, "Lawyer stats fetched", out)
}

// AdminGetLawyerProfile - GET /admin/lawyers/:id/profile
func AdminGetLawyerProfile(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "")
		return
	}

	var p struct {
		ID                 string  `json:"id"`
		Name               string  `json:"name"`
		Email              string  `json:"email"`
		Phone              string  `json:"phone"`
		AvatarURL          string  `json:"avatar_url"`
		Designation        string  `json:"designation"`
		BarCouncilNumber   string  `json:"bar_council_number"`
		Specialization     string  `json:"specialization"`
		IsActive           bool    `json:"is_active"`
		VerificationStatus string  `json:"verification_status"`
		RejectionReason    string  `json:"rejection_reason"`
		SuspensionReason   string  `json:"suspension_reason"`
		SuspendedByName    string  `json:"suspended_by_name"`
		SuspendedAt        *string `json:"suspended_at"`
		ReactivatedByName  string  `json:"reactivated_by_name"`
		ReactivatedAt      *string `json:"reactivated_at"`
		CreatedAt          string  `json:"created_at"`
		TotalBookings      int     `json:"total_bookings"`
		CompletedBookings  int     `json:"completed_consultations"`
		TotalCases         int     `json:"total_cases"`
		GrossEarnings      float64 `json:"gross_earnings"`
		PendingPayout      float64 `json:"pending_payout"`
		PaidPayout         float64 `json:"paid_payout"`
	}

	var avatarURL, designation, barCouncil, rejectionReason, suspensionReason sql.NullString
	var suspendedByName, reactivatedByName sql.NullString
	var suspendedAt, reactivatedAt sql.NullTime
	var createdAt time.Time
	err := config.DB.QueryRow(`
		SELECT u.id, u.name, u.email, COALESCE(u.phone,''), COALESCE(u.avatar_url,''),
		       u.designation, u.bar_council_number, u.is_active,
		       COALESCE(u.verification_status,'verified'), u.rejection_reason,
		       u.suspension_reason, COALESCE(su.name,''), u.suspended_at,
		       COALESCE(ru.name,''), u.reactivated_at, u.created_at,
		       COALESCE((
		           SELECT string_agg(DISTINCT c.case_type, ', ')
		           FROM cases c WHERE c.assigned_lawyer_id = u.id AND c.case_type != ''
		       ), '')
		FROM users u
		JOIN roles r ON u.role_id = r.id
		LEFT JOIN users su ON u.suspended_by = su.id
		LEFT JOIN users ru ON u.reactivated_by = ru.id
		WHERE u.id = $1::uuid AND r.name = 'lawyer'
	`, id).Scan(&p.ID, &p.Name, &p.Email, &p.Phone, &avatarURL, &designation, &barCouncil, &p.IsActive,
		&p.VerificationStatus, &rejectionReason, &suspensionReason, &suspendedByName, &suspendedAt,
		&reactivatedByName, &reactivatedAt, &createdAt, &p.Specialization)
	if err != nil {
		utils.Error(c, http.StatusNotFound, "Lawyer not found", err.Error())
		return
	}
	p.AvatarURL = avatarURL.String
	p.Designation = designation.String
	p.BarCouncilNumber = barCouncil.String
	p.RejectionReason = rejectionReason.String
	p.SuspensionReason = suspensionReason.String
	p.SuspendedByName = suspendedByName.String
	p.ReactivatedByName = reactivatedByName.String
	if suspendedAt.Valid {
		s := suspendedAt.Time.Format(time.RFC3339)
		p.SuspendedAt = &s
	}
	if reactivatedAt.Valid {
		s := reactivatedAt.Time.Format(time.RFC3339)
		p.ReactivatedAt = &s
	}
	p.CreatedAt = createdAt.Format(time.RFC3339)

	config.DB.QueryRow(`SELECT COUNT(*) FROM consultations WHERE lawyer_id=$1::uuid`, id).Scan(&p.TotalBookings)
	config.DB.QueryRow(`SELECT COUNT(*) FROM consultations WHERE lawyer_id=$1::uuid AND status='completed'`, id).Scan(&p.CompletedBookings)
	config.DB.QueryRow(`SELECT COUNT(*) FROM cases WHERE assigned_lawyer_id=$1::uuid`, id).Scan(&p.TotalCases)
	config.DB.QueryRow(`SELECT COALESCE(SUM(amount_paise),0)/100.0 FROM consultations WHERE lawyer_id=$1::uuid AND payment_status='paid'`, id).
		Scan(&p.GrossEarnings)
	config.DB.QueryRow(`
		SELECT COALESCE(SUM(co.amount_paise),0)/100.0
		FROM consultations co
		LEFT JOIN lawyer_payout_items lpi ON lpi.consultation_id = co.id
		WHERE co.lawyer_id = $1::uuid AND co.payment_status = 'paid' AND lpi.id IS NULL
	`, id).Scan(&p.PendingPayout)
	config.DB.QueryRow(`SELECT COALESCE(SUM(net_amount),0) FROM lawyer_payouts WHERE lawyer_id=$1::uuid AND status='paid'`, id).
		Scan(&p.PaidPayout)

	utils.Success(c, http.StatusOK, "Lawyer profile fetched", p)
}

// AdminGetLawyerDocumentsList - GET /admin/lawyers/:id/documents
func AdminGetLawyerDocumentsList(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "")
		return
	}
	rows, err := config.DB.Query(`
		SELECT d.id, d.file_name, COALESCE(d.file_type,''), COALESCE(d.category,''),
		       COALESCE(d.verification_status,'pending'), COALESCE(verifier.name,''), d.verified_at,
		       COALESCE(d.rejection_reason,''), d.created_at
		FROM documents d
		LEFT JOIN users verifier ON d.verified_by = verifier.id
		WHERE d.uploaded_by = $1::uuid AND d.category = 'lawyer_verification'
		ORDER BY d.created_at DESC
	`, id)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch documents", err.Error())
		return
	}
	defer rows.Close()

	type Row struct {
		ID                 string  `json:"id"`
		FileName           string  `json:"file_name"`
		FileType           string  `json:"file_type"`
		Category           string  `json:"category"`
		VerificationStatus string  `json:"verification_status"`
		VerifiedByName     string  `json:"verified_by_name"`
		VerifiedAt         *string `json:"verified_at"`
		RejectionReason    string  `json:"rejection_reason"`
		UploadedAt         string  `json:"uploaded_at"`
	}
	out := []Row{}
	for rows.Next() {
		var r Row
		var verifiedAt sql.NullTime
		var uploadedAt time.Time
		if rows.Scan(&r.ID, &r.FileName, &r.FileType, &r.Category, &r.VerificationStatus,
			&r.VerifiedByName, &verifiedAt, &r.RejectionReason, &uploadedAt) != nil {
			continue
		}
		if verifiedAt.Valid {
			s := verifiedAt.Time.Format(time.RFC3339)
			r.VerifiedAt = &s
		}
		r.UploadedAt = uploadedAt.Format(time.RFC3339)
		out = append(out, r)
	}
	utils.Success(c, http.StatusOK, "Documents fetched", out)
}

// AdminApproveLawyerDocument - PUT /admin/lawyers/documents/:doc_id/approve
func AdminApproveLawyerDocument(c *gin.Context) {
	docID := c.Param("doc_id")
	if !isUUID(docID) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "")
		return
	}
	var lawyerID, previousStatus string
	if err := config.DB.QueryRow(`
		SELECT uploaded_by::text, COALESCE(verification_status,'pending') FROM documents WHERE id=$1::uuid
	`, docID).Scan(&lawyerID, &previousStatus); err != nil {
		utils.Error(c, http.StatusNotFound, "Document not found", "")
		return
	}
	actorID := utils.UserID(c)
	if _, err := config.DB.Exec(`
		UPDATE documents SET verification_status='approved', verified_by=$1::uuid, verified_at=NOW(), rejection_reason=NULL
		WHERE id=$2::uuid
	`, actorID, docID); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to approve document", err.Error())
		return
	}
	utils.LogAudit(c, utils.AuditEntry{
		Action: "DOCUMENT_APPROVED", Module: "lawyers", TargetType: "document", TargetID: docID,
		Description: "Lawyer verification document approved",
		Before:      map[string]string{"verification_status": previousStatus}, After: map[string]string{"verification_status": "approved"},
	})
	utils.Notify(lawyerID, "", "Document approved", "Your verification document has been approved.", "verification")
	utils.Success(c, http.StatusOK, "Document approved", nil)
}

// AdminRejectLawyerDocument - PUT /admin/lawyers/documents/:doc_id/reject
func AdminRejectLawyerDocument(c *gin.Context) {
	docID := c.Param("doc_id")
	if !isUUID(docID) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "")
		return
	}
	var req struct {
		Reason string `json:"reason" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "A rejection reason is required", err.Error())
		return
	}
	var lawyerID, previousStatus string
	if err := config.DB.QueryRow(`
		SELECT uploaded_by::text, COALESCE(verification_status,'pending') FROM documents WHERE id=$1::uuid
	`, docID).Scan(&lawyerID, &previousStatus); err != nil {
		utils.Error(c, http.StatusNotFound, "Document not found", "")
		return
	}
	actorID := utils.UserID(c)
	if _, err := config.DB.Exec(`
		UPDATE documents SET verification_status='rejected', verified_by=$1::uuid, verified_at=NOW(), rejection_reason=$2
		WHERE id=$3::uuid
	`, actorID, req.Reason, docID); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to reject document", err.Error())
		return
	}
	utils.LogAudit(c, utils.AuditEntry{
		Action: "DOCUMENT_REJECTED", Module: "lawyers", TargetType: "document", TargetID: docID,
		Description: "Lawyer verification document rejected",
		Before:      map[string]string{"verification_status": previousStatus},
		After:       map[string]string{"verification_status": "rejected", "reason": req.Reason},
	})
	utils.Notify(lawyerID, "", "Document rejected", "Your verification document was rejected: "+req.Reason, "verification")
	utils.Success(c, http.StatusOK, "Document rejected", nil)
}

// AdminSuspendLawyer - PUT /admin/lawyers/:id/suspend
// Distinct from the generic AdminUpdateUser is_active toggle (used by the
// Users screen) only in that this requires and records a reason, per the
// Lawyer Management spec — both ultimately flip the same is_active column
// that every booking/availability check in the app already reads.
func AdminSuspendLawyer(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "")
		return
	}
	if id == utils.UserID(c) {
		utils.Error(c, http.StatusBadRequest, "You cannot suspend your own account", "")
		return
	}
	var req struct {
		Reason string `json:"reason" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "A suspension reason is required", err.Error())
		return
	}
	actorID := utils.UserID(c)
	res, err := config.DB.Exec(`
		UPDATE users SET is_active=false, suspension_reason=$1, suspended_by=$2::uuid, suspended_at=NOW(), updated_at=NOW()
		WHERE id=$3::uuid AND role_id = (SELECT id FROM roles WHERE name='lawyer')
	`, req.Reason, actorID, id)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to suspend lawyer", err.Error())
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		utils.Error(c, http.StatusNotFound, "Lawyer not found", "")
		return
	}
	utils.LogAudit(c, utils.AuditEntry{
		Action: "LAWYER_SUSPENDED", Module: "lawyers", TargetType: "user", TargetID: id,
		Description: "Lawyer account suspended",
		Before:      map[string]string{"is_active": "true"}, After: map[string]string{"is_active": "false", "reason": req.Reason},
	})
	utils.Notify(id, "", "Account suspended", "Your account has been suspended: "+req.Reason, "general")
	utils.Success(c, http.StatusOK, "Lawyer suspended", nil)
}

// AdminReactivateLawyer - PUT /admin/lawyers/:id/reactivate
func AdminReactivateLawyer(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "")
		return
	}
	actorID := utils.UserID(c)
	res, err := config.DB.Exec(`
		UPDATE users SET is_active=true, reactivated_by=$1::uuid, reactivated_at=NOW(), updated_at=NOW()
		WHERE id=$2::uuid AND role_id = (SELECT id FROM roles WHERE name='lawyer')
	`, actorID, id)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to reactivate lawyer", err.Error())
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		utils.Error(c, http.StatusNotFound, "Lawyer not found", "")
		return
	}
	utils.LogAudit(c, utils.AuditEntry{
		Action: "LAWYER_REACTIVATED", Module: "lawyers", TargetType: "user", TargetID: id,
		Description: "Lawyer account reactivated",
		Before:      map[string]string{"is_active": "false"}, After: map[string]string{"is_active": "true"},
	})
	utils.Notify(id, "", "Account reactivated", "Your account has been reactivated. You can resume using Libra Law.", "general")
	utils.Success(c, http.StatusOK, "Lawyer reactivated", nil)
}

// AdminGetLawyerBookings - GET /admin/lawyers/:id/bookings?status=upcoming|completed|cancelled|rejected|expired&page=
// Also serves the Consultation History tab — this app has one real table
// for both concepts, not two.
func AdminGetLawyerBookings(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "")
		return
	}
	statusFilter := c.Query("status")
	page := ParsePagination(c)

	query := `
		SELECT co.id, COALESCE(cl.name,''), co.consultation_type, co.consultation_date::text,
		       co.consultation_time, co.call_duration_seconds, COALESCE(co.amount_paise,0),
		       co.status, co.payment_status, co.created_at
		FROM consultations co
		LEFT JOIN users cl ON co.client_id = cl.id
		WHERE co.lawyer_id = $1::uuid`
	args := []interface{}{id}
	switch statusFilter {
	case "upcoming":
		query += ` AND co.status IN ('pending','confirmed')`
	case "completed":
		query += ` AND co.status = 'completed'`
	case "cancelled":
		query += ` AND co.status = 'cancelled'`
	case "rejected":
		query += ` AND co.status = 'rejected'`
	case "expired":
		query += ` AND co.status = 'expired'`
	}
	query += ` ORDER BY co.created_at DESC`
	args = append(args, page.Limit, page.Offset)
	query += fmt.Sprintf(` LIMIT $%d OFFSET $%d`, len(args)-1, len(args))

	rows, err := config.DB.Query(query, args...)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch bookings", err.Error())
		return
	}
	defer rows.Close()

	type Row struct {
		ID               string `json:"id"`
		ClientName       string `json:"client_name"`
		ConsultationType string `json:"consultation_type"`
		Date             string `json:"date"`
		Time             string `json:"time"`
		DurationSeconds  int    `json:"duration_seconds"`
		AmountPaise      int64  `json:"amount_paise"`
		Status           string `json:"status"`
		PaymentStatus    string `json:"payment_status"`
		CreatedAt        string `json:"created_at"`
	}
	out := []Row{}
	for rows.Next() {
		var r Row
		var createdAt time.Time
		if rows.Scan(&r.ID, &r.ClientName, &r.ConsultationType, &r.Date, &r.Time, &r.DurationSeconds,
			&r.AmountPaise, &r.Status, &r.PaymentStatus, &createdAt) != nil {
			continue
		}
		r.CreatedAt = createdAt.Format(time.RFC3339)
		out = append(out, r)
	}
	utils.SuccessWithMeta(c, http.StatusOK, "Bookings fetched", out, page.Meta(len(out)))
}

// AdminGetLawyerCases - GET /admin/lawyers/:id/cases?page=
func AdminGetLawyerCases(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "")
		return
	}
	page := ParsePagination(c)
	rows, err := config.DB.Query(`
		SELECT c.id, COALESCE(c.case_number,''), c.case_title, COALESCE(cl.name,''),
		       COALESCE(c.court_name,''), COALESCE(c.case_type,''), c.status,
		       c.filing_date::text, c.updated_at
		FROM cases c
		LEFT JOIN clients cl ON c.client_id = cl.id
		WHERE c.assigned_lawyer_id = $1::uuid
		ORDER BY c.updated_at DESC
		LIMIT $2 OFFSET $3
	`, id, page.Limit, page.Offset)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch cases", err.Error())
		return
	}
	defer rows.Close()

	type Row struct {
		ID         string  `json:"id"`
		CaseNumber string  `json:"case_number"`
		CaseTitle  string  `json:"case_title"`
		ClientName string  `json:"client_name"`
		CourtName  string  `json:"court_name"`
		CaseType   string  `json:"case_type"`
		Status     string  `json:"status"`
		FilingDate *string `json:"filing_date"`
		UpdatedAt  string  `json:"updated_at"`
	}
	out := []Row{}
	for rows.Next() {
		var r Row
		var filingDate sql.NullString
		var updatedAt time.Time
		if rows.Scan(&r.ID, &r.CaseNumber, &r.CaseTitle, &r.ClientName, &r.CourtName, &r.CaseType,
			&r.Status, &filingDate, &updatedAt) != nil {
			continue
		}
		if filingDate.Valid {
			r.FilingDate = &filingDate.String
		}
		r.UpdatedAt = updatedAt.Format(time.RFC3339)
		out = append(out, r)
	}
	utils.SuccessWithMeta(c, http.StatusOK, "Cases fetched", out, page.Meta(len(out)))
}

// AdminGetLawyerReviews - GET /admin/lawyers/:id/reviews
// No ratings/reviews table exists anywhere in this schema — this is a real,
// honest empty response, not a stub pretending to have data.
func AdminGetLawyerReviews(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "")
		return
	}
	utils.Success(c, http.StatusOK, "Reviews fetched", gin.H{
		"average_rating": nil,
		"total_reviews":  0,
		"breakdown":      gin.H{"5": 0, "4": 0, "3": 0, "2": 0, "1": 0},
		"reviews":        []gin.H{},
	})
}

// AdminGetLawyerActivity - GET /admin/lawyers/:id/activity
// Real audit_logs entries about this lawyer, plus the one true fact audit
// logging never captured retroactively: their account creation date.
func AdminGetLawyerActivity(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "")
		return
	}

	type Event struct {
		Action      string `json:"action"`
		Description string `json:"description"`
		ActorName   string `json:"actor_name"`
		ActorRole   string `json:"actor_role"`
		CreatedAt   string `json:"created_at"`
	}
	out := []Event{}

	var createdAt time.Time
	var name string
	if config.DB.QueryRow(`SELECT name, created_at FROM users WHERE id=$1::uuid`, id).Scan(&name, &createdAt) == nil {
		out = append(out, Event{
			Action: "ACCOUNT_CREATED", Description: name + "'s account was created",
			ActorRole: "SYSTEM", ActorName: "System", CreatedAt: createdAt.Format(time.RFC3339),
		})
	}

	rows, err := config.DB.Query(`
		SELECT al.action, COALESCE(al.description,''), COALESCE(u.name,''),
		       COALESCE(al.actor_role, ur.name, ''), al.created_at
		FROM audit_logs al
		LEFT JOIN users u ON al.user_id = u.id
		LEFT JOIN roles ur ON u.role_id = ur.id
		WHERE al.reference_id = $1::uuid
		   OR (al.target_type = 'document' AND al.reference_id IN (SELECT id FROM documents WHERE uploaded_by = $1::uuid))
		ORDER BY al.created_at DESC
	`, id)
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var e Event
			var createdAt time.Time
			if rows.Scan(&e.Action, &e.Description, &e.ActorName, &e.ActorRole, &createdAt) != nil {
				continue
			}
			e.ActorRole = supportRoleLabel(e.ActorRole)
			e.CreatedAt = createdAt.Format(time.RFC3339)
			out = append(out, e)
		}
	}

	utils.Success(c, http.StatusOK, "Activity fetched", out)
}

// AdminGetLawyerBankDetails - GET /admin/lawyers/:id/bank-details
//
// Super Admin only (see the admin group's RoleMiddleware in routes.go) —
// the one reader besides the lawyer themself allowed to see the full
// account number, since Super Admin is who actually has to key it into the
// payout/settlement mechanism. Never wired into any client-facing route.
func AdminGetLawyerBankDetails(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "")
		return
	}

	var d struct {
		AccountHolderName string `json:"bank_account_holder_name"`
		BankName          string `json:"bank_name"`
		AccountNumber     string `json:"bank_account_number"`
		IFSC              string `json:"bank_ifsc"`
		PassbookDocID     string `json:"bank_passbook_document_id"`
	}
	err := config.DB.QueryRow(`
		SELECT COALESCE(bank_account_holder_name,''), COALESCE(bank_name,''),
		       COALESCE(bank_account_number,''), COALESCE(bank_ifsc,''),
		       COALESCE(bank_passbook_document_id::text,'')
		FROM users WHERE id=$1::uuid
	`, id).Scan(&d.AccountHolderName, &d.BankName, &d.AccountNumber, &d.IFSC, &d.PassbookDocID)
	if err != nil {
		utils.Error(c, http.StatusNotFound, "Lawyer not found", err.Error())
		return
	}
	utils.Success(c, http.StatusOK, "Bank details fetched", d)
}
