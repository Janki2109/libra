package controllers

import (
	"bytes"
	"encoding/base64"
	"fmt"
	"net/http"

	"libra/config"
	"libra/utils"

	"github.com/gin-gonic/gin"
	"github.com/go-pdf/fpdf"
)

// ExportInvoicePdf renders one invoice as a real, printable PDF. "Bill print"
// didn't exist anywhere in the app before this — no package, no button, no
// endpoint — so this is the whole feature, not a fix to an existing one.
// GET /invoices/:id/pdf
func ExportInvoicePdf(c *gin.Context) {
	id := c.Param("id")
	firmID, ok := requireFirmResource(c, tblInvoices, id)
	if !ok {
		return
	}

	var inv struct {
		Number      string
		Subtotal    float64
		GSTRate     float64
		GSTAmount   float64
		PlatformFee float64
		Total       float64
		Paid        float64
		Status      string
		IssueDate   string
		DueDate     string
		Notes       string
		ClientName  string
		ClientEmail string
		ClientPhone string
		FirmName    string
		UPIID       string
		BankName    string
		BankAccNum  string
		BankIFSC    string
		BankAccName string
	}
	err := config.DB.QueryRow(`
		SELECT i.invoice_number, COALESCE(i.subtotal,0), COALESCE(i.tax_percent,0),
		       COALESCE(i.tax_amount,0), COALESCE(i.platform_fee,0), i.total_amount,
		       COALESCE(i.paid_amount,0), i.status, i.issue_date::text,
		       COALESCE(i.due_date::text,''), COALESCE(i.notes,''),
		       COALESCE(cl.name,''), COALESCE(cl.email,''), COALESCE(cl.phone,''),
		       COALESCE(f.name,'Libra Law'),
		       COALESCE(i.upi_id, f.upi_id, ''),
		       COALESCE(i.bank_name, f.bank_name, ''),
		       COALESCE(i.bank_account_number, f.bank_account_number, ''),
		       COALESCE(i.bank_ifsc, f.bank_ifsc, ''),
		       COALESCE(i.bank_account_name, f.bank_account_name, '')
		FROM invoices i
		LEFT JOIN clients cl ON i.client_id = cl.id
		LEFT JOIN firms f ON i.firm_id = f.id
		WHERE i.id = $1::uuid AND i.firm_id = $2::uuid
	`, id, firmID).Scan(
		&inv.Number, &inv.Subtotal, &inv.GSTRate, &inv.GSTAmount, &inv.PlatformFee,
		&inv.Total, &inv.Paid, &inv.Status, &inv.IssueDate, &inv.DueDate, &inv.Notes,
		&inv.ClientName, &inv.ClientEmail, &inv.ClientPhone, &inv.FirmName,
		&inv.UPIID, &inv.BankName, &inv.BankAccNum, &inv.BankIFSC, &inv.BankAccName)
	if err != nil {
		utils.Error(c, http.StatusNotFound, "Invoice not found", err.Error())
		return
	}

	pdfBytes, err := buildInvoicePdf(inv.Number, inv.FirmName, inv.ClientName, inv.ClientEmail,
		inv.ClientPhone, inv.IssueDate, inv.DueDate, inv.Status, inv.Notes,
		inv.Subtotal, inv.GSTRate, inv.GSTAmount, inv.PlatformFee, inv.Total, inv.Paid,
		inv.UPIID, inv.BankName, inv.BankAccNum, inv.BankIFSC, inv.BankAccName)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to build invoice PDF", err.Error())
		return
	}
	if len(pdfBytes) == 0 {
		utils.Error(c, http.StatusInternalServerError, "Failed to build invoice PDF", "empty PDF output")
		return
	}

	utils.Success(c, http.StatusOK, "Invoice exported", gin.H{
		"file_base64": base64.StdEncoding.EncodeToString(pdfBytes),
		"file_name":   timestampedFileName("Invoice "+inv.Number, ".pdf"),
	})
}

func buildInvoicePdf(number, firmName, clientName, clientEmail, clientPhone,
	issueDate, dueDate, status, notes string,
	subtotal, gstRate, gstAmount, platformFee, total, paid float64,
	upiID, bankName, bankAccNum, bankIFSC, bankAccName string) ([]byte, error) {
	pdf := fpdf.New("P", "mm", "A4", "")
	pdf.SetMargins(20, 20, 20)
	pdf.SetAutoPageBreak(true, 20)
	pdf.AddPage()
	tr := pdf.UnicodeTranslatorFromDescriptor("cp1252")
	rupee := func(v float64) string {
		return tr("Rs. ") + moneyFmt(v)
	}

	// Header
	pdf.SetFont(pdfFont, "B", 20)
	pdf.CellFormat(0, 10, tr("TAX INVOICE"), "", 1, "L", false, 0, "")
	pdf.SetFont(pdfFont, "", 11)
	pdf.SetTextColor(90, 90, 90)
	pdf.CellFormat(0, 6, tr(firmName), "", 1, "L", false, 0, "")
	pdf.SetTextColor(0, 0, 0)
	pdf.Ln(4)

	left, _, right, _ := pdf.GetMargins()
	pageW, _ := pdf.GetPageSize()
	colW := (pageW - left - right) / 2

	y := pdf.GetY()
	pdf.SetFont(pdfFont, "B", 10)
	pdf.CellFormat(colW, 6, tr("Bill To"), "", 0, "L", false, 0, "")
	pdf.SetXY(left+colW, y)
	pdf.CellFormat(colW, 6, tr("Invoice Details"), "", 1, "L", false, 0, "")

	pdf.SetFont(pdfFont, "", 10)
	pdf.SetX(left)
	pdf.MultiCell(colW-4, 5.5, tr(clientName+"\n"+clientEmail+"\n"+clientPhone), "", "L", false)
	yAfterLeft := pdf.GetY()

	pdf.SetXY(left+colW, y+6)
	pdf.SetX(left + colW)
	details := "Invoice #: " + number + "\nIssue Date: " + issueDate
	if dueDate != "" {
		details += "\nDue Date: " + dueDate
	}
	details += "\nStatus: " + statusLabel(status)
	pdf.MultiCell(colW, 5.5, tr(details), "", "L", false)
	yAfterRight := pdf.GetY()

	if yAfterRight > yAfterLeft {
		pdf.SetY(yAfterRight)
	} else {
		pdf.SetY(yAfterLeft)
	}
	pdf.Ln(6)

	// Line items table
	tableW := pageW - left - right
	descW := tableW * 0.7
	amtW := tableW * 0.3

	pdf.SetFillColor(21, 14, 61) // brand navy
	pdf.SetTextColor(255, 255, 255)
	pdf.SetFont(pdfFont, "B", 10)
	pdf.CellFormat(descW, 8, tr("Description"), "1", 0, "L", true, 0, "")
	pdf.CellFormat(amtW, 8, tr("Amount"), "1", 1, "R", true, 0, "")
	pdf.SetTextColor(0, 0, 0)
	pdf.SetFont(pdfFont, "", 10)

	row := func(label string, amount float64) {
		pdf.CellFormat(descW, 8, tr(label), "LR", 0, "L", false, 0, "")
		pdf.CellFormat(amtW, 8, rupee(amount), "LR", 1, "R", false, 0, "")
	}
	row("Consultation / Service Amount", subtotal)
	row(fmtGSTLabel(gstRate), gstAmount)
	row("Platform Fee", platformFee)

	pdf.CellFormat(descW, 0.3, "", "T", 0, "", false, 0, "")
	pdf.CellFormat(amtW, 0.3, "", "T", 1, "", false, 0, "")

	pdf.SetFont(pdfFont, "B", 11)
	pdf.CellFormat(descW, 9, tr("TOTAL PAYABLE"), "LRB", 0, "L", false, 0, "")
	pdf.CellFormat(amtW, 9, rupee(total), "LRB", 1, "R", false, 0, "")

	pdf.SetFont(pdfFont, "", 10)
	pdf.Ln(2)
	due := total - paid
	pdf.CellFormat(descW, 7, tr("Amount Paid"), "", 0, "L", false, 0, "")
	pdf.CellFormat(amtW, 7, rupee(paid), "", 1, "R", false, 0, "")
	pdf.SetFont(pdfFont, "B", 10)
	pdf.CellFormat(descW, 7, tr("Balance Due"), "", 0, "L", false, 0, "")
	pdf.CellFormat(amtW, 7, rupee(due), "", 1, "R", false, 0, "")
	pdf.SetFont(pdfFont, "", 10)
	pdf.Ln(6)

	if notes != "" {
		pdf.SetFont(pdfFont, "B", 10)
		pdf.CellFormat(0, 6, tr("Notes"), "", 1, "L", false, 0, "")
		pdf.SetFont(pdfFont, "", 10)
		pdf.MultiCell(0, 5.5, tr(notes), "", "L", false)
		pdf.Ln(4)
	}

	if due > 0.01 && (upiID != "" || bankAccNum != "") {
		pdf.SetFont(pdfFont, "B", 10)
		pdf.CellFormat(0, 6, tr("Payment Details"), "", 1, "L", false, 0, "")
		pdf.SetFont(pdfFont, "", 10)
		if upiID != "" {
			pdf.CellFormat(0, 5.5, tr("UPI ID: "+upiID), "", 1, "L", false, 0, "")
		}
		if bankAccNum != "" {
			bank := "Bank: " + bankName + "  |  A/c: " + bankAccNum + "  |  IFSC: " + bankIFSC
			if bankAccName != "" {
				bank += "  |  Name: " + bankAccName
			}
			pdf.MultiCell(0, 5.5, tr(bank), "", "L", false)
		}
	}

	var buf bytes.Buffer
	if err := pdf.Output(&buf); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

func statusLabel(status string) string {
	switch status {
	case "paid":
		return "PAID"
	case "partial":
		return "PARTIALLY PAID"
	case "pending_verification":
		return "PENDING VERIFICATION"
	case "unpaid":
		return "UNPAID"
	default:
		return status
	}
}

func fmtGSTLabel(rate float64) string {
	return fmt.Sprintf("GST (%.0f%%)", rate)
}

func moneyFmt(v float64) string {
	return fmt.Sprintf("%.2f", v)
}
