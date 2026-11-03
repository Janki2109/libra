package controllers

import (
	"database/sql"
	"errors"
	"fmt"
	"libra/config"
	"libra/services"
	"libra/utils"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

// ─── CREATE RAZORPAY ORDER ───────────────────
// POST /payments/razorpay/order
func CreateRazorpayOrder(c *gin.Context) {
	// A self-registered client (ClientRegister) carries no firm_id on their
	// token at all — see the identical fallback in UploadDocument — so
	// requiring it unconditionally 403'd every client before they could ever
	// reach Pay Now, regardless of which invoice they owned. Firm staff still
	// go through RequireFirm exactly as before, which is what enforces tenant
	// isolation for them (see the firm-match check below); a client's
	// authorization instead comes entirely from callerOwnsInvoice's
	// email-to-invoice match.
	var callerFirmID string
	if firmStaffRole(utils.Role(c)) {
		fid, ok := utils.RequireFirm(c)
		if !ok {
			return
		}
		callerFirmID = fid
	}

	var req struct {
		InvoiceID string `json:"invoice_id" binding:"required"`
		Currency  string `json:"currency"`
		Notes     string `json:"notes"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}

	if req.Currency == "" {
		req.Currency = "INR"
	}

	// The amount is read from the invoice, never taken from the request.
	// The handler used to accept an `amount` field from the client, so a
	// caller could open a ₹1 order against a ₹100,000 invoice and — since the
	// verify step also trusted the client's amount — have it recorded as paid
	// in full.
	var total, paid float64
	var invoiceNumber, invoiceFirmID string
	err := config.DB.QueryRow(`
		SELECT total_amount, COALESCE(paid_amount,0), invoice_number, firm_id::text
		FROM invoices WHERE id=$1::uuid
	`, req.InvoiceID).Scan(&total, &paid, &invoiceNumber, &invoiceFirmID)
	if err == sql.ErrNoRows {
		utils.Error(c, http.StatusNotFound, "Invoice not found", "")
		return
	}
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to read invoice", err.Error())
		return
	}
	// Firm staff may only ever touch an invoice in their own firm — same
	// tenant boundary the old WHERE firm_id=$2 enforced.
	if callerFirmID != "" && callerFirmID != invoiceFirmID {
		utils.Error(c, http.StatusNotFound, "Invoice not found", "")
		return
	}
	firmID := invoiceFirmID

	// This route now sits outside RequireFirmStaff() (a client paying their
	// own invoice is not firm staff), so — same rule CreatePayment already
	// enforces for the manual/offline flow — a non-staff caller may only pay
	// their own invoice.
	if !callerOwnsInvoice(c, firmID, req.InvoiceID) {
		utils.Error(c, http.StatusForbidden, "You can only pay your own invoice", "")
		return
	}

	due := total - paid
	if due <= 0 {
		utils.Error(c, http.StatusBadRequest, "Invoice is already settled", "nothing due")
		return
	}
	amountPaise := toPaise(due)

	if !razorpayClient().Configured() {
		// Development stub. It must not be reachable in production, where a
		// missing key would otherwise hand the app a fake order id that the
		// verify step used to accept without any signature at all.
		if utils.IsProduction() {
			utils.Error(c, http.StatusServiceUnavailable,
				"Online payment is not configured", "RAZORPAY_KEY_ID/SECRET unset")
			return
		}
		utils.Success(c, http.StatusOK, "Order created (development stub)", gin.H{
			"order_id":        fmt.Sprintf("order_dev_%s", uuid.New().String()[:16]),
			"amount":          amountPaise,
			"currency":        req.Currency,
			"invoice_id":      req.InvoiceID,
			"key_id":          "",
			"razorpay_active": false,
		})
		return
	}

	// Goes through the shared gateway client, so invoice payment and
	// subscription checkout use one implementation of order creation and one
	// implementation of signature verification. Two copies of a signature
	// check is two copies that eventually differ in one of them.
	order, err := razorpayClient().CreateOrder(c.Request.Context(), amountPaise, req.Currency,
		"inv_"+invoiceNumber,
		map[string]string{
			"kind":       "invoice",
			"invoice_id": req.InvoiceID,
			"firm_id":    firmID,
			"notes":      req.Notes,
		})
	if err != nil {
		utils.Error(c, http.StatusBadGateway, "Failed to create Razorpay order", err.Error())
		return
	}

	// Remember the order so the verify step can match it back to this invoice
	// and this amount instead of believing whatever the client sends.
	_, err = config.DB.Exec(`
		INSERT INTO payment_orders (id, firm_id, kind, invoice_id, order_id, amount_paise, currency, status, created_by)
		VALUES (gen_random_uuid(), $1::uuid, 'invoice', $2::uuid, $3, $4, $5, 'created', $6::uuid)
	`, firmID, req.InvoiceID, order.ID, amountPaise, req.Currency, utils.UserID(c))
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to record order", err.Error())
		return
	}

	utils.Success(c, http.StatusOK, "Order created", gin.H{
		"order_id":        order.ID,
		"amount":          order.Amount,
		"currency":        order.Currency,
		"invoice_id":      req.InvoiceID,
		"key_id":          razorpayClient().KeyID(),
		"razorpay_active": true,
	})
}

// ─── VERIFY RAZORPAY PAYMENT ─────────────────
// POST /payments/razorpay/verify
func VerifyRazorpayPayment(c *gin.Context) {
	// Same reasoning as CreateRazorpayOrder: a self-registered client has no
	// firm_id claim, so it can't be required unconditionally here either.
	var callerFirmID string
	if firmStaffRole(utils.Role(c)) {
		fid, ok := utils.RequireFirm(c)
		if !ok {
			return
		}
		callerFirmID = fid
	}
	// The old code did `firmID.(string)` unchecked, panicking on any token
	// without the claim.
	uID := utils.UserID(c)

	var req struct {
		RazorpayOrderID   string `json:"razorpay_order_id" binding:"required"`
		RazorpayPaymentID string `json:"razorpay_payment_id" binding:"required"`
		RazorpaySignature string `json:"razorpay_signature" binding:"required"`
		PaymentMethod     string `json:"payment_method"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}

	// Signature verification used to be skipped entirely whenever
	// RAZORPAY_KEY_SECRET was empty — the exact state a fresh deployment starts
	// in. Anyone could POST three arbitrary strings and have an invoice marked
	// paid. The shared client refuses instead, and compares in constant time.
	if err := razorpayClient().VerifyPaymentSignature(
		req.RazorpayOrderID, req.RazorpayPaymentID, req.RazorpaySignature,
	); err != nil {
		if errors.Is(err, services.ErrGatewayNotConfigured) {
			utils.Error(c, http.StatusServiceUnavailable,
				"Online payment is not configured", err.Error())
			return
		}
		utils.Error(c, http.StatusBadRequest, "Invalid payment signature", err.Error())
		return
	}

	// Resolve the invoice, the amount, and the order's own firm from the
	// order we recorded at creation time — not from the caller's claim,
	// which a client-role caller may not have at all.
	var invoiceID, orderFirmID string
	var amountPaise int64
	var orderStatus string
	err := config.DB.QueryRow(`
		SELECT invoice_id::text, amount_paise, status, firm_id::text
		FROM payment_orders
		WHERE order_id=$1
	`, req.RazorpayOrderID).Scan(&invoiceID, &amountPaise, &orderStatus, &orderFirmID)
	if err == sql.ErrNoRows {
		utils.Error(c, http.StatusBadRequest, "Unknown order", "no matching order")
		return
	}
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to verify", err.Error())
		return
	}
	// Same tenant boundary the old WHERE firm_id=$2 enforced for firm staff.
	if callerFirmID != "" && callerFirmID != orderFirmID {
		utils.Error(c, http.StatusBadRequest, "Unknown order", "no matching order for this firm")
		return
	}
	firmID := orderFirmID
	if orderStatus == "paid" {
		utils.Error(c, http.StatusConflict, "Order already settled", "duplicate verification")
		return
	}

	if !callerOwnsInvoice(c, firmID, invoiceID) {
		utils.Error(c, http.StatusForbidden, "You can only pay your own invoice", "")
		return
	}

	amount := float64(amountPaise) / 100

	// Snapshot the invoice's own GST/platform-fee/subtotal breakdown onto the
	// payment row at the moment it clears, so a receipt (client/lawyer/Super
	// Admin) never has to reconstruct "what was retained vs. payable to the
	// lawyer" from the invoice's current state, which could since have
	// changed. The lawyer's payable share is the service subtotal — GST and
	// the platform fee are what the platform retains.
	var gstAmount, platformFee, subtotal float64
	config.DB.QueryRow(`
		SELECT COALESCE(tax_amount,0), COALESCE(platform_fee,0), COALESCE(subtotal,0)
		FROM invoices WHERE id=$1::uuid AND firm_id=$2::uuid
	`, invoiceID, firmID).Scan(&gstAmount, &platformFee, &subtotal)
	lawyerPayable := subtotal

	paymentMethod := req.PaymentMethod
	if paymentMethod == "" {
		paymentMethod = "razorpay"
	}

	tx, err := config.DB.Begin()
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to record payment", err.Error())
		return
	}
	defer tx.Rollback()

	// transaction_id is unique per firm (migration 009), so replaying the same
	// razorpay_payment_id cannot inflate paid_amount. The old handler had no
	// such guard: re-POSTing one successful response repeatedly credited the
	// invoice again each time.
	payID := uuid.New().String()
	today := time.Now().Format("2006-01-02")
	res, err := tx.Exec(`
		INSERT INTO payments (id, firm_id, invoice_id, amount,
		payment_date, payment_method, transaction_id, notes, created_by,
		verification_status, verified_at,
		razorpay_order_id, gst_amount, platform_fee, lawyer_payable_amount)
		VALUES ($1, $2::uuid, $3::uuid, $4, $5, $6, $7, $8, $9::uuid, 'verified', NOW(),
		$10, $11, $12, $13)
		ON CONFLICT (firm_id, transaction_id) DO NOTHING
	`, payID, firmID, invoiceID, amount, today,
		paymentMethod, req.RazorpayPaymentID,
		"Online payment via Razorpay", uID,
		req.RazorpayOrderID, gstAmount, platformFee, lawyerPayable)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to record payment", err.Error())
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		utils.Error(c, http.StatusConflict, "Payment already recorded", "duplicate transaction id")
		return
	}

	if _, err := tx.Exec(`
		UPDATE invoices SET
		  paid_amount = COALESCE(paid_amount,0) + $1,
		  status = CASE
		    WHEN COALESCE(paid_amount,0) + $1 >= total_amount THEN 'paid'
		    ELSE 'partial'
		  END,
		  updated_at = NOW()
		WHERE id=$2::uuid AND firm_id=$3::uuid
	`, amount, invoiceID, firmID); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to update invoice", err.Error())
		return
	}

	if _, err := tx.Exec(`
		UPDATE payment_orders SET status='paid', payment_id=$1, updated_at=NOW()
		WHERE order_id=$2 AND firm_id=$3::uuid
	`, req.RazorpayPaymentID, req.RazorpayOrderID, firmID); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to close order", err.Error())
		return
	}

	if err := tx.Commit(); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to record payment", err.Error())
		return
	}

	notifyPaymentRecorded(firmID, invoiceID, uID, payID, req.RazorpayPaymentID, amount)

	utils.Success(c, http.StatusOK, "Payment verified and recorded", gin.H{
		"payment_id":     payID,
		"transaction_id": req.RazorpayPaymentID,
		"amount":         amount,
		"status":         "success",
	})
}

// PayInvoiceWithoutGateway settles an invoice's remaining balance in full,
// with no payment gateway involved — Razorpay checkout is turned off for
// clients for now (CreateRazorpayOrder was failing with "Failed to create
// Razorpay order" and had no other way through). Mirrors
// VerifyRazorpayPayment's crediting logic exactly — same payments insert,
// same invoice update, same notifyPaymentRecorded call to the lawyer — just
// without creating/verifying a gateway order first.
//
// TODO: once Razorpay checkout is reinstated for clients, retire this route
// (or gate it behind ALLOW_TEST_PAYMENT_BYPASS the way the consultation/
// subscription test-bypass endpoints are) rather than leaving two live ways
// to pay an invoice.
func PayInvoiceWithoutGateway(c *gin.Context) {
	var callerFirmID string
	if firmStaffRole(utils.Role(c)) {
		fid, ok := utils.RequireFirm(c)
		if !ok {
			return
		}
		callerFirmID = fid
	}
	uID := utils.UserID(c)

	var req struct {
		InvoiceID string `json:"invoice_id" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}

	var total, paid float64
	var invoiceFirmID string
	err := config.DB.QueryRow(`
		SELECT total_amount, COALESCE(paid_amount,0), firm_id::text
		FROM invoices WHERE id=$1::uuid
	`, req.InvoiceID).Scan(&total, &paid, &invoiceFirmID)
	if err == sql.ErrNoRows {
		utils.Error(c, http.StatusNotFound, "Invoice not found", "")
		return
	}
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to read invoice", err.Error())
		return
	}
	if callerFirmID != "" && callerFirmID != invoiceFirmID {
		utils.Error(c, http.StatusNotFound, "Invoice not found", "")
		return
	}
	firmID := invoiceFirmID

	if !callerOwnsInvoice(c, firmID, req.InvoiceID) {
		utils.Error(c, http.StatusForbidden, "You can only pay your own invoice", "")
		return
	}

	due := services.RoundMoney(total - paid)
	if due <= 0 {
		utils.Error(c, http.StatusBadRequest, "Invoice is already settled", "nothing due")
		return
	}

	var gstAmount, platformFee, subtotal float64
	config.DB.QueryRow(`
		SELECT COALESCE(tax_amount,0), COALESCE(platform_fee,0), COALESCE(subtotal,0)
		FROM invoices WHERE id=$1::uuid AND firm_id=$2::uuid
	`, req.InvoiceID, firmID).Scan(&gstAmount, &platformFee, &subtotal)

	tx, err := config.DB.Begin()
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to record payment", err.Error())
		return
	}
	defer tx.Rollback()

	payID := uuid.New().String()
	today := time.Now().Format("2006-01-02")
	txnID := "NO_GATEWAY_" + uuid.New().String()
	if _, err := tx.Exec(`
		INSERT INTO payments (id, firm_id, invoice_id, amount,
		payment_date, payment_method, transaction_id, notes, created_by,
		verification_status, verified_at, gst_amount, platform_fee, lawyer_payable_amount)
		VALUES ($1, $2::uuid, $3::uuid, $4, $5, 'manual_test', $6, $7, $8::uuid, 'verified', NOW(),
		$9, $10, $11)
	`, payID, firmID, req.InvoiceID, due, today, txnID,
		"Marked paid without a payment gateway (testing)", uID,
		gstAmount, platformFee, subtotal); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to record payment", err.Error())
		return
	}

	if _, err := tx.Exec(`
		UPDATE invoices SET
		  paid_amount = COALESCE(paid_amount,0) + $1,
		  status = CASE
		    WHEN COALESCE(paid_amount,0) + $1 >= total_amount THEN 'paid'
		    ELSE 'partial'
		  END,
		  updated_at = NOW()
		WHERE id=$2::uuid AND firm_id=$3::uuid
	`, due, req.InvoiceID, firmID); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to update invoice", err.Error())
		return
	}

	if err := tx.Commit(); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to record payment", err.Error())
		return
	}

	notifyPaymentRecorded(firmID, req.InvoiceID, uID, payID, txnID, due)

	utils.Success(c, http.StatusOK, "Payment recorded — lawyer notified", gin.H{
		"payment_id": payID,
		"amount":     due,
		"status":     "success",
	})
}

// notifyPaymentRecorded tells the invoice's author and the payer that money
// landed. Failures here are logged by the DB layer but never fail the payment,
// which has already been committed.
func notifyPaymentRecorded(firmID, invoiceID, payerUserID, payID, txnID string, amount float64) {
	var createdBy sql.NullString
	var invNum string
	config.DB.QueryRow(`
		SELECT created_by::text, invoice_number FROM invoices WHERE id=$1::uuid
	`, invoiceID).Scan(&createdBy, &invNum)

	if createdBy.Valid && createdBy.String != "" {
		utils.NotifyWithRef(createdBy.String, firmID,
			"Payment received",
			fmt.Sprintf("Online payment of %s received for invoice %s (Txn: %s)",
				formatINR(amount), invNum, txnID),
			"general", payID, "payment")
	}

	utils.NotifyWithRef(payerUserID, firmID,
		"Payment successful",
		fmt.Sprintf("Your payment of %s for invoice %s was successful. Transaction ID: %s",
			formatINR(amount), invNum, txnID),
		"general", payID, "payment")
}

// toPaise and the HMAC helper now live on services.Razorpay, so subscription
// checkout and invoice payment share one implementation of each.
func toPaise(rupees float64) int64 { return services.ToPaise(rupees) }

// formatINR renders an amount for human-readable copy.
func formatINR(amount float64) string {
	return "Rs. " + strings.TrimSpace(fmt.Sprintf("%.2f", amount))
}
