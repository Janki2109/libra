// Package controllers — admin panel, part 2.
//
// Split from admin_controller.go purely for file size; every handler here
// sits behind the same `admin.Use(middleware.RoleMiddleware("super_admin"))`
// group in routes.go as the rest of the admin API, so there is nothing
// extra to wire up per-handler. Every query here reads tables the rest of
// the app already owns (consultations, payment_orders, documents, cases,
// hearings, notifications, student_progress) — nothing new is stored.
package controllers

import (
	"fmt"
	"libra/config"
	"libra/utils"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
)

// ─── STUDENTS ─────────────────────────────────────
// GET /admin/students
func AdminGetStudents(c *gin.Context) {
	status := c.Query("status")
	search := strings.TrimSpace(c.Query("search"))
	page := ParsePagination(c)

	// student_progress's real columns are total_challenges/completed_challenges/
	// total_score/streak_days (confirmed against the live schema) — NOT the
	// xp/level/total_cases_completed/current_streak names challenge_controller.go's
	// SubmitChallenge/GetStudentProgress reference. That mismatch is a
	// pre-existing bug in the student challenge feature, unrelated to the
	// admin panel — flagged in the implementation report rather than fixed
	// here, since fixing it isn't part of this task.
	query := `
		SELECT u.id, u.name, u.email, COALESCE(u.phone,''), u.is_active,
		       COALESCE(u.created_at::text,''), COALESCE(u.last_login_at::text,''),
		       COALESCE(sp.total_score,0), COALESCE(sp.total_challenges,0), COALESCE(sp.completed_challenges,0),
		       COALESCE(sp.streak_days,0),
		       (SELECT COUNT(*) FROM consultations co WHERE co.client_id=u.id),
		       (SELECT COALESCE(SUM(co.amount_paise),0)/100.0 FROM consultations co WHERE co.client_id=u.id AND co.payment_status='paid')
		FROM users u
		JOIN roles r ON u.role_id = r.id
		LEFT JOIN student_progress sp ON sp.user_id = u.id
		WHERE r.name = 'law_student'`
	args := []interface{}{}
	if status == "active" {
		query += ` AND u.is_active = true`
	} else if status == "suspended" {
		query += ` AND u.is_active = false`
	}
	if search != "" {
		args = append(args, "%"+search+"%")
		query += fmt.Sprintf(` AND (u.name ILIKE $%d OR u.email ILIKE $%d)`, len(args), len(args))
	}
	query += ` ORDER BY u.created_at DESC`
	args = append(args, page.Limit, page.Offset)
	query += fmt.Sprintf(` LIMIT $%d OFFSET $%d`, len(args)-1, len(args))

	rows, err := config.DB.Query(query, args...)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch students", err.Error())
		return
	}
	defer rows.Close()

	type Student struct {
		ID                   string  `json:"id"`
		Name                 string  `json:"name"`
		Email                string  `json:"email"`
		Phone                string  `json:"phone"`
		IsActive             bool    `json:"is_active"`
		CreatedAt            string  `json:"created_at"`
		LastLoginAt          string  `json:"last_login_at"`
		TotalScore           int     `json:"total_score"`
		TotalChallenges      int     `json:"total_challenges"`
		CompletedChallenges  int     `json:"completed_challenges"`
		StreakDays           int     `json:"streak_days"`
		TotalConsultations   int     `json:"total_consultations"`
		TotalAmountSpent     float64 `json:"total_amount_spent"`
	}
	out := []Student{}
	for rows.Next() {
		var s Student
		rows.Scan(&s.ID, &s.Name, &s.Email, &s.Phone, &s.IsActive, &s.CreatedAt, &s.LastLoginAt,
			&s.TotalScore, &s.TotalChallenges, &s.CompletedChallenges, &s.StreakDays,
			&s.TotalConsultations, &s.TotalAmountSpent)
		out = append(out, s)
	}
	utils.SuccessWithMeta(c, http.StatusOK, "Students fetched", out, page.Meta(len(out)))
}

// ─── CLIENTS ──────────────────────────────────────
// GET /admin/clients
//
// The `client` role is the client-portal login (users.role='client') — not
// the firm-scoped `clients` table a firm manually enters its own clients
// into. This lists people who registered their own account and book lawyers
// through the consultation flow, matching what ClientRegister/find-a-lawyer
// actually create.
func AdminGetClients(c *gin.Context) {
	status := c.Query("status")
	search := strings.TrimSpace(c.Query("search"))
	page := ParsePagination(c)

	query := `
		SELECT u.id, u.name, u.email, COALESCE(u.phone,''), u.is_active,
		       COALESCE(u.created_at::text,''), COALESCE(u.last_login_at::text,''),
		       (SELECT COUNT(DISTINCT co.lawyer_id) FROM consultations co WHERE co.client_id=u.id),
		       (SELECT COUNT(*) FROM consultations co WHERE co.client_id=u.id),
		       (SELECT COUNT(*) FROM consultations co WHERE co.client_id=u.id AND co.status='completed'),
		       (SELECT COUNT(*) FROM consultations co WHERE co.client_id=u.id AND co.status='cancelled'),
		       (SELECT COUNT(*) FROM consultations co WHERE co.client_id=u.id AND co.payment_status='paid'),
		       (SELECT COALESCE(SUM(co.amount_paise),0)/100.0 FROM consultations co WHERE co.client_id=u.id AND co.payment_status='paid')
		FROM users u
		JOIN roles r ON u.role_id = r.id
		WHERE r.name = 'client'`
	args := []interface{}{}
	if status == "active" {
		query += ` AND u.is_active = true`
	} else if status == "suspended" {
		query += ` AND u.is_active = false`
	}
	if search != "" {
		args = append(args, "%"+search+"%")
		query += fmt.Sprintf(` AND (u.name ILIKE $%d OR u.email ILIKE $%d)`, len(args), len(args))
	}
	query += ` ORDER BY u.created_at DESC`
	args = append(args, page.Limit, page.Offset)
	query += fmt.Sprintf(` LIMIT $%d OFFSET $%d`, len(args)-1, len(args))

	rows, err := config.DB.Query(query, args...)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch clients", err.Error())
		return
	}
	defer rows.Close()

	type Client struct {
		ID                     string  `json:"id"`
		Name                   string  `json:"name"`
		Email                  string  `json:"email"`
		Phone                  string  `json:"phone"`
		IsActive               bool    `json:"is_active"`
		CreatedAt              string  `json:"created_at"`
		LastLoginAt            string  `json:"last_login_at"`
		TotalLawyersConsulted  int     `json:"total_lawyers_consulted"`
		TotalConsultations     int     `json:"total_consultations"`
		CompletedConsultations int     `json:"completed_consultations"`
		CancelledConsultations int     `json:"cancelled_consultations"`
		TotalPayments          int     `json:"total_payments"`
		TotalAmountSpent       float64 `json:"total_amount_spent"`
	}
	out := []Client{}
	for rows.Next() {
		var cl Client
		rows.Scan(&cl.ID, &cl.Name, &cl.Email, &cl.Phone, &cl.IsActive, &cl.CreatedAt, &cl.LastLoginAt,
			&cl.TotalLawyersConsulted, &cl.TotalConsultations, &cl.CompletedConsultations,
			&cl.CancelledConsultations, &cl.TotalPayments, &cl.TotalAmountSpent)
		out = append(out, cl)
	}
	utils.SuccessWithMeta(c, http.StatusOK, "Clients fetched", out, page.Meta(len(out)))
}

// ─── CONSULTATIONS (platform-wide) ────────────────
// GET /admin/consultations
// ?status= ?payment_status= ?search= (client/lawyer name) ?from= ?to=
func AdminGetConsultations(c *gin.Context) {
	status := c.Query("status")
	paymentStatus := c.Query("payment_status")
	search := strings.TrimSpace(c.Query("search"))
	from := c.Query("from")
	to := c.Query("to")
	page := ParsePagination(c)

	query := `
		SELECT co.id, co.consultation_type, co.consultation_date::text, co.consultation_time,
		       co.status, co.payment_status, COALESCE(co.amount_paise,0),
		       COALESCE(cl.name,''), COALESCE(cl.email,''),
		       COALESCE(law.name,''), COALESCE(law.email,''),
		       co.created_at::text
		FROM consultations co
		LEFT JOIN users cl  ON co.client_id = cl.id
		LEFT JOIN users law ON co.lawyer_id = law.id
		WHERE 1=1`
	args := []interface{}{}
	if status != "" {
		args = append(args, status)
		query += fmt.Sprintf(` AND co.status = $%d`, len(args))
	}
	if paymentStatus != "" {
		args = append(args, paymentStatus)
		query += fmt.Sprintf(` AND co.payment_status = $%d`, len(args))
	}
	if search != "" {
		args = append(args, "%"+search+"%")
		query += fmt.Sprintf(` AND (cl.name ILIKE $%d OR law.name ILIKE $%d)`, len(args), len(args))
	}
	if from != "" {
		args = append(args, from)
		query += fmt.Sprintf(` AND co.consultation_date >= $%d::date`, len(args))
	}
	if to != "" {
		args = append(args, to)
		query += fmt.Sprintf(` AND co.consultation_date <= $%d::date`, len(args))
	}
	query += ` ORDER BY co.created_at DESC`
	args = append(args, page.Limit, page.Offset)
	query += fmt.Sprintf(` LIMIT $%d OFFSET $%d`, len(args)-1, len(args))

	rows, err := config.DB.Query(query, args...)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch consultations", err.Error())
		return
	}
	defer rows.Close()

	type Row struct {
		ID               string  `json:"id"`
		ConsultationType string  `json:"consultation_type"`
		ConsultationDate string  `json:"consultation_date"`
		ConsultationTime string  `json:"consultation_time"`
		Status           string  `json:"status"`
		PaymentStatus    string  `json:"payment_status"`
		AmountRupees     float64 `json:"amount_rupees"`
		ClientName       string  `json:"client_name"`
		ClientEmail      string  `json:"client_email"`
		LawyerName       string  `json:"lawyer_name"`
		LawyerEmail      string  `json:"lawyer_email"`
		CreatedAt        string  `json:"created_at"`
	}
	out := []Row{}
	for rows.Next() {
		var r Row
		var amountPaise int64
		rows.Scan(&r.ID, &r.ConsultationType, &r.ConsultationDate, &r.ConsultationTime,
			&r.Status, &r.PaymentStatus, &amountPaise, &r.ClientName, &r.ClientEmail,
			&r.LawyerName, &r.LawyerEmail, &r.CreatedAt)
		r.AmountRupees = float64(amountPaise) / 100
		out = append(out, r)
	}
	utils.SuccessWithMeta(c, http.StatusOK, "Consultations fetched", out, page.Meta(len(out)))
}

// GET /admin/consultations/:id
func AdminGetConsultationDetail(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "not a uuid")
		return
	}
	var out gin.H
	var consultType, cdate, ctime, status, payStatus, notes, lawyerNotes, meetingLink string
	var amountPaise int64
	var clientName, clientEmail, clientPhone, lawyerName, lawyerEmail, lawyerPhone string
	var razorpayPaymentID, createdAt string
	err := config.DB.QueryRow(`
		SELECT co.consultation_type, co.consultation_date::text, co.consultation_time,
		       co.status, co.payment_status, COALESCE(co.amount_paise,0),
		       COALESCE(co.notes,''), COALESCE(co.lawyer_notes,''), COALESCE(co.meeting_link,''),
		       COALESCE(cl.name,''), COALESCE(cl.email,''), COALESCE(cl.phone,''),
		       COALESCE(law.name,''), COALESCE(law.email,''), COALESCE(law.phone,''),
		       COALESCE(co.razorpay_payment_id,''), co.created_at::text
		FROM consultations co
		LEFT JOIN users cl  ON co.client_id = cl.id
		LEFT JOIN users law ON co.lawyer_id = law.id
		WHERE co.id = $1::uuid
	`, id).Scan(&consultType, &cdate, &ctime, &status, &payStatus, &amountPaise,
		&notes, &lawyerNotes, &meetingLink, &clientName, &clientEmail, &clientPhone,
		&lawyerName, &lawyerEmail, &lawyerPhone, &razorpayPaymentID, &createdAt)
	if err != nil {
		utils.Error(c, http.StatusNotFound, "Consultation not found", err.Error())
		return
	}

	var orderID string
	config.DB.QueryRow(`
		SELECT order_id FROM payment_orders WHERE consultation_id=$1::uuid AND kind='consultation'
		ORDER BY updated_at DESC LIMIT 1
	`, id).Scan(&orderID)

	out = gin.H{
		"id": id, "consultation_type": consultType, "consultation_date": cdate, "consultation_time": ctime,
		"status": status, "payment_status": payStatus, "amount_rupees": float64(amountPaise) / 100,
		"notes": notes, "lawyer_notes": lawyerNotes, "meeting_link": meetingLink,
		"client_name": clientName, "client_email": clientEmail, "client_phone": clientPhone,
		"lawyer_name": lawyerName, "lawyer_email": lawyerEmail, "lawyer_phone": lawyerPhone,
		"razorpay_payment_id": razorpayPaymentID, "razorpay_order_id": orderID,
		"created_at": createdAt,
	}
	utils.Success(c, http.StatusOK, "Consultation fetched", out)
}

// ─── PAYMENTS (Razorpay ledger) ────────────────────
// GET /admin/payments
//
// payment_orders is the one table every gateway transaction attempt is
// recorded in — invoice payments, subscription checkouts and consultation
// fees alike (see migrations 010 and 014) — so this single query, joined
// out to whichever target each `kind` points at, is both the platform's
// "Payment Management" list and its "Razorpay Payment Details" view. No
// second payments table, no separate Razorpay-specific query.
//
// ?status=created|paid|failed ?kind=consultation|subscription|invoice
// ?search= (order id / payment id / user name / email) ?from= ?to=
func AdminGetPayments(c *gin.Context) {
	status := c.Query("status")
	kind := c.Query("kind")
	search := strings.TrimSpace(c.Query("search"))
	from := c.Query("from")
	to := c.Query("to")
	page := ParsePagination(c)

	query := `
		SELECT po.id, po.kind, po.order_id, COALESCE(po.payment_id,''),
		       po.amount_paise, po.currency, po.status,
		       COALESCE(payer.name,''), COALESCE(payer.email,''), COALESCE(payer_role.name,''),
		       COALESCE(law.name,''),
		       COALESCE(po.consultation_id::text,''),
		       po.created_at::text, po.updated_at::text
		FROM payment_orders po
		LEFT JOIN users payer ON payer.id = po.created_by
		LEFT JOIN roles payer_role ON payer_role.id = payer.role_id
		LEFT JOIN consultations co ON co.id = po.consultation_id
		LEFT JOIN users law ON law.id = co.lawyer_id
		WHERE 1=1`
	args := []interface{}{}
	if status != "" {
		args = append(args, status)
		query += fmt.Sprintf(` AND po.status = $%d`, len(args))
	}
	if kind != "" {
		args = append(args, kind)
		query += fmt.Sprintf(` AND po.kind = $%d`, len(args))
	}
	if search != "" {
		args = append(args, "%"+search+"%")
		query += fmt.Sprintf(` AND (po.order_id ILIKE $%d OR po.payment_id ILIKE $%d OR payer.name ILIKE $%d OR payer.email ILIKE $%d)`,
			len(args), len(args), len(args), len(args))
	}
	if from != "" {
		args = append(args, from)
		query += fmt.Sprintf(` AND po.created_at >= $%d::date`, len(args))
	}
	if to != "" {
		args = append(args, to)
		query += fmt.Sprintf(` AND po.created_at < ($%d::date + INTERVAL '1 day')`, len(args))
	}
	query += ` ORDER BY po.created_at DESC`
	args = append(args, page.Limit, page.Offset)
	query += fmt.Sprintf(` LIMIT $%d OFFSET $%d`, len(args)-1, len(args))

	rows, err := config.DB.Query(query, args...)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch payments", err.Error())
		return
	}
	defer rows.Close()

	type Row struct {
		ID              string  `json:"id"`
		Kind            string  `json:"kind"`
		OrderID         string  `json:"order_id"`
		PaymentID       string  `json:"payment_id"`
		AmountRupees    float64 `json:"amount_rupees"`
		Currency        string  `json:"currency"`
		Status          string  `json:"status"`
		UserName        string  `json:"user_name"`
		UserEmail       string  `json:"user_email"`
		UserRole        string  `json:"user_role"`
		LawyerName      string  `json:"lawyer_name"`
		ConsultationID  string  `json:"consultation_id"`
		CreatedAt       string  `json:"created_at"`
		UpdatedAt       string  `json:"updated_at"`
	}
	out := []Row{}
	for rows.Next() {
		var r Row
		var amountPaise int64
		rows.Scan(&r.ID, &r.Kind, &r.OrderID, &r.PaymentID, &amountPaise, &r.Currency, &r.Status,
			&r.UserName, &r.UserEmail, &r.UserRole, &r.LawyerName, &r.ConsultationID,
			&r.CreatedAt, &r.UpdatedAt)
		r.AmountRupees = float64(amountPaise) / 100
		out = append(out, r)
	}
	utils.SuccessWithMeta(c, http.StatusOK, "Payments fetched", out, page.Meta(len(out)))
}

// ─── DOCUMENTS (platform-wide) ─────────────────────
// GET /admin/documents
// ?category=lawyer_verification|... ?owner_role=lawyer|client|law_student
func AdminGetDocuments(c *gin.Context) {
	category := c.Query("category")
	ownerRole := c.Query("owner_role")
	page := ParsePagination(c)

	query := `
		SELECT d.id, d.file_name, COALESCE(d.file_type,''), COALESCE(d.category,''),
		       COALESCE(u.name,''), COALESCE(u.email,''), COALESCE(r.name,''),
		       COALESCE(u.verification_status,''),
		       d.created_at::text
		FROM documents d
		LEFT JOIN users u ON u.id = d.uploaded_by
		LEFT JOIN roles r ON r.id = u.role_id
		WHERE 1=1`
	args := []interface{}{}
	if category != "" {
		args = append(args, category)
		query += fmt.Sprintf(` AND d.category = $%d`, len(args))
	}
	if ownerRole == "lawyer" {
		query += ` AND r.name IN ('lawyer','admin')`
	} else if ownerRole != "" {
		args = append(args, ownerRole)
		query += fmt.Sprintf(` AND r.name = $%d`, len(args))
	}
	query += ` ORDER BY d.created_at DESC`
	args = append(args, page.Limit, page.Offset)
	query += fmt.Sprintf(` LIMIT $%d OFFSET $%d`, len(args)-1, len(args))

	rows, err := config.DB.Query(query, args...)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch documents", err.Error())
		return
	}
	defer rows.Close()

	type Row struct {
		ID                 string `json:"id"`
		FileName           string `json:"file_name"`
		FileType           string `json:"file_type"`
		Category           string `json:"category"`
		OwnerName          string `json:"owner_name"`
		OwnerEmail         string `json:"owner_email"`
		OwnerRole          string `json:"owner_role"`
		// Documents have no per-file verification flag — for a lawyer's
		// verification document, "status" is the owning USER's
		// verification_status (see AdminVerifyLawyer); other documents have
		// no verification concept at all and this is left blank.
		VerificationStatus string `json:"verification_status"`
		CreatedAt          string `json:"created_at"`
	}
	out := []Row{}
	for rows.Next() {
		var r Row
		rows.Scan(&r.ID, &r.FileName, &r.FileType, &r.Category, &r.OwnerName, &r.OwnerEmail,
			&r.OwnerRole, &r.VerificationStatus, &r.CreatedAt)
		if r.Category != "lawyer_verification" {
			r.VerificationStatus = ""
		}
		out = append(out, r)
	}
	utils.SuccessWithMeta(c, http.StatusOK, "Documents fetched", out, page.Meta(len(out)))
}

// ─── CASES (platform-wide) ─────────────────────────
// GET /admin/cases
func AdminGetCases(c *gin.Context) {
	search := strings.TrimSpace(c.Query("search"))
	status := c.Query("status")
	page := ParsePagination(c)

	query := `
		SELECT ca.id, COALESCE(ca.case_number,''), ca.case_title, COALESCE(ca.status,''),
		       COALESCE(ca.court_name,''), COALESCE(c.name,''), COALESCE(law.name,''),
		       ca.created_at::text,
		       (SELECT MIN(h.hearing_date)::text FROM hearings h WHERE h.case_id = ca.id AND h.hearing_date >= CURRENT_DATE)
		FROM cases ca
		LEFT JOIN clients c ON c.id = ca.client_id
		LEFT JOIN users law ON law.id = ca.assigned_lawyer_id
		WHERE 1=1`
	args := []interface{}{}
	if search != "" {
		args = append(args, "%"+search+"%")
		query += fmt.Sprintf(` AND (ca.case_title ILIKE $%d OR ca.case_number ILIKE $%d)`, len(args), len(args))
	}
	if status != "" {
		args = append(args, status)
		query += fmt.Sprintf(` AND ca.status = $%d`, len(args))
	}
	query += ` ORDER BY ca.created_at DESC`
	args = append(args, page.Limit, page.Offset)
	query += fmt.Sprintf(` LIMIT $%d OFFSET $%d`, len(args)-1, len(args))

	rows, err := config.DB.Query(query, args...)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch cases", err.Error())
		return
	}
	defer rows.Close()

	type Row struct {
		ID          string  `json:"id"`
		CaseNumber  string  `json:"case_number"`
		CaseTitle   string  `json:"case_title"`
		Status      string  `json:"status"`
		CourtName   string  `json:"court_name"`
		ClientName  string  `json:"client_name"`
		LawyerName  string  `json:"lawyer_name"`
		CreatedAt   string  `json:"created_at"`
		NextHearing *string `json:"next_hearing"`
	}
	out := []Row{}
	for rows.Next() {
		var r Row
		var next *string
		rows.Scan(&r.ID, &r.CaseNumber, &r.CaseTitle, &r.Status, &r.CourtName,
			&r.ClientName, &r.LawyerName, &r.CreatedAt, &next)
		r.NextHearing = next
		out = append(out, r)
	}
	utils.SuccessWithMeta(c, http.StatusOK, "Cases fetched", out, page.Meta(len(out)))
}

// ─── HEARINGS (platform-wide) ──────────────────────
// GET /admin/hearings
func AdminGetHearings(c *gin.Context) {
	status := c.Query("status")
	page := ParsePagination(c)

	query := `
		SELECT h.id, COALESCE(ca.case_title,''), COALESCE(h.court_name,''),
		       COALESCE(law.name,''), COALESCE(c.name,''),
		       h.hearing_date::text, COALESCE(h.hearing_time::text,''), COALESCE(h.status,'')
		FROM hearings h
		LEFT JOIN cases ca ON ca.id = h.case_id
		LEFT JOIN clients c ON c.id = ca.client_id
		LEFT JOIN users law ON law.id = ca.assigned_lawyer_id
		WHERE 1=1`
	args := []interface{}{}
	if status != "" {
		args = append(args, status)
		query += fmt.Sprintf(` AND h.status = $%d`, len(args))
	}
	query += ` ORDER BY h.hearing_date DESC`
	args = append(args, page.Limit, page.Offset)
	query += fmt.Sprintf(` LIMIT $%d OFFSET $%d`, len(args)-1, len(args))

	rows, err := config.DB.Query(query, args...)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch hearings", err.Error())
		return
	}
	defer rows.Close()

	type Row struct {
		ID          string `json:"id"`
		CaseTitle   string `json:"case_title"`
		CourtName   string `json:"court_name"`
		LawyerName  string `json:"lawyer_name"`
		ClientName  string `json:"client_name"`
		HearingDate string `json:"hearing_date"`
		HearingTime string `json:"hearing_time"`
		Status      string `json:"status"`
	}
	out := []Row{}
	for rows.Next() {
		var r Row
		rows.Scan(&r.ID, &r.CaseTitle, &r.CourtName, &r.LawyerName, &r.ClientName,
			&r.HearingDate, &r.HearingTime, &r.Status)
		out = append(out, r)
	}
	utils.SuccessWithMeta(c, http.StatusOK, "Hearings fetched", out, page.Meta(len(out)))
}

// ─── NOTIFICATIONS ──────────────────────────────────
// GET /admin/notifications — recent notification records platform-wide.
func AdminGetNotifications(c *gin.Context) {
	page := ParsePagination(c)
	rows, err := config.DB.Query(`
		SELECT n.id, COALESCE(u.name,''), COALESCE(r.name,''), n.title, COALESCE(n.message,''),
		       COALESCE(n.type,''), n.is_read, n.created_at::text
		FROM notifications n
		LEFT JOIN users u ON u.id = n.user_id
		LEFT JOIN roles r ON r.id = u.role_id
		ORDER BY n.created_at DESC
		LIMIT $1 OFFSET $2
	`, page.Limit, page.Offset)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch notifications", err.Error())
		return
	}
	defer rows.Close()

	type Row struct {
		ID        string `json:"id"`
		UserName  string `json:"user_name"`
		UserRole  string `json:"user_role"`
		Title     string `json:"title"`
		Message   string `json:"message"`
		Type      string `json:"type"`
		IsRead    bool   `json:"is_read"`
		CreatedAt string `json:"created_at"`
	}
	out := []Row{}
	for rows.Next() {
		var r Row
		rows.Scan(&r.ID, &r.UserName, &r.UserRole, &r.Title, &r.Message, &r.Type, &r.IsRead, &r.CreatedAt)
		out = append(out, r)
	}
	utils.SuccessWithMeta(c, http.StatusOK, "Notifications fetched", out, page.Meta(len(out)))
}

// POST /admin/notifications/send
// {"target":"user"|"lawyers"|"students"|"clients", "user_id":"...", "title":"...", "message":"..."}
//
// Reuses utils.Notify — the exact function every other notification in this
// app already goes through (in-app row + FCM push if configured) — for both
// the single-user and the broadcast-by-role cases. No new send/push
// machinery.
func AdminSendNotification(c *gin.Context) {
	var req struct {
		Target  string `json:"target" binding:"required,oneof=user lawyers students clients"`
		UserID  string `json:"user_id"`
		Title   string `json:"title" binding:"required"`
		Message string `json:"message" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}

	if req.Target == "user" {
		if !isUUID(req.UserID) {
			utils.Error(c, http.StatusBadRequest, "Invalid user_id", "not a uuid")
			return
		}
		var firmID string
		config.DB.QueryRow(`SELECT COALESCE(firm_id::text,'') FROM users WHERE id=$1::uuid`, req.UserID).Scan(&firmID)
		utils.Notify(req.UserID, firmID, req.Title, req.Message, "admin_broadcast")
		utils.Success(c, http.StatusOK, "Notification sent", gin.H{"recipients": 1})
		return
	}

	// "lawyers" also reaches role='admin' — see AdminGetLawyers' comment on
	// why self-registered lawyers carry that role.
	roleFilter := "r.name IN ('lawyer','admin')"
	args := []interface{}{}
	if req.Target != "lawyers" {
		roleFilter = "r.name = $1"
		args = append(args, map[string]string{"students": "law_student", "clients": "client"}[req.Target])
	}
	query := fmt.Sprintf(`
		SELECT u.id::text, COALESCE(u.firm_id::text,'') FROM users u
		JOIN roles r ON u.role_id = r.id
		WHERE %s AND u.is_active = true
	`, roleFilter)
	rows, err := config.DB.Query(query, args...)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to send notifications", err.Error())
		return
	}
	defer rows.Close()

	count := 0
	for rows.Next() {
		var uid, firmID string
		if rows.Scan(&uid, &firmID) == nil {
			utils.Notify(uid, firmID, req.Title, req.Message, "admin_broadcast")
			count++
		}
	}
	utils.Success(c, http.StatusOK, "Notification sent", gin.H{"recipients": count})
}

// ─── INVOICES (platform-wide, with GST/platform-fee breakdown) ────
// GET /admin/invoices
//
// invoices already carries the full breakdown (subtotal, tax_percent,
// tax_amount, platform_fee, total_amount — see migration 016 and
// CreateInvoice) — this just surfaces it platform-wide instead of the
// firm-scoped GetInvoices, with lawyer/client names joined in. Deliberately
// separate from AdminGetPayments: most invoices in this app are settled
// through the manual UPI/bank-transfer proof flow (payment_screen.dart),
// which never creates a payment_orders row at all, so payment_orders alone
// would miss most bills. Reading straight from invoices catches all of them
// regardless of how they were paid.
func AdminGetInvoices(c *gin.Context) {
	status := c.Query("status")
	search := strings.TrimSpace(c.Query("search"))
	page := ParsePagination(c)

	query := `
		SELECT i.id, i.invoice_number, COALESCE(i.subtotal,0), COALESCE(i.tax_percent,0),
		       COALESCE(i.tax_amount,0), COALESCE(i.platform_fee,0), i.total_amount,
		       COALESCE(i.paid_amount,0), i.status,
		       COALESCE(cl.name,''), COALESCE(law.name,''),
		       i.issue_date::text, COALESCE(i.due_date::text,''), i.created_at::text
		FROM invoices i
		LEFT JOIN clients cl ON i.client_id = cl.id
		LEFT JOIN users law ON law.id = i.created_by
		WHERE 1=1`
	args := []interface{}{}
	if status != "" {
		args = append(args, status)
		query += fmt.Sprintf(` AND i.status = $%d`, len(args))
	}
	if search != "" {
		args = append(args, "%"+search+"%")
		query += fmt.Sprintf(` AND (i.invoice_number ILIKE $%d OR cl.name ILIKE $%d)`, len(args), len(args))
	}
	query += ` ORDER BY i.created_at DESC`
	args = append(args, page.Limit, page.Offset)
	query += fmt.Sprintf(` LIMIT $%d OFFSET $%d`, len(args)-1, len(args))

	rows, err := config.DB.Query(query, args...)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch invoices", err.Error())
		return
	}
	defer rows.Close()

	type Row struct {
		ID            string  `json:"id"`
		InvoiceNumber string  `json:"invoice_number"`
		Subtotal      float64 `json:"subtotal"`
		GSTRate       float64 `json:"gst_rate"`
		GSTAmount     float64 `json:"gst_amount"`
		PlatformFee   float64 `json:"platform_fee"`
		TotalAmount   float64 `json:"total_amount"`
		PaidAmount    float64 `json:"paid_amount"`
		Status        string  `json:"status"`
		ClientName    string  `json:"client_name"`
		LawyerName    string  `json:"lawyer_name"`
		IssueDate     string  `json:"issue_date"`
		DueDate       string  `json:"due_date"`
		CreatedAt     string  `json:"created_at"`
	}
	out := []Row{}
	for rows.Next() {
		var r Row
		rows.Scan(&r.ID, &r.InvoiceNumber, &r.Subtotal, &r.GSTRate, &r.GSTAmount, &r.PlatformFee,
			&r.TotalAmount, &r.PaidAmount, &r.Status, &r.ClientName, &r.LawyerName,
			&r.IssueDate, &r.DueDate, &r.CreatedAt)
		out = append(out, r)
	}
	utils.SuccessWithMeta(c, http.StatusOK, "Invoices fetched", out, page.Meta(len(out)))
}

// ─── GLOBAL SEARCH ─────────────────────────────────
// GET /admin/search?q=
//
// Fans the query out across the same tables every other admin list already
// queries and returns a small, capped result per category — a lookup aid
// for "find this person/payment/case", not a paginated list in its own
// right (each section's own screen already provides that).
func AdminSearch(c *gin.Context) {
	q := strings.TrimSpace(c.Query("q"))
	if q == "" {
		utils.Success(c, http.StatusOK, "Search results", gin.H{
			"users": []interface{}{}, "consultations": []interface{}{},
			"payments": []interface{}{}, "cases": []interface{}{},
		})
		return
	}
	like := "%" + q + "%"

	users := []gin.H{}
	rows, _ := config.DB.Query(`
		SELECT u.id, u.name, u.email, COALESCE(r.name,'')
		FROM users u LEFT JOIN roles r ON r.id = u.role_id
		WHERE r.name != 'super_admin' AND (u.name ILIKE $1 OR u.email ILIKE $1 OR u.phone ILIKE $1)
		LIMIT 10
	`, like)
	if rows != nil {
		for rows.Next() {
			var id, name, email, role string
			if rows.Scan(&id, &name, &email, &role) == nil {
				users = append(users, gin.H{"id": id, "name": name, "email": email, "role": role})
			}
		}
		rows.Close()
	}

	consultations := []gin.H{}
	rows, _ = config.DB.Query(`
		SELECT co.id::text, COALESCE(cl.name,''), COALESCE(law.name,''), co.status
		FROM consultations co
		LEFT JOIN users cl ON cl.id = co.client_id
		LEFT JOIN users law ON law.id = co.lawyer_id
		WHERE co.id::text ILIKE $1 OR cl.name ILIKE $1 OR law.name ILIKE $1
		LIMIT 10
	`, like)
	if rows != nil {
		for rows.Next() {
			var id, clientName, lawyerName, status string
			if rows.Scan(&id, &clientName, &lawyerName, &status) == nil {
				consultations = append(consultations, gin.H{"id": id, "client_name": clientName, "lawyer_name": lawyerName, "status": status})
			}
		}
		rows.Close()
	}

	payments := []gin.H{}
	rows, _ = config.DB.Query(`
		SELECT id::text, order_id, COALESCE(payment_id,''), status
		FROM payment_orders
		WHERE order_id ILIKE $1 OR payment_id ILIKE $1
		LIMIT 10
	`, like)
	if rows != nil {
		for rows.Next() {
			var id, orderID, paymentID, status string
			if rows.Scan(&id, &orderID, &paymentID, &status) == nil {
				payments = append(payments, gin.H{"id": id, "order_id": orderID, "payment_id": paymentID, "status": status})
			}
		}
		rows.Close()
	}

	cases := []gin.H{}
	rows, _ = config.DB.Query(`
		SELECT id::text, case_title, COALESCE(case_number,'')
		FROM cases
		WHERE case_title ILIKE $1 OR case_number ILIKE $1 OR id::text ILIKE $1
		LIMIT 10
	`, like)
	if rows != nil {
		for rows.Next() {
			var id, title, number string
			if rows.Scan(&id, &title, &number) == nil {
				cases = append(cases, gin.H{"id": id, "case_title": title, "case_number": number})
			}
		}
		rows.Close()
	}

	utils.Success(c, http.StatusOK, "Search results", gin.H{
		"users": users, "consultations": consultations, "payments": payments, "cases": cases,
	})
}
