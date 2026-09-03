package controllers

import (
	"database/sql"
	"libra/config"
	"libra/utils"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

// ─── CLIENT PORTAL LOGIN ─────────────────────
func PortalLogin(c *gin.Context) {
	var req struct {
		Email    string `json:"email" binding:"required,email"`
		Password string `json:"password" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}

	var user struct {
		ID           string
		Name         string
		Email        string
		Phone        string
		PasswordHash string
		RoleName     string
		FirmID       string
		IsActive     bool
	}

	err := config.DB.QueryRow(`
		SELECT u.id, u.name, u.email, COALESCE(u.phone,''),
		       u.password_hash, COALESCE(r.name,''),
		       COALESCE(u.firm_id::text,''), u.is_active
		FROM users u
		LEFT JOIN roles r ON u.role_id = r.id
		WHERE lower(u.email) = $1 AND u.is_active = true
	`, normalizeEmail(req.Email)).Scan(
		&user.ID, &user.Name, &user.Email, &user.Phone,
		&user.PasswordHash, &user.RoleName, &user.FirmID, &user.IsActive,
	)

	if err == sql.ErrNoRows {
		// Equalise timing with the wrong-password path — see Login.
		utils.CheckPassword(req.Password, dummyBcryptHash)
		utils.Error(c, http.StatusUnauthorized, "Invalid email or password", "user not found")
		return
	}
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Database error", err.Error())
		return
	}

	if !utils.CheckPassword(req.Password, user.PasswordHash) {
		utils.Error(c, http.StatusUnauthorized, "Invalid email or password", "wrong password")
		return
	}

	// This endpoint issues a session for the client portal specifically. It
	// previously accepted any account, so a lawyer or platform admin could
	// authenticate through it and receive a token carrying their full role.
	if user.RoleName != "client" {
		utils.Error(c, http.StatusForbidden,
			"This login is for client portal accounts", "wrong portal for role")
		return
	}

	config.DB.Exec("UPDATE users SET last_login_at=$1 WHERE id=$2", time.Now(), user.ID)

	token, err := utils.GenerateToken(user.ID, user.Email, user.RoleName, user.FirmID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Token generation failed", err.Error())
		return
	}

	utils.Success(c, http.StatusOK, "Login successful", gin.H{
		"token": token,
		"user": gin.H{
			"id":        user.ID,
			"name":      user.Name,
			"email":     user.Email,
			"phone":     user.Phone,
			"role":      user.RoleName,
			"role_name": user.RoleName,
			"firm_id":   user.FirmID,
		},
	})
}

// portalClientEmail returns the caller's own, normalized email address — the
// key every portal query scopes on. It reads the address from the database
// using the verified user id rather than trusting anything in the request.
func portalClientEmail(c *gin.Context) (string, bool) {
	userID := utils.UserID(c)
	if !isUUID(userID) {
		return "", false
	}
	var email string
	if err := config.DB.QueryRow(
		`SELECT lower(email) FROM users WHERE id=$1::uuid`, userID,
	).Scan(&email); err != nil || email == "" {
		return "", false
	}
	return email, true
}

// ─── MY CASES ────────────────────────────────
func GetMyCases(c *gin.Context) {
	userEmail, ok := portalClientEmail(c)
	if !ok {
		utils.Success(c, http.StatusOK, "Cases fetched", []interface{}{})
		return
	}

	// Match every clients row carrying this address, not just the first one.
	//
	// The old code took `SELECT id FROM clients WHERE email=$1 LIMIT 1` and
	// filtered on that single id. Two firms can each have a client with the
	// same email, and "first row" is whichever Postgres happened to return —
	// so a client engaged by two firms saw an arbitrary one of them, and could
	// be shown the wrong firm's matters entirely.
	rows, err := config.DB.Query(`
		SELECT c.id, COALESCE(c.case_number,''), c.case_title,
		       COALESCE(c.case_type,''), COALESCE(c.court_name,''),
		       COALESCE(c.court_location,''), COALESCE(c.judge_name,''),
		       COALESCE(c.status,'active'), COALESCE(c.priority,'normal'),
		       COALESCE(c.description,''), COALESCE(c.opposite_party,''),
		       COALESCE(c.opposite_lawyer,''), COALESCE(c.cnr_number,''),
		       c.created_at
		FROM cases c
		WHERE c.client_id IN (SELECT id FROM clients WHERE lower(email) = $1)
		ORDER BY c.created_at DESC
	`, userEmail)

	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch cases", err.Error())
		return
	}
	defer rows.Close()

	type Case struct {
		ID             string    `json:"id"`
		CaseNumber     string    `json:"case_number"`
		CaseTitle      string    `json:"case_title"`
		CaseType       string    `json:"case_type"`
		CourtName      string    `json:"court_name"`
		CourtLocation  string    `json:"court_location"`
		JudgeName      string    `json:"judge_name"`
		Status         string    `json:"status"`
		Priority       string    `json:"priority"`
		Description    string    `json:"description"`
		OppositeParty  string    `json:"opposite_party"`
		OppositeLawyer string    `json:"opposite_lawyer"`
		CNRNumber      string    `json:"cnr_number"`
		CreatedAt      time.Time `json:"created_at"`
	}

	cases := []Case{}
	for rows.Next() {
		var cs Case
		rows.Scan(
			&cs.ID, &cs.CaseNumber, &cs.CaseTitle,
			&cs.CaseType, &cs.CourtName, &cs.CourtLocation,
			&cs.JudgeName, &cs.Status, &cs.Priority,
			&cs.Description, &cs.OppositeParty,
			&cs.OppositeLawyer, &cs.CNRNumber, &cs.CreatedAt,
		)
		cases = append(cases, cs)
	}
	utils.Success(c, http.StatusOK, "Cases fetched", cases)
}

// ─── MY HEARINGS ─────────────────────────────
func GetMyHearings(c *gin.Context) {
	userEmail, ok := portalClientEmail(c)
	if !ok {
		utils.Success(c, http.StatusOK, "Hearings fetched", []interface{}{})
		return
	}

	rows, err := config.DB.Query(`
		SELECT h.id,
		       COALESCE(h.case_id::text,''),
		       h.hearing_date::text,
		       COALESCE(h.court_name,''),
		       COALESCE(h.purpose,''),
		       h.status,
		       COALESCE(cs.case_title,''),
		       COALESCE(h.judge_name,''),
		       COALESCE(h.court_room,''),
		       COALESCE(h.hearing_time::text,''),
		       COALESCE(h.order_summary,''),
		       COALESCE(h.remarks,''),
		       COALESCE(h.next_date::text,'')
		FROM hearings h
		LEFT JOIN cases cs ON h.case_id = cs.id
		WHERE cs.client_id IN (SELECT id FROM clients WHERE lower(email) = $1)
		ORDER BY h.hearing_date ASC
	`, userEmail)

	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch hearings", err.Error())
		return
	}
	defer rows.Close()

	type Hearing struct {
		ID           string `json:"id"`
		CaseID       string `json:"case_id"`
		HearingDate  string `json:"hearing_date"`
		CourtName    string `json:"court_name"`
		Purpose      string `json:"purpose"`
		Status       string `json:"status"`
		CaseTitle    string `json:"case_title"`
		JudgeName    string `json:"judge_name"`
		CourtRoom    string `json:"court_room"`
		HearingTime  string `json:"hearing_time"`
		OrderSummary string `json:"order_summary"`
		Remarks      string `json:"remarks"`
		NextDate     string `json:"next_date"`
	}

	hearings := []Hearing{}
	for rows.Next() {
		var h Hearing
		rows.Scan(
			&h.ID, &h.CaseID, &h.HearingDate, &h.CourtName,
			&h.Purpose, &h.Status, &h.CaseTitle,
			&h.JudgeName, &h.CourtRoom, &h.HearingTime,
			&h.OrderSummary, &h.Remarks, &h.NextDate,
		)
		hearings = append(hearings, h)
	}
	utils.Success(c, http.StatusOK, "Hearings fetched", hearings)
}

// ─── MY DOCUMENTS ────────────────────────────
func GetMyDocuments(c *gin.Context) {
	userEmail, ok := portalClientEmail(c)
	if !ok {
		utils.Success(c, http.StatusOK, "Documents fetched", []interface{}{})
		return
	}
	userID := utils.UserID(c)

	// One query for both cases, matching on every clients row that carries the
	// caller's address rather than an arbitrary first match, and comparing
	// email case-insensitively — `cl.email = $3` missed a client stored as
	// "Name@Firm.com" and quietly showed them nothing.
	rows, err := config.DB.Query(`
		SELECT d.id, d.file_name, COALESCE(d.file_type,''),
		       COALESCE(d.category,''), COALESCE(d.file_url,''),
		       COALESCE(d.description,''),
		       COALESCE(d.case_id::text,''),
		       d.created_at
		FROM documents d
		LEFT JOIN clients cl ON d.client_id = cl.id
		WHERE (
		  d.uploaded_by = $1::uuid
		  OR lower(cl.email) = $2
		  OR d.client_id IN (SELECT id FROM clients WHERE lower(email) = $2)
		  OR d.case_id IN (
		    SELECT id FROM cases
		    WHERE client_id IN (SELECT id FROM clients WHERE lower(email) = $2)
		  )
		)
		AND d.is_archived = false
		ORDER BY d.created_at DESC
	`, userID, userEmail)

	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch documents", err.Error())
		return
	}
	defer rows.Close()

	type Doc struct {
		ID          string    `json:"id"`
		FileName    string    `json:"file_name"`
		FileType    string    `json:"file_type"`
		Category    string    `json:"category"`
		FileURL     string    `json:"file_url"`
		Description string    `json:"description"`
		CaseID      string    `json:"case_id"`
		CreatedAt   time.Time `json:"created_at"`
	}

	docs := []Doc{}
	for rows.Next() {
		var d Doc
		rows.Scan(
			&d.ID, &d.FileName, &d.FileType,
			&d.Category, &d.FileURL, &d.Description,
			&d.CaseID, &d.CreatedAt,
		)
		docs = append(docs, d)
	}
	utils.Success(c, http.StatusOK, "Documents fetched", docs)
}

// GetMyDocument returns one document's full content (including the inline
// base64 file body) so the client portal can open/download a file it
// uploaded — GetMyDocuments deliberately omits file_content for the list view.
//
// Scoped with the same ownership clause as GetMyDocuments rather than
// requireFirmResource's firm-wide check: a client must only ever reach their
// own documents, not every document belonging to any client at their lawyer's
// firm.
func GetMyDocument(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "not a uuid")
		return
	}
	userEmail, ok := portalClientEmail(c)
	if !ok {
		utils.Error(c, http.StatusNotFound, "Document not found", "no portal identity")
		return
	}
	userID := utils.UserID(c)

	var d struct {
		ID          string `json:"id"`
		FileName    string `json:"file_name"`
		FileURL     string `json:"file_url"`
		FileContent string `json:"file_content"`
		FileType    string `json:"file_type"`
		Category    string `json:"category"`
		FileSize    int    `json:"file_size"`
		MimeType    string `json:"mime_type"`
	}
	err := config.DB.QueryRow(`
		SELECT d.id, d.file_name, COALESCE(d.file_url,''),
		       COALESCE(d.file_content,''), COALESCE(d.file_type,''),
		       COALESCE(d.category,''), COALESCE(d.file_size,0),
		       COALESCE(d.mime_type,'')
		FROM documents d
		LEFT JOIN clients cl ON d.client_id = cl.id
		WHERE d.id = $1::uuid
		  AND d.is_archived = false
		  AND (
		    d.uploaded_by = $2::uuid
		    OR lower(cl.email) = $3
		    OR d.client_id IN (SELECT id FROM clients WHERE lower(email) = $3)
		    OR d.case_id IN (
		      SELECT id FROM cases
		      WHERE client_id IN (SELECT id FROM clients WHERE lower(email) = $3)
		    )
		  )
	`, id, userID, userEmail).Scan(&d.ID, &d.FileName, &d.FileURL, &d.FileContent,
		&d.FileType, &d.Category, &d.FileSize, &d.MimeType)
	if err != nil {
		utils.Error(c, http.StatusNotFound, "Document not found", err.Error())
		return
	}
	utils.Success(c, http.StatusOK, "Document fetched", d)
}

// ─── MY INVOICES ─────────────────────────────
func GetMyInvoices(c *gin.Context) {
	userEmail, ok := portalClientEmail(c)
	if !ok {
		utils.Success(c, http.StatusOK, "Invoices fetched", []interface{}{})
		return
	}

	rows, err := config.DB.Query(`
		SELECT i.id, i.invoice_number,
		       COALESCE(i.subtotal,0), COALESCE(i.tax_percent,0), COALESCE(i.tax_amount,0),
		       COALESCE(i.platform_fee,0), i.total_amount,
		       COALESCE(i.paid_amount,0), i.status, i.issue_date::text,
		       COALESCE(i.due_date::text,''), COALESCE(i.notes,'')
		FROM invoices i
		WHERE i.client_id IN (SELECT id FROM clients WHERE lower(email) = $1)
		ORDER BY i.created_at DESC
	`, userEmail)

	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch invoices", err.Error())
		return
	}
	defer rows.Close()

	type Invoice struct {
		ID            string  `json:"id"`
		InvoiceNumber string  `json:"invoice_number"`
		Subtotal      float64 `json:"subtotal"`
		GSTRate       float64 `json:"gst_rate"`
		GSTAmount     float64 `json:"gst_amount"`
		PlatformFee   float64 `json:"platform_fee"`
		TotalAmount   float64 `json:"total_amount"`
		PaidAmount    float64 `json:"paid_amount"`
		Status        string  `json:"status"`
		IssueDate     string  `json:"issue_date"`
		DueDate       string  `json:"due_date"`
		Notes         string  `json:"notes"`
	}

	invoices := []Invoice{}
	for rows.Next() {
		var inv Invoice
		rows.Scan(
			&inv.ID, &inv.InvoiceNumber, &inv.Subtotal, &inv.GSTRate, &inv.GSTAmount,
			&inv.PlatformFee, &inv.TotalAmount,
			&inv.PaidAmount, &inv.Status, &inv.IssueDate,
			&inv.DueDate, &inv.Notes,
		)
		invoices = append(invoices, inv)
	}
	utils.Success(c, http.StatusOK, "Invoices fetched", invoices)
}

// GetMyInvoice - a single invoice, scoped to the calling client the same way
// GetMyInvoices is.
//
// Added because payment_screen.dart (the client's own pay-this-invoice
// screen) was calling GET /invoices/:id — the firm-staff-only route
// (billed.GET("/invoices/:id", GetInvoice), gated by RequireFirmStaff(),
// which explicitly excludes the 'client' role) — and so was silently
// getting a 403 on every load. The screen swallowed the error and rendered
// with empty bank details; the client never saw them, and would never have
// seen the GST/platform-fee breakdown added alongside this either. This is
// the portal-scoped equivalent of GetInvoice.
func GetMyInvoice(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "not a uuid")
		return
	}
	userEmail, ok := portalClientEmail(c)
	if !ok {
		utils.Error(c, http.StatusNotFound, "Invoice not found", "")
		return
	}

	var inv struct {
		ID                string  `json:"id"`
		InvoiceNumber     string  `json:"invoice_number"`
		Subtotal          float64 `json:"subtotal"`
		GSTRate           float64 `json:"gst_rate"`
		GSTAmount         float64 `json:"gst_amount"`
		PlatformFee       float64 `json:"platform_fee"`
		TotalAmount       float64 `json:"total_amount"`
		PaidAmount        float64 `json:"paid_amount"`
		Status            string  `json:"status"`
		IssueDate         string  `json:"issue_date"`
		DueDate           string  `json:"due_date"`
		Notes             string  `json:"notes"`
		ClientName        string  `json:"client_name"`
		UPIID             string  `json:"upi_id"`
		BankAccountName   string  `json:"bank_account_name"`
		BankAccountNumber string  `json:"bank_account_number"`
		BankIFSC          string  `json:"bank_ifsc"`
		BankName          string  `json:"bank_name"`
	}
	err := config.DB.QueryRow(`
		SELECT i.id, i.invoice_number,
		       COALESCE(i.subtotal,0), COALESCE(i.tax_percent,0), COALESCE(i.tax_amount,0),
		       COALESCE(i.platform_fee,0), i.total_amount, COALESCE(i.paid_amount,0),
		       i.status, i.issue_date::text, COALESCE(i.due_date::text,''),
		       COALESCE(i.notes,''), COALESCE(cl.name,''),
		       COALESCE(i.upi_id, f.upi_id, ''),
		       COALESCE(i.bank_account_name, f.bank_account_name, ''),
		       COALESCE(i.bank_account_number, f.bank_account_number, ''),
		       COALESCE(i.bank_ifsc, f.bank_ifsc, ''),
		       COALESCE(i.bank_name, f.bank_name, '')
		FROM invoices i
		LEFT JOIN clients cl ON i.client_id = cl.id
		LEFT JOIN firms f ON i.firm_id = f.id
		WHERE i.id = $1::uuid
		  AND i.client_id IN (SELECT id FROM clients WHERE lower(email) = $2)
	`, id, userEmail).Scan(
		&inv.ID, &inv.InvoiceNumber, &inv.Subtotal, &inv.GSTRate, &inv.GSTAmount,
		&inv.PlatformFee, &inv.TotalAmount, &inv.PaidAmount,
		&inv.Status, &inv.IssueDate, &inv.DueDate, &inv.Notes, &inv.ClientName,
		&inv.UPIID, &inv.BankAccountName, &inv.BankAccountNumber,
		&inv.BankIFSC, &inv.BankName)
	if err != nil {
		utils.Error(c, http.StatusNotFound, "Invoice not found", err.Error())
		return
	}
	utils.Success(c, http.StatusOK, "Invoice fetched", inv)
}
