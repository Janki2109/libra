package controllers

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"libra/config"
	"libra/services"
	"libra/utils"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

// ─── DOCUMENTS ───────────────────────────────

func GetDocuments(c *gin.Context) {
	firmID, ok := utils.RequireFirm(c)
	if !ok {
		return
	}
	// The fallback query here returned the 100 most recent documents belonging
	// to every firm on the platform whenever the scoped query errored — client
	// case files included.
	page := ParsePagination(c)
	clientID := c.Query("client_id")
	caseID := c.Query("case_id")

	// file_content is deliberately NOT selected. It holds the whole file as
	// base64 inline in the row, so listing 25 documents used to drag up to
	// 200 MB of file bodies through the connection pool and into the response
	// just to render a list of names. Fetch a document's bytes from
	// GET /documents/:id when the user actually opens it.
	rows, err := config.DB.Query(`
		SELECT id, file_name, COALESCE(file_type,''), COALESCE(category,''),
		       COALESCE(file_url,''),
		       COALESCE(file_size,0), COALESCE(mime_type,''),
		       COALESCE(uploaded_by_role,''), is_archived, created_at
		FROM documents
		WHERE firm_id = $1::uuid AND is_archived = false
		  AND ($4 = '' OR client_id = $4::uuid)
		  AND ($5 = '' OR case_id = $5::uuid)
		ORDER BY created_at DESC
		LIMIT $2 OFFSET $3
	`, firmID, page.Limit, page.Offset, clientID, caseID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch documents", err.Error())
		return
	}
	defer rows.Close()

	type Doc struct {
		ID             string    `json:"id"`
		FileName       string    `json:"file_name"`
		FileType       string    `json:"file_type"`
		Category       string    `json:"category"`
		FileURL        string    `json:"file_url"`
		FileSize       int       `json:"file_size"`
		MimeType       string    `json:"mime_type"`
		UploadedByRole string    `json:"uploaded_by_role"`
		IsArchived     bool      `json:"is_archived"`
		CreatedAt      time.Time `json:"created_at"`
	}
	docs := []Doc{}
	for rows.Next() {
		var d Doc
		if err := rows.Scan(&d.ID, &d.FileName, &d.FileType, &d.Category,
			&d.FileURL, &d.FileSize, &d.MimeType,
			&d.UploadedByRole, &d.IsArchived, &d.CreatedAt); err != nil {
			utils.Error(c, http.StatusInternalServerError, "Failed to read documents", err.Error())
			return
		}
		docs = append(docs, d)
	}
	utils.SuccessWithMeta(c, http.StatusOK, "Documents fetched", docs, page.Meta(len(docs)))
}

func UploadDocument(c *gin.Context) {
	userID := utils.UserID(c)
	role := utils.Role(c)

	var req struct {
		FileName       string `json:"file_name" binding:"required"`
		FileType       string `json:"file_type"`
		FileURL        string `json:"file_url"`
		FileContent    string `json:"file_content"`
		FileSize       int    `json:"file_size"`
		MimeType       string `json:"mime_type"`
		CaseID         string `json:"case_id"`
		ClientID       string `json:"client_id"`
		Category       string `json:"category"`
		Description    string `json:"description"`
		UploadedByRole string `json:"uploaded_by_role"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}

	fID := utils.FirmID(c)
	if fID == "" && role == "client" {
		// A client who signed up directly (ClientRegister) carries no firm_id
		// on their token — RequireFirm always 403'd them here before this
		// request was ever evaluated, so a self-registered client could never
		// upload a document. Their only link to a firm is through a lawyer
		// they've consulted, so fall back to the firm of their most recent
		// consultation rather than requiring a pre-existing tenant claim.
		if err := config.DB.QueryRow(`
			SELECT u.firm_id::text FROM consultations co
			JOIN users u ON co.lawyer_id = u.id
			WHERE co.client_id = $1::uuid AND u.firm_id IS NOT NULL
			ORDER BY co.created_at DESC LIMIT 1
		`, userID).Scan(&fID); err != nil || fID == "" {
			utils.Error(c, http.StatusBadRequest, "No lawyer relationship found",
				"book a consultation with a lawyer before uploading documents")
			return
		}
	}
	if fID == "" {
		utils.Error(c, http.StatusForbidden, "No firm associated with this account", "missing firm context")
		return
	}

	if !belongsToFirm(tblCases, req.CaseID, fID) {
		utils.Error(c, http.StatusBadRequest, "Unknown case", "case not in caller's firm")
		return
	}
	if !belongsToFirm(tblClients, req.ClientID, fID) {
		utils.Error(c, http.StatusBadRequest, "Unknown client", "client not in caller's firm")
		return
	}

	// uploaded_by_role is taken from the verified JWT claim, not from the
	// request body. A client could previously claim to be a "lawyer" upload
	// and vice versa simply by setting the field.
	uploadedByRole := role

	// file_content holds a base64 payload inline in the row. Without a ceiling
	// a single request can push an arbitrarily large string into Postgres.
	if len(req.FileContent) > maxInlineDocumentBytes {
		utils.Error(c, http.StatusRequestEntityTooLarge,
			"File too large", "inline document exceeds limit")
		return
	}

	id := uuid.New().String()
	_, err := config.DB.Exec(`
		INSERT INTO documents (id, firm_id, case_id, client_id, uploaded_by,
		file_name, file_type, file_url, file_content, file_size, mime_type,
		category, description, uploaded_by_role)
		VALUES ($1, $2::uuid, $3, $4, $5::uuid, $6, $7, $8, $9, $10, $11, $12, $13, $14)
	`, id, fID, nullIfEmpty(req.CaseID), nullIfEmpty(req.ClientID), userID,
		req.FileName, req.FileType, req.FileURL,
		req.FileContent, req.FileSize, req.MimeType,
		req.Category, req.Description, uploadedByRole)

	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to upload document", err.Error())
		return
	}

	// ✅ Notify lawyer when client uploads
	if uploadedByRole == "client" {
		var lawyerID, firmIDStr string
		config.DB.QueryRow(`
			SELECT cr.lawyer_id::text, cr.firm_id::text
			FROM chat_rooms cr
			JOIN clients cl ON cr.client_id = cl.id
			JOIN users u ON lower(u.email) = lower(cl.email)
			WHERE u.id = $1::uuid LIMIT 1
		`, userID).Scan(&lawyerID, &firmIDStr)

		if lawyerID != "" {
			utils.Notify(lawyerID, firmIDStr,
				"📁 New Document from Client",
				fmt.Sprintf("Client uploaded: %s", req.FileName), "general")
		}
	}

	utils.Success(c, http.StatusCreated, "Document uploaded!", gin.H{"id": id})
}

// maxInlineDocumentBytes caps a base64 payload stored directly in the row.
// Roughly 8 MB of encoded text, i.e. about a 6 MB file.
const maxInlineDocumentBytes = 8 << 20

func GetDocument(c *gin.Context) {
	id := c.Param("id")
	firmID, ok := requireFirmResource(c, tblDocuments, id)
	if !ok {
		return
	}
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
		SELECT id, file_name, COALESCE(file_url,''),
		COALESCE(file_content,''), COALESCE(file_type,''),
		COALESCE(category,''), COALESCE(file_size,0), COALESCE(mime_type,'')
		FROM documents WHERE id=$1::uuid AND firm_id=$2::uuid
	`, id, firmID).Scan(&d.ID, &d.FileName, &d.FileURL, &d.FileContent,
		&d.FileType, &d.Category, &d.FileSize, &d.MimeType)
	// A real DB/connection failure was previously reported as "Document not
	// found" too, which told a user staring at a network blip that their
	// file had been deleted.
	if err == sql.ErrNoRows {
		utils.Error(c, http.StatusNotFound, "Document not found", "")
		return
	}
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to load document", err.Error())
		return
	}
	utils.Success(c, http.StatusOK, "Document fetched", d)
}

func DeleteDocument(c *gin.Context) {
	id := c.Param("id")
	firmID, ok := requireFirmResource(c, tblDocuments, id)
	if !ok {
		return
	}
	_, err := config.DB.Exec(
		"UPDATE documents SET is_archived=true WHERE id=$1::uuid AND firm_id=$2::uuid",
		id, firmID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to archive document", err.Error())
		return
	}
	utils.Success(c, http.StatusOK, "Document archived", nil)
}

// ─── BILLING ─────────────────────────────────

func GetInvoices(c *gin.Context) {
	firmID, ok := utils.RequireFirm(c)
	if !ok {
		return
	}

	page := ParsePagination(c)
	status := c.Query("status")

	rows, err := config.DB.Query(`
		SELECT i.id, i.invoice_number, i.total_amount, COALESCE(i.paid_amount,0),
		       i.status, i.issue_date::text, COALESCE(cl.name,'')
		FROM invoices i
		LEFT JOIN clients cl ON i.client_id = cl.id
		WHERE i.firm_id = $1::uuid
		  AND ($2 = '' OR i.status = $2)
		ORDER BY i.created_at DESC
		LIMIT $3 OFFSET $4
	`, firmID, status, page.Limit, page.Offset)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch invoices", err.Error())
		return
	}
	defer rows.Close()

	type Invoice struct {
		ID            string  `json:"id"`
		InvoiceNumber string  `json:"invoice_number"`
		TotalAmount   float64 `json:"total_amount"`
		PaidAmount    float64 `json:"paid_amount"`
		Status        string  `json:"status"`
		IssueDate     string  `json:"issue_date"`
		ClientName    string  `json:"client_name"`
	}
	invoices := []Invoice{}
	for rows.Next() {
		var inv Invoice
		rows.Scan(&inv.ID, &inv.InvoiceNumber, &inv.TotalAmount,
			&inv.PaidAmount, &inv.Status, &inv.IssueDate, &inv.ClientName)
		invoices = append(invoices, inv)
	}
	utils.SuccessWithMeta(c, http.StatusOK, "Invoices fetched", invoices, page.Meta(len(invoices)))
}

// CreateInvoice — GST (18%) and the ₹100 platform fee are mandatory and
// computed here, never accepted from the request. The old version trusted
// req.TotalAmount outright (whatever the Flutter app's local slider/subtotal
// math produced), which is exactly the "modify the frontend request
// manually" gap: nothing stopped a caller from POSTing any total at all.
// Now the lawyer's Subtotal is the only money value this endpoint reads from
// the client; tax_percent/tax_amount/total_amount in the request (if a
// caller sends them) are ignored and recomputed via
// services.ComputeInvoiceBreakdown.
func CreateInvoice(c *gin.Context) {
	firmID, ok := utils.RequireFirm(c)
	if !ok {
		return
	}
	userID := utils.UserID(c)

	var req struct {
		ClientID          string  `json:"client_id"`
		CaseID            string  `json:"case_id"`
		InvoiceNumber     string  `json:"invoice_number" binding:"required"`
		IssueDate         string  `json:"issue_date"`
		DueDate           string  `json:"due_date"`
		Subtotal          float64 `json:"subtotal" binding:"gte=0"`
		Notes             string  `json:"notes"`
		UPIID             string  `json:"upi_id"`
		BankAccountName   string  `json:"bank_account_name"`
		BankAccountNumber string  `json:"bank_account_number"`
		BankIFSC          string  `json:"bank_ifsc"`
		BankName          string  `json:"bank_name"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}

	fID := firmID

	if !belongsToFirm(tblClients, req.ClientID, fID) {
		utils.Error(c, http.StatusBadRequest, "Unknown client", "client not in caller's firm")
		return
	}
	if !belongsToFirm(tblCases, req.CaseID, fID) {
		utils.Error(c, http.StatusBadRequest, "Unknown case", "case not in caller's firm")
		return
	}

	if req.IssueDate == "" {
		req.IssueDate = time.Now().Format("2006-01-02")
	}

	gstRate, gstAmount, platformFee, total := services.ComputeInvoiceBreakdown(req.Subtotal)

	id := uuid.New().String()
	_, err := config.DB.Exec(`
		INSERT INTO invoices (id, firm_id, client_id, case_id, invoice_number,
		issue_date, due_date, subtotal, tax_percent, tax_amount, platform_fee,
		total_amount, notes, created_by,
		upi_id, bank_account_name, bank_account_number, bank_ifsc, bank_name)
		VALUES ($1, $2::uuid, $3, $4, $5, $6, $7, $8, $9, $10, $11,
		$12, $13, $14::uuid,
		$15, $16, $17, $18, $19)
	`, id, fID, nullIfEmpty(req.ClientID), nullIfEmpty(req.CaseID), req.InvoiceNumber,
		req.IssueDate, nullIfEmpty(req.DueDate), req.Subtotal, gstRate, gstAmount, platformFee,
		total, req.Notes, userID,
		req.UPIID, req.BankAccountName, req.BankAccountNumber,
		req.BankIFSC, req.BankName)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to create invoice", err.Error())
		return
	}

	if req.ClientID != "" {
		var clientUserID string
		config.DB.QueryRow(`
			SELECT u.id FROM users u
			JOIN clients cl ON lower(u.email) = lower(cl.email)
			WHERE cl.id = $1::uuid AND u.is_active = true
			LIMIT 1
		`, req.ClientID).Scan(&clientUserID)

		if clientUserID != "" {
			utils.NotifyWithRef(clientUserID, fID,
				"💰 New Invoice Received",
				fmt.Sprintf("Invoice %s: ₹%.2f (incl. 18%% GST + ₹100 platform fee) is pending payment. Due: %s",
					req.InvoiceNumber, total, req.DueDate),
				"payment_reminder", id, "invoice")
		}
	}

	utils.Success(c, http.StatusCreated, "Invoice created!", gin.H{
		"id": id, "subtotal": req.Subtotal, "gst_rate": gstRate, "gst_amount": gstAmount,
		"platform_fee": platformFee, "total_amount": total,
	})
}

func GetInvoice(c *gin.Context) {
	id := c.Param("id")
	firmID, ok := requireFirmResource(c, tblInvoices, id)
	if !ok {
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
		TransactionID     string  `json:"transaction_id"`
		PaymentSlipURL    string  `json:"payment_slip_url"`
	}
	err := config.DB.QueryRow(`
		SELECT i.id, i.invoice_number,
		       COALESCE(i.subtotal,0), COALESCE(i.tax_percent,0), COALESCE(i.tax_amount,0),
		       COALESCE(i.platform_fee,0), i.total_amount, i.paid_amount,
		       i.status, i.issue_date::text, COALESCE(i.due_date::text,''),
		       COALESCE(i.notes,''), COALESCE(cl.name,''),
		       COALESCE(i.upi_id, f.upi_id, ''),
		       COALESCE(i.bank_account_name, f.bank_account_name, ''),
		       COALESCE(i.bank_account_number, f.bank_account_number, ''),
		       COALESCE(i.bank_ifsc, f.bank_ifsc, ''),
		       COALESCE(i.bank_name, f.bank_name, ''),
		       COALESCE(i.transaction_id,''),
		       COALESCE(i.payment_slip_url,'')
		FROM invoices i
		LEFT JOIN clients cl ON i.client_id = cl.id
		LEFT JOIN firms f ON i.firm_id = f.id
		WHERE i.id = $1::uuid AND i.firm_id = $2::uuid
	`, id, firmID).Scan(
		&inv.ID, &inv.InvoiceNumber, &inv.Subtotal, &inv.GSTRate, &inv.GSTAmount,
		&inv.PlatformFee, &inv.TotalAmount, &inv.PaidAmount,
		&inv.Status, &inv.IssueDate, &inv.DueDate, &inv.Notes, &inv.ClientName,
		&inv.UPIID, &inv.BankAccountName, &inv.BankAccountNumber,
		&inv.BankIFSC, &inv.BankName, &inv.TransactionID, &inv.PaymentSlipURL)
	if err != nil {
		utils.Error(c, http.StatusNotFound, "Invoice not found", err.Error())
		return
	}
	utils.Success(c, http.StatusOK, "Invoice fetched", inv)
}

func UpdateInvoice(c *gin.Context) {
	id := c.Param("id")
	firmID, ok := requireFirmResource(c, tblInvoices, id)
	if !ok {
		return
	}
	var req struct {
		Status         string `json:"status"`
		Notes          string `json:"notes"`
		TransactionID  string `json:"transaction_id"`
		PaymentSlipURL string `json:"payment_slip_url"`
	}
	// The bind error used to be discarded, so a malformed body silently became
	// an all-empty update.
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}

	// 'paid' is set by the payment paths, which also move paid_amount. Letting
	// a client PUT it directly marks an invoice settled without any money.
	if req.Status == "paid" {
		utils.Error(c, http.StatusBadRequest,
			"Cannot set paid directly", "record a payment instead")
		return
	}

	// $N::text on every placeholder — see UpdateProfile (auth_controller.go)
	// for why: this same CASE-with-reused-placeholder shape is what broke
	// UpdateCase in production with "inconsistent types deduced".
	_, err := config.DB.Exec(`
		UPDATE invoices SET
		status = CASE WHEN $1::text != '' THEN $1::text ELSE status END,
		notes = CASE WHEN $2::text != '' THEN $2::text ELSE notes END,
		transaction_id = CASE WHEN $3::text != '' THEN $3::text ELSE COALESCE(transaction_id,'') END,
		payment_slip_url = CASE WHEN $4::text != '' THEN $4::text ELSE COALESCE(payment_slip_url,'') END,
		updated_at = NOW()
		WHERE id = $5::uuid AND firm_id = $6::uuid
	`, req.Status, req.Notes, req.TransactionID, req.PaymentSlipURL, id, firmID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to update invoice", err.Error())
		return
	}
	utils.Success(c, http.StatusOK, "Invoice updated", nil)
}

func GetPayments(c *gin.Context) {
	firmID, ok := utils.RequireFirm(c)
	if !ok {
		return
	}
	page := ParsePagination(c)
	// status filters against verification_status ('verified'/'rejected'/
	// 'pending') so the Payment Verification screen's "Verified" tab (where
	// the Pay Back button lives) can ask for only payments it's actually
	// allowed to refund, instead of pulling every payment and filtering
	// client-side.
	status := c.Query("status")
	rows, err := config.DB.Query(`
		SELECT p.id, p.amount, p.payment_date::text,
		COALESCE(p.payment_method,''), COALESCE(p.notes,''),
		COALESCE(p.transaction_id,''), COALESCE(cl.name,''),
		COALESCE(i.invoice_number,''), COALESCE(p.verification_status,'verified'),
		COALESCE(p.refund_status,''), COALESCE(p.refunded_amount,0)
		FROM payments p
		LEFT JOIN invoices i ON p.invoice_id = i.id
		LEFT JOIN clients cl ON p.client_id = cl.id
		WHERE p.firm_id=$1::uuid
		  AND ($4 = '' OR COALESCE(p.verification_status,'verified') = $4)
		ORDER BY p.created_at DESC
		LIMIT $2 OFFSET $3
	`, firmID, page.Limit, page.Offset, status)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch payments", err.Error())
		return
	}
	defer rows.Close()

	type Payment struct {
		ID                string  `json:"id"`
		Amount            float64 `json:"amount"`
		PaymentDate       string  `json:"payment_date"`
		PaymentMethod     string  `json:"payment_method"`
		Notes             string  `json:"notes"`
		TransactionID     string  `json:"transaction_id"`
		ClientName        string  `json:"client_name"`
		InvoiceNumber     string  `json:"invoice_number"`
		VerificationState string  `json:"verification_status"`
		RefundStatus      string  `json:"refund_status"`
		RefundedAmount    float64 `json:"refunded_amount"`
	}
	payments := []Payment{}
	for rows.Next() {
		var p Payment
		if err := rows.Scan(&p.ID, &p.Amount, &p.PaymentDate, &p.PaymentMethod, &p.Notes,
			&p.TransactionID, &p.ClientName, &p.InvoiceNumber, &p.VerificationState,
			&p.RefundStatus, &p.RefundedAmount); err != nil {
			utils.Error(c, http.StatusInternalServerError, "Failed to read payments", err.Error())
			return
		}
		payments = append(payments, p)
	}
	utils.SuccessWithMeta(c, http.StatusOK, "Payments fetched", payments, page.Meta(len(payments)))
}

func CreatePayment(c *gin.Context) {
	firmID, ok := utils.RequireFirm(c)
	if !ok {
		return
	}
	userID := utils.UserID(c)

	var req struct {
		InvoiceID      string  `json:"invoice_id"`
		ClientID       string  `json:"client_id"`
		Amount         float64 `json:"amount" binding:"required,gt=0"`
		PaymentDate    string  `json:"payment_date" binding:"required"`
		PaymentMethod  string  `json:"payment_method"`
		TransactionID  string  `json:"transaction_id"`
		PaymentSlipURL string  `json:"payment_slip_url"`
		Notes          string  `json:"notes"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}

	fID := firmID

	// Attaching a payment to another firm's invoice used to be possible, which
	// would have marked their invoice paid.
	if !belongsToFirm(tblInvoices, req.InvoiceID, fID) {
		utils.Error(c, http.StatusBadRequest, "Unknown invoice", "invoice not in caller's firm")
		return
	}
	if !belongsToFirm(tblClients, req.ClientID, fID) {
		utils.Error(c, http.StatusBadRequest, "Unknown client", "client not in caller's firm")
		return
	}

	// This endpoint is now reachable by the client themselves, not just firm
	// staff (see routes.go) — so a client-role caller must be restricted to
	// their own client record, or one client could submit a payment claim
	// against any other client's invoice in the same firm.
	if !firmStaffRole(utils.Role(c)) {
		callerEmail, ok := portalClientEmail(c)
		if !ok {
			utils.Error(c, http.StatusForbidden, "Not authorized", "")
			return
		}
		var ownClientID string
		config.DB.QueryRow(`
			SELECT id::text FROM clients WHERE lower(email) = $1 AND firm_id = $2::uuid
		`, callerEmail, fID).Scan(&ownClientID)
		if ownClientID == "" || ownClientID != req.ClientID {
			utils.Error(c, http.StatusForbidden, "You can only submit payment for your own invoice", "")
			return
		}
	}

	// The claimed amount used to be trusted outright and credited to the
	// invoice immediately (see the paid_amount update below) — before any
	// lawyer verification — so a client (or a hand-crafted request) could
	// claim any figure at all, including far more than the invoice's actual
	// remaining balance, and have it marked paid on the spot. This is the
	// same "never trust an amount from the frontend" rule CreateInvoice now
	// enforces for GST/platform fee, applied at the other end of the same
	// invoice: nothing here may push paid_amount past total_amount.
	if req.InvoiceID != "" {
		var total, paid float64
		if err := config.DB.QueryRow(`
			SELECT total_amount, COALESCE(paid_amount,0) FROM invoices WHERE id=$1::uuid AND firm_id=$2::uuid
		`, req.InvoiceID, fID).Scan(&total, &paid); err != nil {
			utils.Error(c, http.StatusBadRequest, "Unknown invoice", err.Error())
			return
		}
		due := services.RoundMoney(total - paid)
		if req.Amount > due+0.01 {
			utils.Error(c, http.StatusBadRequest,
				fmt.Sprintf("Amount exceeds the invoice's remaining balance of ₹%.2f", due),
				"claimed amount is greater than what is actually due")
			return
		}
	}

	id := uuid.New().String()
	_, err := config.DB.Exec(`
		INSERT INTO payments (id, firm_id, invoice_id, client_id, amount,
		payment_date, payment_method, transaction_id, notes, created_by)
		VALUES ($1, $2::uuid, $3, $4, $5, $6, $7, $8, $9, $10::uuid)
	`, id, fID, nullIfEmpty(req.InvoiceID), nullIfEmpty(req.ClientID), req.Amount,
		req.PaymentDate, req.PaymentMethod, nullIfEmpty(req.TransactionID),
		req.Notes, userID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to create payment", err.Error())
		return
	}

	if req.InvoiceID != "" {
		if firmStaffRole(utils.Role(c)) {
			// A lawyer/staff member is recording money they personally
			// confirmed (cash in hand, a bank statement they checked) — credit
			// it immediately. One statement, not two: the old pair could
			// interleave with a concurrent payment and leave status
			// disagreeing with paid_amount.
			config.DB.Exec(`
				UPDATE invoices SET
				  paid_amount = COALESCE(paid_amount,0) + $1,
				  status = CASE
				    WHEN COALESCE(paid_amount,0) + $1 >= total_amount THEN 'paid'
				    WHEN COALESCE(paid_amount,0) + $1 > 0 THEN 'partial'
				    ELSE status
				  END,
				  updated_at = NOW()
				WHERE id=$2::uuid AND firm_id=$3::uuid
			`, req.Amount, req.InvoiceID, fID)
		} else {
			// A client is only ever submitting an unverified claim (a UTR they
			// typed in, a screenshot) — this used to credit paid_amount and
			// flip the invoice straight to 'paid'/'partial' on the client's own
			// say-so, with no lawyer review at all, and the invoice never
			// reached the Payment Verification queue because nothing here ever
			// set status='pending_verification'. Now the claim just moves the
			// invoice into that queue; paid_amount/status only change once a
			// lawyer approves it via VerifyPayment. A 'paid' invoice does not
			// get bumped back to pending by a stray extra submission.
			//
			// transaction_id/payment_slip_url are stored on the invoice itself
			// (what Payment Verification's "View slip" reads) in this same
			// request — this used to be a second PUT /invoices/:id call from
			// the client, which 403'd because that route is firm-staff-only,
			// silently discarding the slip/reference every time.
			config.DB.Exec(`
				UPDATE invoices SET
				  status = 'pending_verification',
				  transaction_id = CASE WHEN $1::text != '' THEN $1::text ELSE transaction_id END,
				  payment_slip_url = CASE WHEN $2::text != '' THEN $2::text ELSE payment_slip_url END,
				  updated_at = NOW()
				WHERE id=$3::uuid AND firm_id=$4::uuid AND status != 'paid'
			`, req.TransactionID, req.PaymentSlipURL, req.InvoiceID, fID)
		}

		var invoiceCreator, invoiceNum string
		var invoiceTotal float64
		config.DB.QueryRow(`
			SELECT created_by::text, invoice_number, total_amount
			FROM invoices WHERE id=$1::uuid
		`, req.InvoiceID).Scan(&invoiceCreator, &invoiceNum, &invoiceTotal)

		if invoiceCreator != "" {
			slipMsg := ""
			if req.TransactionID != "" {
				slipMsg += fmt.Sprintf(" | TXN: %s", req.TransactionID)
			}
			utils.NotifyWithRef(invoiceCreator, fID,
				"✅ Payment Received!",
				fmt.Sprintf("Payment of ₹%.2f received for invoice %s via %s%s",
					req.Amount, invoiceNum, req.PaymentMethod, slipMsg),
				"general", id, "payment")
		}
	}

	utils.Success(c, http.StatusCreated, "Payment recorded!", gin.H{"id": id})
}

// ─── NOTIFICATIONS ───────────────────────────

func GetNotifications(c *gin.Context) {
	userID, _ := c.Get("user_id")
	rows, err := config.DB.Query(`
		SELECT id, title, COALESCE(message,''), COALESCE(type,'general'),
		is_read, created_at
		FROM notifications WHERE user_id=$1::uuid
		ORDER BY created_at DESC LIMIT 50
	`, userID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch notifications", err.Error())
		return
	}
	defer rows.Close()

	type Notif struct {
		ID        string    `json:"id"`
		Title     string    `json:"title"`
		Message   string    `json:"message"`
		Type      string    `json:"type"`
		IsRead    bool      `json:"is_read"`
		CreatedAt time.Time `json:"created_at"`
	}
	notifs := []Notif{}
	for rows.Next() {
		var n Notif
		rows.Scan(&n.ID, &n.Title, &n.Message, &n.Type, &n.IsRead, &n.CreatedAt)
		notifs = append(notifs, n)
	}
	utils.Success(c, http.StatusOK, "Notifications fetched", notifs)
}

func MarkNotificationRead(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "not a uuid")
		return
	}
	// Scoped to the caller: any user could previously mark any other user's
	// notification read.
	res, err := config.DB.Exec(
		"UPDATE notifications SET is_read=true WHERE id=$1::uuid AND user_id=$2::uuid",
		id, utils.UserID(c))
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to update notification", err.Error())
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		utils.Error(c, http.StatusNotFound, "Notification not found", "")
		return
	}
	utils.Success(c, http.StatusOK, "Marked as read", nil)
}

// ─── REPORTS ─────────────────────────────────

func GetCaseReport(c *gin.Context) {
	firmID, ok := utils.RequireFirm(c)
	if !ok {
		return
	}

	var report struct {
		Total   int `json:"total"`
		Active  int `json:"active"`
		Closed  int `json:"closed"`
		Won     int `json:"won"`
		Lost    int `json:"lost"`
		Pending int `json:"pending"`
	}

	// One pass instead of six round trips, and no `OR created_by = ...`
	// escape hatch that pulled in rows from firms the caller has left.
	err := config.DB.QueryRow(`
		SELECT COUNT(*),
		       COUNT(*) FILTER (WHERE status='active'),
		       COUNT(*) FILTER (WHERE status='closed'),
		       COUNT(*) FILTER (WHERE status='won'),
		       COUNT(*) FILTER (WHERE status='lost'),
		       COUNT(*) FILTER (WHERE status='pending')
		FROM cases WHERE firm_id = $1::uuid
	`, firmID).Scan(&report.Total, &report.Active, &report.Closed,
		&report.Won, &report.Lost, &report.Pending)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to build report", err.Error())
		return
	}

	utils.Success(c, http.StatusOK, "Case report fetched", report)
}

func GetRevenueReport(c *gin.Context) {
	firmID, ok := utils.RequireFirm(c)
	if !ok {
		return
	}

	var report struct {
		TotalInvoiced float64 `json:"total_invoiced"`
		TotalPaid     float64 `json:"total_paid"`
		TotalPending  float64 `json:"total_pending"`
	}

	err := config.DB.QueryRow(`
		SELECT COALESCE(SUM(total_amount),0), COALESCE(SUM(paid_amount),0)
		FROM invoices WHERE firm_id = $1::uuid
	`, firmID).Scan(&report.TotalInvoiced, &report.TotalPaid)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to build report", err.Error())
		return
	}

	report.TotalPending = report.TotalInvoiced - report.TotalPaid
	utils.Success(c, http.StatusOK, "Revenue report fetched", report)
}

// ─── STAFF ───────────────────────────────────

func GetStaff(c *gin.Context) {
	firmID, ok := utils.RequireFirm(c)
	if !ok {
		return
	}
	// The removed fallback listed 50 arbitrary platform users — names, emails
	// and phone numbers from every firm — to any authenticated caller.
	rows, err := config.DB.Query(`
		SELECT u.id, u.name, u.email, COALESCE(u.phone,''),
		       COALESCE(r.name,''), COALESCE(u.designation,''), u.is_active
		FROM users u
		LEFT JOIN roles r ON u.role_id = r.id
		WHERE u.firm_id = $1::uuid
		ORDER BY u.created_at DESC
	`, firmID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch staff", err.Error())
		return
	}
	defer rows.Close()

	type Staff struct {
		ID          string `json:"id"`
		Name        string `json:"name"`
		Email       string `json:"email"`
		Phone       string `json:"phone"`
		Role        string `json:"role"`
		Designation string `json:"designation"`
		IsActive    bool   `json:"is_active"`
	}
	staff := []Staff{}
	for rows.Next() {
		var s Staff
		rows.Scan(&s.ID, &s.Name, &s.Email, &s.Phone,
			&s.Role, &s.Designation, &s.IsActive)
		staff = append(staff, s)
	}
	utils.Success(c, http.StatusOK, "Staff fetched", staff)
}

// CreateStaff adds a member to the caller's existing firm.
//
// It used to simply delegate to Register, which creates a brand new firm, a new
// subscription and a new admin user. Adding a paralegal therefore spun up a
// second tenant that the inviting firm could not see, and the new account
// landed on its own free trial rather than the firm's plan.
func CreateStaff(c *gin.Context) {
	firmID, ok := utils.RequireFirm(c)
	if !ok {
		return
	}
	if !utils.IsAdmin(c) {
		utils.Error(c, http.StatusForbidden, "Only a firm admin can add staff", "insufficient role")
		return
	}

	if !enforcePlanLimit(c, firmID, limitStaff) {
		return
	}

	var req struct {
		Name        string `json:"name" binding:"required"`
		Email       string `json:"email" binding:"required,email"`
		Phone       string `json:"phone"`
		Role        string `json:"role"`
		Designation string `json:"designation"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}
	req.Phone = strings.TrimSpace(req.Phone)
	if req.Phone != "" && !utils.ValidPhone(req.Phone) {
		utils.Error(c, http.StatusBadRequest, "Please enter a valid 10-digit mobile number.", "invalid phone")
		return
	}

	role := req.Role
	switch role {
	case "lawyer", "staff", "clerk", "admin":
	case "":
		role = "staff"
	default:
		// Without this, a firm admin could mint a super_admin and take over
		// the whole platform.
		utils.Error(c, http.StatusBadRequest, "Invalid role",
			"expected one of: lawyer, staff, clerk, admin")
		return
	}

	email := normalizeEmail(req.Email)

	var taken int
	config.DB.QueryRow("SELECT COUNT(*) FROM users WHERE lower(email)=$1", email).Scan(&taken)
	if taken > 0 {
		utils.Error(c, http.StatusConflict, "Email already registered", "duplicate email")
		return
	}

	var roleID sql.NullString
	config.DB.QueryRow("SELECT id FROM roles WHERE name=$1 LIMIT 1", role).Scan(&roleID)
	if !roleID.Valid {
		utils.Error(c, http.StatusInternalServerError, "Unknown role", "roles table not seeded")
		return
	}

	password, err := generatePassword()
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to create staff", err.Error())
		return
	}
	hash, err := utils.HashPassword(password)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to create staff", err.Error())
		return
	}

	staffID := uuid.New().String()
	_, err = config.DB.Exec(`
		INSERT INTO users (id, name, email, phone, password_hash, role_id, firm_id,
		designation, is_active, email_verified, must_change_password)
		VALUES ($1, $2, $3, $4, $5, $6, $7::uuid, $8, true, false, true)
	`, staffID, req.Name, email, req.Phone, hash, roleID, firmID, req.Designation)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to create staff", err.Error())
		return
	}

	body := fmt.Sprintf(
		"Hello %s,\n\nAn account has been created for you on Libra Law.\n\n"+
			"Email: %s\nTemporary password: %s\n\n"+
			"You will be asked to choose a new password when you first sign in.\n",
		req.Name, email, password)
	if err := mailerClient().Send(email, "Your Libra Law account", body); err != nil {
		if errors.Is(err, services.ErrMailNotConfigured) && !utils.IsProduction() {
			log.Printf("[dev] staff password for %s is %s", email, password)
		} else {
			log.Printf("[staff] could not email credentials to %s: %v", email, err)
		}
	}

	utils.Success(c, http.StatusCreated, "Staff member added", gin.H{
		"id":    staffID,
		"email": email,
		"role":  role,
	})
}

func GetStaffMember(c *gin.Context) {
	id := c.Param("id")
	firmID, ok := utils.RequireFirm(c)
	if !ok {
		return
	}
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "not a uuid")
		return
	}

	var s struct {
		ID          string `json:"id"`
		Name        string `json:"name"`
		Email       string `json:"email"`
		Phone       string `json:"phone"`
		Designation string `json:"designation"`
		IsActive    bool   `json:"is_active"`
	}
	// Scoped to the firm. Any logged-in user could previously read any account
	// on the platform by id, and the scan error was discarded so a miss
	// returned an empty record with a 200.
	err := config.DB.QueryRow(`
		SELECT id, name, email, COALESCE(phone,''),
		COALESCE(designation,''), is_active
		FROM users WHERE id=$1::uuid AND firm_id=$2::uuid
	`, id, firmID).Scan(&s.ID, &s.Name, &s.Email, &s.Phone, &s.Designation, &s.IsActive)
	if err == sql.ErrNoRows {
		utils.Error(c, http.StatusNotFound, "Staff member not found", "")
		return
	}
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Database error", err.Error())
		return
	}
	utils.Success(c, http.StatusOK, "Staff member fetched", s)
}

func UpdateStaffMember(c *gin.Context) {
	id := c.Param("id")
	firmID, ok := utils.RequireFirm(c)
	if !ok {
		return
	}
	if !utils.IsAdmin(c) {
		utils.Error(c, http.StatusForbidden, "Only a firm admin can edit staff", "insufficient role")
		return
	}
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "not a uuid")
		return
	}

	var req struct {
		Name        string `json:"name"`
		Phone       string `json:"phone"`
		Designation string `json:"designation"`
		IsActive    *bool  `json:"is_active"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}
	req.Phone = strings.TrimSpace(req.Phone)
	if req.Phone != "" && !utils.ValidPhone(req.Phone) {
		utils.Error(c, http.StatusBadRequest, "Please enter a valid 10-digit mobile number.", "invalid phone")
		return
	}

	// is_active is a pointer so an omitted field leaves the account alone.
	// As a plain bool it defaulted to false, meaning a rename request also
	// deactivated the person being renamed.
	// $N::text on every text placeholder — see UpdateProfile
	// (auth_controller.go) for why: this same CASE-with-reused-placeholder
	// shape is what broke UpdateCase in production with "inconsistent types
	// deduced".
	res, err := config.DB.Exec(`
		UPDATE users SET
		  name        = CASE WHEN $1::text != '' THEN $1::text ELSE name END,
		  phone       = CASE WHEN $2::text != '' THEN $2::text ELSE phone END,
		  designation = CASE WHEN $3::text != '' THEN $3::text ELSE designation END,
		  is_active   = COALESCE($4, is_active),
		  updated_at  = NOW()
		WHERE id=$5::uuid AND firm_id=$6::uuid
	`, req.Name, req.Phone, req.Designation, req.IsActive, id, firmID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to update staff", err.Error())
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		utils.Error(c, http.StatusNotFound, "Staff member not found", "")
		return
	}
	utils.Success(c, http.StatusOK, "Staff updated", nil)
}

// ─── ADMIN ───────────────────────────────────

func GetAllUsers(c *gin.Context) {
	rows, err := config.DB.Query(`
		SELECT u.id, u.name, u.email, COALESCE(r.name,''),
		u.is_active, u.created_at
		FROM users u LEFT JOIN roles r ON u.role_id = r.id
		ORDER BY u.created_at DESC
	`)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch users", err.Error())
		return
	}
	defer rows.Close()

	type U struct {
		ID        string    `json:"id"`
		Name      string    `json:"name"`
		Email     string    `json:"email"`
		Role      string    `json:"role"`
		IsActive  bool      `json:"is_active"`
		CreatedAt time.Time `json:"created_at"`
	}
	users := []U{}
	for rows.Next() {
		var u U
		rows.Scan(&u.ID, &u.Name, &u.Email, &u.Role, &u.IsActive, &u.CreatedAt)
		users = append(users, u)
	}
	utils.Success(c, http.StatusOK, "Users fetched", users)
}

func UpdateUser(c *gin.Context) {
	id := c.Param("id")
	var req struct {
		IsActive bool `json:"is_active"`
	}
	c.ShouldBindJSON(&req)
	config.DB.Exec("UPDATE users SET is_active=$1, updated_at=NOW() WHERE id=$2::uuid",
		req.IsActive, id)
	utils.Success(c, http.StatusOK, "User updated", nil)
}

func DeleteUser(c *gin.Context) {
	id := c.Param("id")
	config.DB.Exec("UPDATE users SET is_active=false WHERE id=$1::uuid", id)
	utils.Success(c, http.StatusOK, "User deactivated", nil)
}

func GetAuditLogs(c *gin.Context) {
	firmID, ok := utils.RequireFirm(c)
	if !ok {
		return
	}

	// A firm admin sees their own firm's trail. Only the platform owner sees
	// everything — the previous query handed every firm's activity log,
	// including user names and IP addresses, to any firm admin.
	query := `
		SELECT al.id, al.action, COALESCE(al.module,''),
		COALESCE(u.name,''), COALESCE(al.ip_address,''), al.created_at
		FROM audit_logs al
		LEFT JOIN users u ON al.user_id = u.id
		WHERE al.firm_id = $1::uuid
		ORDER BY al.created_at DESC LIMIT 100`
	args := []interface{}{firmID}

	if utils.IsPlatformAdmin(c) {
		query = `
		SELECT al.id, al.action, COALESCE(al.module,''),
		COALESCE(u.name,''), COALESCE(al.ip_address,''), al.created_at
		FROM audit_logs al
		LEFT JOIN users u ON al.user_id = u.id
		ORDER BY al.created_at DESC LIMIT 100`
		args = nil
	}

	rows, err := config.DB.Query(query, args...)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch audit logs", err.Error())
		return
	}
	defer rows.Close()

	type Log struct {
		ID        string    `json:"id"`
		Action    string    `json:"action"`
		Module    string    `json:"module"`
		UserName  string    `json:"user_name"`
		IPAddress string    `json:"ip_address"`
		CreatedAt time.Time `json:"created_at"`
	}
	logs := []Log{}
	for rows.Next() {
		var l Log
		rows.Scan(&l.ID, &l.Action, &l.Module,
			&l.UserName, &l.IPAddress, &l.CreatedAt)
		logs = append(logs, l)
	}
	utils.Success(c, http.StatusOK, "Audit logs fetched", logs)
}

// ─── FIRM BANK DETAILS ───────────────────────

func GetFirmBankDetails(c *gin.Context) {
	firmID, ok := utils.RequireFirm(c)
	if !ok {
		return
	}

	var details struct {
		UPIID             string `json:"upi_id"`
		BankAccountName   string `json:"bank_account_name"`
		BankAccountNumber string `json:"bank_account_number"`
		BankIFSC          string `json:"bank_ifsc"`
		BankName          string `json:"bank_name"`
		BankBranch        string `json:"bank_branch"`
	}

	config.DB.QueryRow(`
		SELECT COALESCE(upi_id,''), COALESCE(bank_account_name,''),
		COALESCE(bank_account_number,''), COALESCE(bank_ifsc,''),
		COALESCE(bank_name,''), COALESCE(bank_branch,'')
		FROM firms WHERE id=$1::uuid
	`, firmID).Scan(
		&details.UPIID, &details.BankAccountName,
		&details.BankAccountNumber, &details.BankIFSC,
		&details.BankName, &details.BankBranch)

	utils.Success(c, http.StatusOK, "Bank details fetched", details)
}

func UpdateFirmBankDetails(c *gin.Context) {
	firmID, ok := utils.RequireFirm(c)
	if !ok {
		return
	}
	// These fields decide where every client payment lands. Any firm member —
	// a clerk, an intern, a compromised junior account — could previously
	// point them at their own account and silently redirect the firm's income.
	if !utils.IsAdmin(c) {
		utils.Error(c, http.StatusForbidden,
			"Only a firm admin can change bank details", "insufficient role")
		return
	}

	var req struct {
		UPIID             string `json:"upi_id"`
		BankAccountName   string `json:"bank_account_name"`
		BankAccountNumber string `json:"bank_account_number"`
		BankIFSC          string `json:"bank_ifsc"`
		BankName          string `json:"bank_name"`
		BankBranch        string `json:"bank_branch"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}

	_, err := config.DB.Exec(`
		UPDATE firms SET
		upi_id=$1, bank_account_name=$2, bank_account_number=$3,
		bank_ifsc=$4, bank_name=$5, bank_branch=$6, updated_at=NOW()
		WHERE id=$7::uuid
	`, req.UPIID, req.BankAccountName, req.BankAccountNumber,
		req.BankIFSC, req.BankName, req.BankBranch, firmID)

	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to update", err.Error())
		return
	}

	// Payout details changing is exactly the event a firm needs to be able to
	// review after the fact.
	config.DB.Exec(`
		INSERT INTO audit_logs (id, firm_id, user_id, action, module, ip_address)
		VALUES (gen_random_uuid(), $1::uuid, $2::uuid, 'bank_details_updated', 'firm', $3)
	`, firmID, utils.UserID(c), c.ClientIP())

	utils.Success(c, http.StatusOK, "Bank details saved!", nil)
}

// ─── ALL LAWYERS ─────────────────────────────

// GetAllLawyers powers the public lawyer directory shown to students and
// prospective clients.
//
// It used to return every lawyer's email address and phone number to any
// authenticated caller — a scraped contact list of the platform's entire
// professional user base. Contact happens through the in-app consultation
// booking instead, so the directory only carries what is needed to choose
// someone.
func GetAllLawyers(c *gin.Context) {
	// The client-facing category filter (Corporate/Tax/Labour/Consumer/...)
	// had nothing real to match against — this endpoint never returned any
	// specialization field at all, and 'designation' is a job title
	// ("Advocate", "Partner"), not a practice area. There is no dedicated
	// specialization column anywhere in the schema; the closest existing,
	// already-stored equivalent is the set of case_type values on the
	// lawyer's own firm's cases (the same Civil/Criminal/Family/Property/
	// Corporate/Labour/Tax list add_case_screen.dart already uses) —
	// GetLawyerProfile already treats case_type the same way for its "won
	// cases" track record. Reused here instead of adding a new column.
	rows, err := config.DB.Query(`
		SELECT u.id, u.name,
		       COALESCE(u.designation,'Advocate'), COALESCE(f.name,'') as firm_name,
		       COALESCE(f.city,''), COALESCE(f.state,''), COALESCE(u.avatar_url,''),
		       COALESCE((
		           SELECT string_agg(DISTINCT c.case_type, ',')
		           FROM cases c WHERE c.firm_id = u.firm_id AND c.case_type != ''
		       ), '') as practice_areas
		FROM users u
		LEFT JOIN firms f ON u.firm_id = f.id
		LEFT JOIN roles r ON u.role_id = r.id
		WHERE r.name IN ('admin','lawyer') AND u.is_active = true
		ORDER BY u.created_at DESC
		LIMIT 200
	`)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch lawyers", err.Error())
		return
	}
	defer rows.Close()

	type Lawyer struct {
		ID            string `json:"id"`
		Name          string `json:"name"`
		Designation   string `json:"designation"`
		FirmName      string `json:"firm_name"`
		City          string `json:"city"`
		State         string `json:"state"`
		AvatarURL     string `json:"avatar_url"`
		PracticeAreas string `json:"practice_areas"`
	}

	lawyers := []Lawyer{}
	for rows.Next() {
		var l Lawyer
		if err := rows.Scan(&l.ID, &l.Name, &l.Designation,
			&l.FirmName, &l.City, &l.State, &l.AvatarURL, &l.PracticeAreas); err != nil {
			utils.Error(c, http.StatusInternalServerError, "Failed to read lawyers", err.Error())
			return
		}
		lawyers = append(lawyers, l)
	}
	utils.Success(c, http.StatusOK, "Lawyers fetched", lawyers)
}

// ─── PAYMENT VERIFICATION ────────────────────

func GetPendingVerification(c *gin.Context) {
	firmID, _ := c.Get("firm_id")

	rows, err := config.DB.Query(`
		SELECT i.id, i.invoice_number, i.total_amount,
		       COALESCE(i.transaction_id,'') as transaction_id,
		       COALESCE(i.payment_slip_url,'') as payment_slip_url,
		       COALESCE(cl.name,'') as client_name,
		       COALESCE(p.id::text,'') as payment_id
		FROM invoices i
		LEFT JOIN clients cl ON i.client_id = cl.id
		LEFT JOIN payments p ON p.invoice_id = i.id
		WHERE i.firm_id = $1::uuid 
		AND i.status = 'pending_verification'
		ORDER BY i.updated_at DESC
	`, firmID)

	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed", err.Error())
		return
	}
	defer rows.Close()

	type Inv struct {
		ID             string  `json:"id"`
		InvoiceNumber  string  `json:"invoice_number"`
		TotalAmount    float64 `json:"total_amount"`
		TransactionID  string  `json:"transaction_id"`
		PaymentSlipURL string  `json:"payment_slip_url"`
		ClientName     string  `json:"client_name"`
		PaymentID      string  `json:"payment_id"`
	}

	list := []Inv{}
	for rows.Next() {
		var inv Inv
		rows.Scan(&inv.ID, &inv.InvoiceNumber, &inv.TotalAmount,
			&inv.TransactionID, &inv.PaymentSlipURL,
			&inv.ClientName, &inv.PaymentID)
		list = append(list, inv)
	}
	utils.Success(c, http.StatusOK, "Pending verifications", list)
}

func VerifyPayment(c *gin.Context) {
	paymentID := c.Param("id")

	// Approving a payment is what tells the firm the money arrived. Without a
	// scope check, any authenticated user on the platform — including the
	// client who filed the claim — could approve any payment by id.
	firmID, ok := requireFirmResource(c, tblPayments, paymentID)
	if !ok {
		return
	}
	userID := utils.UserID(c)

	var req struct {
		Status          string `json:"status" binding:"required"`
		RejectionReason string `json:"rejection_reason"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}

	if req.Status != "verified" && req.Status != "rejected" {
		utils.Error(c, http.StatusBadRequest, "Invalid status",
			"expected 'verified' or 'rejected'")
		return
	}
	if req.Status == "rejected" && req.RejectionReason == "" {
		utils.Error(c, http.StatusBadRequest, "Rejection reason required", "")
		return
	}

	tx, err := config.DB.Begin()
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to verify", err.Error())
		return
	}
	defer tx.Rollback()

	// Only move a payment that is still awaiting a decision, so a repeated
	// call cannot flip an already-settled payment or double-adjust the invoice.
	res, err := tx.Exec(`
		UPDATE payments SET
		verification_status=$1,
		rejection_reason=$2,
		verified_by=$3::uuid,
		verified_at=NOW()
		WHERE id=$4::uuid AND firm_id=$5::uuid
		  AND COALESCE(verification_status,'pending') = 'pending'
	`, req.Status, req.RejectionReason, userID, paymentID, firmID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to verify", err.Error())
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		utils.Error(c, http.StatusConflict, "Payment already reviewed", "not pending")
		return
	}

	var invoiceID sql.NullString
	var amount float64
	tx.QueryRow(`SELECT invoice_id::text, amount FROM payments WHERE id=$1::uuid`,
		paymentID).Scan(&invoiceID, &amount)

	// A rejected payment must not keep counting toward the invoice balance.
	if invoiceID.Valid && invoiceID.String != "" {
		if req.Status == "rejected" {
			tx.Exec(`
				UPDATE invoices SET
				  paid_amount = GREATEST(COALESCE(paid_amount,0) - $1, 0),
				  status = CASE
				    WHEN GREATEST(COALESCE(paid_amount,0) - $1, 0) >= total_amount THEN 'paid'
				    WHEN GREATEST(COALESCE(paid_amount,0) - $1, 0) > 0 THEN 'partial'
				    ELSE 'unpaid'
				  END,
				  updated_at = NOW()
				WHERE id=$2::uuid AND firm_id=$3::uuid
			`, amount, invoiceID.String, firmID)
		} else {
			tx.Exec(`
				UPDATE invoices SET
				  status = CASE
				    WHEN COALESCE(paid_amount,0) >= total_amount THEN 'paid'
				    WHEN COALESCE(paid_amount,0) > 0 THEN 'partial'
				    ELSE status
				  END,
				  updated_at = NOW()
				WHERE id=$1::uuid AND firm_id=$2::uuid
			`, invoiceID.String, firmID)
		}
	}

	if err := tx.Commit(); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to verify", err.Error())
		return
	}

	var clientUserID string
	config.DB.QueryRow(`
		SELECT u.id::text
		FROM payments p
		JOIN invoices i ON p.invoice_id = i.id
		JOIN clients cl ON i.client_id = cl.id
		JOIN users u ON lower(u.email) = lower(cl.email)
		WHERE p.id = $1::uuid LIMIT 1
	`, paymentID).Scan(&clientUserID)

	if clientUserID != "" {
		msg := "Your payment has been verified and approved."
		title := "Payment approved"
		if req.Status == "rejected" {
			msg = "Your payment was rejected. Reason: " + req.RejectionReason
			title = "Payment rejected"
		}
		// firm_id was omitted before, leaving the notification unattributable.
		utils.Notify(clientUserID, firmID, title, msg, "payment_reminder")
	}

	utils.Success(c, http.StatusOK, "Payment "+req.Status, nil)
}

// RefundPayment pays a client back for a payment that was already verified.
// For a payment that came in through Razorpay (payment_method='razorpay',
// transaction_id holding the gateway's payment id) this calls Razorpay's
// real refund API — no refund is ever faked. A manually-recorded payment
// (cash/bank-transfer/UPI proof) has no gateway transaction to reverse, so
// it's a bookkeeping-only refund: the invoice balance is corrected and the
// firm settles the money back to the client outside the app, same as how
// that payment was originally received outside the app.
func RefundPayment(c *gin.Context) {
	paymentID := c.Param("id")
	firmID, ok := requireFirmResource(c, tblPayments, paymentID)
	if !ok {
		return
	}
	userID := utils.UserID(c)

	var p struct {
		Amount            float64
		PaymentMethod     string
		TransactionID     string
		InvoiceID         sql.NullString
		VerificationState string
		RefundStatus      sql.NullString
	}
	err := config.DB.QueryRow(`
		SELECT amount, COALESCE(payment_method,''), COALESCE(transaction_id,''),
		       invoice_id::text, COALESCE(verification_status,'verified'), refund_status
		FROM payments WHERE id=$1::uuid AND firm_id=$2::uuid
	`, paymentID, firmID).Scan(&p.Amount, &p.PaymentMethod, &p.TransactionID,
		&p.InvoiceID, &p.VerificationState, &p.RefundStatus)
	if err == sql.ErrNoRows {
		utils.Error(c, http.StatusNotFound, "Payment not found", "")
		return
	}
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Database error", err.Error())
		return
	}
	if p.RefundStatus.Valid && p.RefundStatus.String == "refunded" {
		utils.Error(c, http.StatusConflict, "Payment already refunded", "duplicate refund")
		return
	}
	if p.VerificationState == "rejected" {
		utils.Error(c, http.StatusBadRequest, "A rejected payment cannot be refunded", "")
		return
	}

	reference := "manual"
	if p.PaymentMethod == "razorpay" && p.TransactionID != "" {
		refund, err := razorpayClient().CreateRefund(context.Background(), p.TransactionID, services.ToPaise(p.Amount))
		if err != nil {
			if errors.Is(err, services.ErrGatewayNotConfigured) {
				utils.Error(c, http.StatusServiceUnavailable,
					"Online payments are not configured, so this refund can't be processed automatically", err.Error())
				return
			}
			utils.Error(c, http.StatusBadGateway, "Refund failed at the payment gateway", err.Error())
			return
		}
		reference = refund.ID
	}

	tx, err := config.DB.Begin()
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to record refund", err.Error())
		return
	}
	defer tx.Rollback()

	// The refund_status IS NULL guard makes this safe against a second,
	// near-simultaneous tap: only the first request can move the row, and a
	// concurrent Razorpay refund (if any) already succeeded above, so this
	// only protects the local bookkeeping from double-adjusting the invoice.
	res, err := tx.Exec(`
		UPDATE payments SET
		  refund_status = 'refunded',
		  refunded_amount = $1,
		  refunded_at = NOW(),
		  refunded_by = $2::uuid,
		  refund_reference = $3
		WHERE id=$4::uuid AND firm_id=$5::uuid AND refund_status IS NULL
	`, p.Amount, userID, reference, paymentID, firmID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to record refund", err.Error())
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		utils.Error(c, http.StatusConflict, "Payment already refunded", "duplicate refund")
		return
	}

	if p.InvoiceID.Valid && p.InvoiceID.String != "" {
		tx.Exec(`
			UPDATE invoices SET
			  paid_amount = GREATEST(COALESCE(paid_amount,0) - $1, 0),
			  status = CASE
			    WHEN GREATEST(COALESCE(paid_amount,0) - $1, 0) >= total_amount THEN 'paid'
			    WHEN GREATEST(COALESCE(paid_amount,0) - $1, 0) > 0 THEN 'partial'
			    ELSE 'unpaid'
			  END,
			  updated_at = NOW()
			WHERE id=$2::uuid AND firm_id=$3::uuid
		`, p.Amount, p.InvoiceID.String, firmID)
	}

	if err := tx.Commit(); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to record refund", err.Error())
		return
	}

	var clientUserID string
	config.DB.QueryRow(`
		SELECT u.id::text
		FROM payments p
		JOIN invoices i ON p.invoice_id = i.id
		JOIN clients cl ON i.client_id = cl.id
		JOIN users u ON lower(u.email) = lower(cl.email)
		WHERE p.id = $1::uuid LIMIT 1
	`, paymentID).Scan(&clientUserID)
	if clientUserID != "" {
		utils.Notify(clientUserID, firmID, "Payment refunded",
			fmt.Sprintf("₹%.2f has been paid back to you.", p.Amount), "payment_reminder")
	}

	utils.Success(c, http.StatusOK, "Payment refunded", gin.H{
		"amount":           p.Amount,
		"refund_reference": reference,
	})
}

// ─── LAWYER PROFILE FOR STUDENTS ─────────────

func GetLawyerProfile(c *gin.Context) {
	lawyerID := c.Param("id")

	if !isUUID(lawyerID) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "not a uuid")
		return
	}

	var id, name, designation, firmName, city, state, barCouncil, avatarURL string
	var totalCases, wonCases, expYears int

	// Email and phone are deliberately not part of the public profile — see
	// GetAllLawyers. Only active lawyers are listed; the old query would happily
	// return a deactivated or suspended account.
	err := config.DB.QueryRow(`
		SELECT u.id, u.name, COALESCE(u.designation,'Advocate'),
		COALESCE(f.name,''), COALESCE(f.city,''), COALESCE(f.state,''),
		COALESCE(u.bar_council_number,''), COALESCE(u.avatar_url,''),
		(SELECT COUNT(*) FROM cases WHERE firm_id=u.firm_id) as total_cases,
		(SELECT COUNT(*) FROM cases WHERE firm_id=u.firm_id AND status='won') as won_cases,
		0 as exp_years
		FROM users u
		LEFT JOIN firms f ON u.firm_id = f.id
		LEFT JOIN roles r ON u.role_id = r.id
		WHERE u.id = $1::uuid AND u.is_active = true
		  AND r.name IN ('admin','lawyer')
	`, lawyerID).Scan(&id, &name, &designation,
		&firmName, &city, &state, &barCouncil, &avatarURL,
		&totalCases, &wonCases, &expYears)

	if err != nil {
		utils.Error(c, http.StatusNotFound, "Lawyer not found", err.Error())
		return
	}

	lawyer := gin.H{
		"id":                 id,
		"name":               name,
		"designation":        designation,
		"firm_name":          firmName,
		"city":               city,
		"state":              state,
		"bar_council_number": barCouncil,
		"avatar_url":         avatarURL,
		"total_cases":        totalCases,
		"won_cases_count":    wonCases,
		"experience_years":   expYears,
	}

	// Track record shown on the public profile.
	//
	// The case id and case_title used to be included. An Indian case title is
	// literally "<party> vs <party>", so this published the names of the firm's
	// real clients and their opponents to every user of the app, and the id let
	// a caller probe other endpoints with it. Only the practice area and the
	// lawyer's own written note are safe to show.
	rows, err2 := config.DB.Query(`
		SELECT COALESCE(case_type,''), COALESCE(won_feedback,'')
		FROM cases
		WHERE firm_id=(SELECT firm_id FROM users WHERE id=$1::uuid)
		AND status='won' AND COALESCE(won_feedback,'') != ''
		ORDER BY updated_at DESC LIMIT 5
	`, lawyerID)

	type WonCase struct {
		CaseType    string `json:"case_type"`
		WonFeedback string `json:"won_feedback"`
	}
	wonCasesList := []WonCase{}
	if err2 == nil && rows != nil {
		defer rows.Close()
		for rows.Next() {
			var wc WonCase
			rows.Scan(&wc.CaseType, &wc.WonFeedback)
			wonCasesList = append(wonCasesList, wc)
		}
	}

	utils.Success(c, http.StatusOK, "Lawyer profile fetched", gin.H{
		"lawyer":    lawyer,
		"won_cases": wonCasesList,
	})
}
