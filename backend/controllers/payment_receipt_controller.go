package controllers

import (
	"bytes"
	"database/sql"
	"encoding/base64"
	"net/http"

	"libra/config"
	"libra/utils"

	"github.com/gin-gonic/gin"
	"github.com/go-pdf/fpdf"
)

// Payment receipts didn't exist anywhere in the app before this — only
// invoice PDFs did (ExportInvoicePdf / ExportMyInvoicePdf). A receipt is a
// separate document type: it confirms one specific payment (invoice
// instalment or a ₹5 consultation payment), not the invoice as a whole, and
// is the only downloadable proof of payment a ₹5 consultation transaction
// ever has since consultations have no invoice of their own.

type receiptData struct {
	PaymentID     string
	ReceiptNumber string // short, stable, human-shareable id derived from payment id
	FirmName      string
	PayerName     string
	Amount        float64
	PaymentDate   string
	PaymentMethod string
	TransactionID string
	Description   string // "Invoice INV-2026-123" or "Video Call consultation"
	InvoiceNumber string // empty for a consultation payment
	Status        string // always "verified"/"PAID" for a row that exists at all
}

// fetchReceiptData loads everything a receipt needs for one payment, scoped
// to firmID so a caller can never pull another firm's payment by guessing an
// id. Shared by both the lawyer and client receipt endpoints -- the client
// path additionally checks the payment belongs to them specifically before
// calling this (see ExportMyPaymentReceiptPdf).
func fetchReceiptData(paymentID, firmID string) (receiptData, error) {
	var d receiptData
	var invoiceNumber, clientName, notes, method sql.NullString
	err := config.DB.QueryRow(`
		SELECT p.id, p.amount, p.payment_date::text, COALESCE(p.payment_method,''),
		       COALESCE(p.transaction_id,''), COALESCE(p.notes,''),
		       COALESCE(i.invoice_number,''), COALESCE(cl.name,''),
		       COALESCE(f.name,'Libra Law')
		FROM payments p
		LEFT JOIN invoices i ON p.invoice_id = i.id
		LEFT JOIN clients cl ON p.client_id = cl.id
		LEFT JOIN firms f ON p.firm_id = f.id
		WHERE p.id = $1::uuid AND p.firm_id = $2::uuid
	`, paymentID, firmID).Scan(&d.PaymentID, &d.Amount, &d.PaymentDate, &method,
		&d.TransactionID, &notes, &invoiceNumber, &clientName, &d.FirmName)
	if err != nil {
		return d, err
	}
	d.PaymentMethod = method.String
	d.InvoiceNumber = invoiceNumber.String
	d.PayerName = clientName.String
	if d.PayerName == "" {
		d.PayerName = "Client"
	}
	if d.InvoiceNumber != "" {
		d.Description = "Invoice " + d.InvoiceNumber
	} else if notes.String != "" {
		d.Description = notes.String
	} else {
		d.Description = "Consultation payment"
	}
	// Short, stable, non-sequential receipt number derived from the
	// payment's own uuid (first 8 hex chars) rather than a separate counter
	// table -- unique per payment without any new schema or race condition.
	d.ReceiptNumber = "RCPT-" + firstN(d.PaymentID, 8)
	d.Status = "PAID"
	return d, nil
}

func firstN(s string, n int) string {
	clean := make([]rune, 0, n)
	for _, r := range s {
		if r == '-' {
			continue
		}
		clean = append(clean, r)
		if len(clean) == n {
			break
		}
	}
	return string(clean)
}

func buildReceiptPdf(d receiptData) ([]byte, error) {
	pdf := fpdf.New("P", "mm", "A4", "")
	pdf.SetMargins(20, 20, 20)
	pdf.SetAutoPageBreak(true, 20)
	pdf.AddPage()
	tr := pdf.UnicodeTranslatorFromDescriptor("cp1252")
	rupee := func(v float64) string { return tr("Rs. ") + moneyFmt(v) }

	pdf.SetFont(pdfFont, "B", 20)
	pdf.CellFormat(0, 10, tr("PAYMENT RECEIPT"), "", 1, "L", false, 0, "")
	pdf.SetFont(pdfFont, "", 11)
	pdf.SetTextColor(90, 90, 90)
	pdf.CellFormat(0, 6, tr(d.FirmName), "", 1, "L", false, 0, "")
	pdf.SetTextColor(0, 0, 0)
	pdf.Ln(4)

	left, _, right, _ := pdf.GetMargins()
	pageW, _ := pdf.GetPageSize()
	colW := (pageW - left - right) / 2

	y := pdf.GetY()
	pdf.SetFont(pdfFont, "B", 10)
	pdf.CellFormat(colW, 6, tr("Received From"), "", 0, "L", false, 0, "")
	pdf.SetXY(left+colW, y)
	pdf.CellFormat(colW, 6, tr("Receipt Details"), "", 1, "L", false, 0, "")

	pdf.SetFont(pdfFont, "", 10)
	pdf.SetX(left)
	pdf.MultiCell(colW-4, 5.5, tr(d.PayerName), "", "L", false)
	yAfterLeft := pdf.GetY()

	pdf.SetXY(left+colW, y+6)
	pdf.SetX(left + colW)
	details := "Receipt #: " + d.ReceiptNumber + "\nDate: " + d.PaymentDate
	if d.InvoiceNumber != "" {
		details += "\nInvoice #: " + d.InvoiceNumber
	}
	details += "\nStatus: " + d.Status
	pdf.MultiCell(colW, 5.5, tr(details), "", "L", false)
	yAfterRight := pdf.GetY()

	if yAfterRight > yAfterLeft {
		pdf.SetY(yAfterRight)
	} else {
		pdf.SetY(yAfterLeft)
	}
	pdf.Ln(6)

	tableW := pageW - left - right
	descW := tableW * 0.7
	amtW := tableW * 0.3

	pdf.SetFillColor(21, 14, 61)
	pdf.SetTextColor(255, 255, 255)
	pdf.SetFont(pdfFont, "B", 10)
	pdf.CellFormat(descW, 8, tr("Description"), "1", 0, "L", true, 0, "")
	pdf.CellFormat(amtW, 8, tr("Amount"), "1", 1, "R", true, 0, "")
	pdf.SetTextColor(0, 0, 0)
	pdf.SetFont(pdfFont, "", 10)
	pdf.CellFormat(descW, 8, tr(d.Description), "LR", 0, "L", false, 0, "")
	pdf.CellFormat(amtW, 8, rupee(d.Amount), "LR", 1, "R", false, 0, "")

	pdf.SetFont(pdfFont, "B", 11)
	pdf.CellFormat(descW, 9, tr("AMOUNT PAID"), "LRB", 0, "L", false, 0, "")
	pdf.CellFormat(amtW, 9, rupee(d.Amount), "LRB", 1, "R", false, 0, "")
	pdf.SetFont(pdfFont, "", 10)
	pdf.Ln(6)

	pdf.SetFont(pdfFont, "B", 10)
	pdf.CellFormat(0, 6, tr("Payment Method"), "", 1, "L", false, 0, "")
	pdf.SetFont(pdfFont, "", 10)
	method := d.PaymentMethod
	if method == "" {
		method = "—"
	}
	pdf.CellFormat(0, 5.5, tr(method), "", 1, "L", false, 0, "")
	pdf.Ln(2)

	pdf.SetFont(pdfFont, "B", 10)
	pdf.CellFormat(0, 6, tr("Transaction ID"), "", 1, "L", false, 0, "")
	pdf.SetFont(pdfFont, "", 10)
	txn := d.TransactionID
	if txn == "" {
		txn = "—"
	}
	pdf.CellFormat(0, 5.5, tr(txn), "", 1, "L", false, 0, "")

	var buf bytes.Buffer
	if err := pdf.Output(&buf); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

// ExportPaymentReceiptPdf is the lawyer-side receipt download.
// GET /payments/:id/receipt
func ExportPaymentReceiptPdf(c *gin.Context) {
	id := c.Param("id")
	firmID, ok := requireFirmResource(c, tblPayments, id)
	if !ok {
		return
	}
	d, err := fetchReceiptData(id, firmID)
	if err != nil {
		utils.Error(c, http.StatusNotFound, "Payment not found", err.Error())
		return
	}
	pdfBytes, err := buildReceiptPdf(d)
	if err != nil || len(pdfBytes) == 0 {
		utils.Error(c, http.StatusInternalServerError, "Failed to build receipt PDF", "")
		return
	}
	utils.Success(c, http.StatusOK, "Receipt exported", gin.H{
		"file_base64": base64.StdEncoding.EncodeToString(pdfBytes),
		"file_name":   timestampedFileName("Receipt "+d.ReceiptNumber, ".pdf"),
	})
}

// ExportMyConsultationReceiptPdf is the client-side receipt download for a
// ₹5-style consultation payment, keyed by the consultation id rather than
// the payments.id directly -- GetMyConsultations never exposes the latter,
// since the payment row is an implementation detail of how consultation
// payments get recorded (see recordConsultationPayment's deterministic
// "CONSULT_"+consultationID transaction_id). Ownership is checked against
// consultations.client_id, the same column GetMyConsultations itself
// filters on, before the matching payment is even looked up.
// GET /portal/my-consultations/:id/receipt
func ExportMyConsultationReceiptPdf(c *gin.Context) {
	consultationID := c.Param("id")
	if !isUUID(consultationID) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "not a uuid")
		return
	}
	userID, _ := c.Get("user_id")

	var firmID string
	err := config.DB.QueryRow(`
		SELECT COALESCE(l.firm_id::text,'')
		FROM consultations con
		JOIN users l ON con.lawyer_id = l.id
		WHERE con.id = $1::uuid AND con.client_id = $2::uuid
	`, consultationID, userID).Scan(&firmID)
	if err != nil || firmID == "" {
		utils.Error(c, http.StatusNotFound, "Consultation not found", "")
		return
	}

	var paymentID string
	err = config.DB.QueryRow(`
		SELECT id::text FROM payments
		WHERE firm_id = $1::uuid AND transaction_id = $2
	`, firmID, "CONSULT_"+consultationID).Scan(&paymentID)
	if err != nil {
		utils.Error(c, http.StatusNotFound, "No payment found for this consultation", "")
		return
	}

	d, err := fetchReceiptData(paymentID, firmID)
	if err != nil {
		utils.Error(c, http.StatusNotFound, "Payment not found", err.Error())
		return
	}
	pdfBytes, err := buildReceiptPdf(d)
	if err != nil || len(pdfBytes) == 0 {
		utils.Error(c, http.StatusInternalServerError, "Failed to build receipt PDF", "")
		return
	}
	utils.Success(c, http.StatusOK, "Receipt exported", gin.H{
		"file_base64": base64.StdEncoding.EncodeToString(pdfBytes),
		"file_name":   timestampedFileName("Receipt "+d.ReceiptNumber, ".pdf"),
	})
}

// ExportMyPaymentReceiptPdf is the client-side receipt download. Ownership
// is checked the same way GetMyDocument/GetMyInvoice check it: the payment's
// client_id must resolve to a clients row whose email matches the
// authenticated portal user's own email -- never trusting the :id alone, and
// never relying on requireFirmResource (which has no concept of "this
// specific client" within a firm, only "this firm").
// GET /portal/payments/:id/receipt
func ExportMyPaymentReceiptPdf(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "not a uuid")
		return
	}
	userEmail, ok := portalClientEmail(c)
	if !ok {
		utils.Error(c, http.StatusNotFound, "Payment not found", "no portal identity")
		return
	}
	var firmID string
	err := config.DB.QueryRow(`
		SELECT p.firm_id::text
		FROM payments p
		JOIN clients cl ON p.client_id = cl.id
		WHERE p.id = $1::uuid AND lower(cl.email) = $2
	`, id, userEmail).Scan(&firmID)
	if err != nil {
		utils.Error(c, http.StatusNotFound, "Payment not found", "")
		return
	}
	d, err := fetchReceiptData(id, firmID)
	if err != nil {
		utils.Error(c, http.StatusNotFound, "Payment not found", err.Error())
		return
	}
	pdfBytes, err := buildReceiptPdf(d)
	if err != nil || len(pdfBytes) == 0 {
		utils.Error(c, http.StatusInternalServerError, "Failed to build receipt PDF", "")
		return
	}
	utils.Success(c, http.StatusOK, "Receipt exported", gin.H{
		"file_base64": base64.StdEncoding.EncodeToString(pdfBytes),
		"file_name":   timestampedFileName("Receipt "+d.ReceiptNumber, ".pdf"),
	})
}
