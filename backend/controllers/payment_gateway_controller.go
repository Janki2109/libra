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
	firmID, ok := utils.RequireFirm(c)
	if !ok {
		return
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
	var invoiceNumber string
	err := config.DB.QueryRow(`
		SELECT total_amount, COALESCE(paid_amount,0), invoice_number
		FROM invoices WHERE id=$1::uuid AND firm_id=$2::uuid
	`, req.InvoiceID, firmID).Scan(&total, &paid, &invoiceNumber)
	if err == sql.ErrNoRows {
		utils.Error(c, http.StatusNotFound, "Invoice not found", "")
		return
	}
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to read invoice", err.Error())
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
	firmID, ok := utils.RequireFirm(c)
	if !ok {
		return
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

	// Resolve the invoice and the amount from the order we recorded at
	// creation time.
	var invoiceID string
	var amountPaise int64
	var orderStatus string
	err := config.DB.QueryRow(`
		SELECT invoice_id::text, amount_paise, status
		FROM payment_orders
		WHERE order_id=$1 AND firm_id=$2::uuid
	`, req.RazorpayOrderID, firmID).Scan(&invoiceID, &amountPaise, &orderStatus)
	if err == sql.ErrNoRows {
		utils.Error(c, http.StatusBadRequest, "Unknown order", "no matching order for this firm")
		return
	}
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to verify", err.Error())
		return
	}
	if orderStatus == "paid" {
		utils.Error(c, http.StatusConflict, "Order already settled", "duplicate verification")
		return
	}

	amount := float64(amountPaise) / 100

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
		verification_status, verified_at)
		VALUES ($1, $2::uuid, $3::uuid, $4, $5, $6, $7, $8, $9::uuid, 'verified', NOW())
		ON CONFLICT (firm_id, transaction_id) DO NOTHING
	`, payID, firmID, invoiceID, amount, today,
		paymentMethod, req.RazorpayPaymentID,
		"Online payment via Razorpay", uID)
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
