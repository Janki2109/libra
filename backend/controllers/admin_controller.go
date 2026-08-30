package controllers

import (
	"libra/config"
	"libra/utils"
	"net/http"

	"github.com/gin-gonic/gin"
)

// ─── GET ALL USERS ────────────────────────────────
func AdminGetUsers(c *gin.Context) {
	rows, err := config.DB.Query(`
		SELECT u.id, u.name, u.email, COALESCE(u.phone,''),
		       COALESCE(r.name,''), u.is_active,
		       COALESCE(u.created_at::text,''),
		       COALESCE(u.last_login_at::text,'')
		FROM users u
		LEFT JOIN roles r ON u.role_id = r.id
		WHERE r.name != 'super_admin'
		ORDER BY u.created_at DESC
	`)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch users", err.Error())
		return
	}
	defer rows.Close()

	type User struct {
		ID          string `json:"id"`
		Name        string `json:"name"`
		Email       string `json:"email"`
		Phone       string `json:"phone"`
		RoleName    string `json:"role_name"`
		IsActive    bool   `json:"is_active"`
		CreatedAt   string `json:"created_at"`
		LastLoginAt string `json:"last_login_at"`
	}

	users := []User{}
	for rows.Next() {
		var u User
		rows.Scan(&u.ID, &u.Name, &u.Email, &u.Phone,
			&u.RoleName, &u.IsActive, &u.CreatedAt, &u.LastLoginAt)
		users = append(users, u)
	}
	utils.Success(c, http.StatusOK, "Users fetched", users)
}

// ─── UPDATE USER (Suspend / Activate) ────────────
func AdminUpdateUser(c *gin.Context) {
	userID := c.Param("id")
	if !isUUID(userID) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "not a uuid")
		return
	}
	if userID == utils.UserID(c) {
		utils.Error(c, http.StatusBadRequest,
			"You cannot suspend your own account", "self-suspend")
		return
	}

	var req struct {
		IsActive bool `json:"is_active"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}
	// Never let one platform admin disable another.
	res, err := config.DB.Exec(`
		UPDATE users SET is_active=$1, updated_at=NOW()
		WHERE id=$2::uuid
		  AND role_id NOT IN (SELECT id FROM roles WHERE name='super_admin')
	`, req.IsActive, userID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to update user", err.Error())
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		utils.Error(c, http.StatusNotFound, "User not found", "")
		return
	}
	action := "suspended"
	if req.IsActive {
		action = "activated"
	}
	utils.Success(c, http.StatusOK, "User "+action, nil)
}

// ─── DELETE USER ──────────────────────────────────
//
// Deactivates rather than deleting. The old handler ran a hard
// `DELETE FROM users`, which in a legal practice tool destroys the authorship
// trail on cases, notes, invoices and audit logs — records a firm may be
// required to retain — and cascades through every foreign key that references
// the user.
func AdminDeleteUser(c *gin.Context) {
	userID := c.Param("id")
	if !isUUID(userID) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "not a uuid")
		return
	}
	if userID == utils.UserID(c) {
		utils.Error(c, http.StatusBadRequest,
			"You cannot delete your own account", "self-delete")
		return
	}

	_, err := config.DB.Exec(`
		UPDATE users SET is_active=false, updated_at=NOW()
		WHERE id=$1::uuid
		  AND role_id NOT IN (SELECT id FROM roles WHERE name='super_admin')
	`, userID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to delete user", err.Error())
		return
	}
	utils.Success(c, http.StatusOK, "User deleted", nil)
}

// ─── GET ADMIN STATS ──────────────────────────────
func AdminGetStats(c *gin.Context) {
	var stats struct {
		TotalUsers          int     `json:"total_users"`
		TotalLawyers        int     `json:"total_lawyers"`
		TotalClients        int     `json:"total_clients"`
		TotalStudents       int     `json:"total_students"`
		TotalRevenue        float64 `json:"total_revenue"`
		MonthlyRevenue      float64 `json:"monthly_revenue"`
		ActiveSubscriptions int     `json:"active_subscriptions"`
		PendingVerification int     `json:"pending_verification"`
	}

	config.DB.QueryRow(`SELECT COUNT(*) FROM users`).Scan(&stats.TotalUsers)
	config.DB.QueryRow(`SELECT COUNT(*) FROM users u JOIN roles r ON u.role_id=r.id WHERE r.name='lawyer'`).Scan(&stats.TotalLawyers)
	config.DB.QueryRow(`SELECT COUNT(*) FROM users u JOIN roles r ON u.role_id=r.id WHERE r.name='client'`).Scan(&stats.TotalClients)
	config.DB.QueryRow(`SELECT COUNT(*) FROM users u JOIN roles r ON u.role_id=r.id WHERE r.name='law_student'`).Scan(&stats.TotalStudents)
	config.DB.QueryRow(`SELECT COALESCE(SUM(total_amount),0) FROM invoices WHERE status='paid'`).Scan(&stats.TotalRevenue)
	config.DB.QueryRow(`SELECT COALESCE(SUM(total_amount),0) FROM invoices WHERE status='paid' AND EXTRACT(MONTH FROM created_at)=EXTRACT(MONTH FROM NOW())`).Scan(&stats.MonthlyRevenue)

	utils.Success(c, http.StatusOK, "Stats fetched", stats)
}

// ─── GET ALL LAWYERS ──────────────────────────────
//
// Registering "as a lawyer" (RegisterScreen / auth_controller.Register)
// actually creates a role='admin' user — the firm owner — so both 'lawyer'
// and 'admin' role users are included here; otherwise no self-registered
// lawyer would ever appear in this verification list.
func AdminGetLawyers(c *gin.Context) {
	rows, err := config.DB.Query(`
		SELECT u.id, u.name, u.email, COALESCE(u.phone,''),
		       u.is_active, COALESCE(u.created_at::text,''),
		       COALESCE(u.bar_council_number,''), COALESCE(u.verification_status,'verified'),
		       COALESCE(u.rejection_reason,''),
		       COALESCE((SELECT d.id::text FROM documents d
		                 WHERE d.uploaded_by = u.id AND d.category = 'lawyer_verification'
		                 ORDER BY d.created_at DESC LIMIT 1), '')
		FROM users u
		JOIN roles r ON u.role_id = r.id
		WHERE r.name IN ('lawyer', 'admin')
		ORDER BY u.created_at DESC
	`)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed", err.Error())
		return
	}
	defer rows.Close()

	type Lawyer struct {
		ID                 string `json:"id"`
		Name               string `json:"name"`
		Email              string `json:"email"`
		Phone              string `json:"phone"`
		IsActive           bool   `json:"is_active"`
		CreatedAt          string `json:"created_at"`
		BarCouncilNumber   string `json:"bar_council_number"`
		VerificationStatus string `json:"verification_status"`
		RejectionReason    string `json:"rejection_reason"`
		DocumentID         string `json:"document_id"`
	}

	lawyers := []Lawyer{}
	for rows.Next() {
		var l Lawyer
		rows.Scan(&l.ID, &l.Name, &l.Email, &l.Phone, &l.IsActive, &l.CreatedAt,
			&l.BarCouncilNumber, &l.VerificationStatus, &l.RejectionReason, &l.DocumentID)
		lawyers = append(lawyers, l)
	}
	utils.Success(c, http.StatusOK, "Lawyers fetched", lawyers)
}

// ─── GET LAWYER VERIFICATION DOCUMENT ─────────────
//
// Platform-admin-only view of the document a lawyer attached at signup.
// Separate from the firm-scoped GetDocument handler because the caller here
// has no firm of their own to match against.
func AdminGetLawyerDocument(c *gin.Context) {
	userID := c.Param("id")
	if !isUUID(userID) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "not a uuid")
		return
	}
	var d struct {
		ID          string `json:"id"`
		FileName    string `json:"file_name"`
		FileContent string `json:"file_content"`
		MimeType    string `json:"mime_type"`
	}
	err := config.DB.QueryRow(`
		SELECT id, file_name, COALESCE(file_content,''), COALESCE(mime_type,'')
		FROM documents
		WHERE uploaded_by = $1::uuid AND category = 'lawyer_verification'
		ORDER BY created_at DESC LIMIT 1
	`, userID).Scan(&d.ID, &d.FileName, &d.FileContent, &d.MimeType)
	if err != nil {
		utils.Error(c, http.StatusNotFound, "Document not found", err.Error())
		return
	}
	utils.Success(c, http.StatusOK, "Document fetched", d)
}

// ─── APPROVE / REJECT LAWYER VERIFICATION ─────────
//
// Separate from AdminUpdateUser (which only ever toggles is_active) so that
// verifying a lawyer can never accidentally suspend their account, and vice
// versa. Does not touch is_active or the lawyer's ability to use the
// dashboard — verification is informational, tracked here and surfaced to
// the lawyer via the existing in-app notifications list (no separate push
// service exists in this codebase to hook into).
func AdminVerifyLawyer(c *gin.Context) {
	userID := c.Param("id")
	if !isUUID(userID) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "not a uuid")
		return
	}

	var req struct {
		Status          string `json:"verification_status" binding:"required,oneof=verified rejected"`
		RejectionReason string `json:"rejection_reason"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}

	adminID := utils.UserID(c)
	var firmID string
	res, err := config.DB.Exec(`
		UPDATE users
		SET verification_status = $1, rejection_reason = $2,
		    verified_by = $3::uuid, verified_at = NOW(), updated_at = NOW()
		WHERE id = $4::uuid
	`, req.Status, req.RejectionReason, adminID, userID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to update verification", err.Error())
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		utils.Error(c, http.StatusNotFound, "User not found", "")
		return
	}
	config.DB.QueryRow(`SELECT firm_id::text FROM users WHERE id = $1::uuid`, userID).Scan(&firmID)

	title := "Verification Approved"
	message := "Your professional/Bar Council document has been verified. Your account is fully verified."
	if req.Status == "rejected" {
		title = "Verification Rejected"
		message = "Your professional/Bar Council document was rejected."
		if req.RejectionReason != "" {
			message += " Reason: " + req.RejectionReason
		}
	}
	utils.Notify(userID, firmID, title, message, "verification")

	utils.Success(c, http.StatusOK, "Verification updated", nil)
}

// ─── GET SUBSCRIPTIONS ────────────────────────────
func AdminGetSubscriptions(c *gin.Context) {
	utils.Success(c, http.StatusOK, "Subscriptions fetched", []interface{}{})
}

// ─── GET REVENUE ──────────────────────────────────
func AdminGetRevenue(c *gin.Context) {
	var revenue struct {
		TotalRevenue   float64 `json:"total_revenue"`
		MonthlyRevenue float64 `json:"monthly_revenue"`
		WeeklyRevenue  float64 `json:"weekly_revenue"`
	}
	config.DB.QueryRow(`SELECT COALESCE(SUM(total_amount),0) FROM invoices WHERE status='paid'`).Scan(&revenue.TotalRevenue)
	config.DB.QueryRow(`SELECT COALESCE(SUM(total_amount),0) FROM invoices WHERE status='paid' AND created_at >= date_trunc('month', NOW())`).Scan(&revenue.MonthlyRevenue)
	config.DB.QueryRow(`SELECT COALESCE(SUM(total_amount),0) FROM invoices WHERE status='paid' AND created_at >= NOW() - INTERVAL '7 days'`).Scan(&revenue.WeeklyRevenue)
	utils.Success(c, http.StatusOK, "Revenue fetched", revenue)
}
