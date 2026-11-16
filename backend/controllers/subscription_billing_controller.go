package controllers

import (
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"io"
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

// gracePeriod is how long a firm keeps access after a renewal fails.
//
// Cutting a law firm off from its own case files the instant a card expires is
// not an acceptable failure mode — they may be in court that morning.
const gracePeriod = 7 * 24 * time.Hour

// ─── CHECKOUT ────────────────────────────────
// POST /subscription/checkout  {"plan":"solo","billing_cycle":"monthly"}
//
// Opens a gateway order for a plan. Nothing here trusts a price from the
// client: the amount is read from the plans table, so a caller cannot buy the
// Scale plan for ₹1 by posting their own figure.
func CreateSubscriptionCheckout(c *gin.Context) {
	firmID, ok := utils.RequireFirm(c)
	if !ok {
		return
	}
	if !utils.IsAdmin(c) {
		utils.Error(c, http.StatusForbidden,
			"Only a firm admin can change the subscription", "insufficient role")
		return
	}

	var req struct {
		Plan         string `json:"plan" binding:"required"`
		BillingCycle string `json:"billing_cycle"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}

	cycle := req.BillingCycle
	if cycle == "" {
		cycle = "monthly"
	}
	if cycle != "monthly" && cycle != "yearly" {
		utils.Error(c, http.StatusBadRequest, "Invalid billing cycle",
			"expected 'monthly' or 'yearly'")
		return
	}

	var planID, displayName string
	var monthly, yearly float64
	err := config.DB.QueryRow(`
		SELECT id, display_name, price_monthly, price_yearly
		FROM plans WHERE name = $1 AND is_active = true
	`, req.Plan).Scan(&planID, &displayName, &monthly, &yearly)
	if err == sql.ErrNoRows {
		utils.Error(c, http.StatusBadRequest, "Unknown plan", "no such active plan")
		return
	}
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to read plan", err.Error())
		return
	}

	price := monthly
	if cycle == "yearly" {
		price = yearly
	}
	if price <= 0 {
		utils.Error(c, http.StatusBadRequest,
			"That plan is free — no payment is needed", "zero-price plan")
		return
	}

	// A firm with an active, unexpired subscription must not be able to
	// start a second checkout at all -- enforced here (not just hidden in
	// the Flutter UI) so a direct API call can't buy a second plan on top
	// of one already running. DemoActivateSubscription enforces the same
	// rule for the demo path with a row lock across the whole check+write;
	// this read-then-reject is enough here since CreateSubscriptionCheckout
	// only ever opens a gateway order -- the money/activation only happens
	// later in activateFromOrder, which is itself transactional per order.
	var curStatus string
	var curEnd sql.NullTime
	config.DB.QueryRow(`
		SELECT status, current_period_end FROM subscriptions WHERE firm_id = $1::uuid
	`, firmID).Scan(&curStatus, &curEnd)
	if curStatus == "active" && curEnd.Valid && curEnd.Time.After(time.Now().UTC()) {
		utils.Error(c, http.StatusConflict,
			"Your subscription is already active",
			fmt.Sprintf("current plan is active until %s", curEnd.Time.Format("2 Jan 2006")))
		return
	}

	if !razorpayClient().Configured() {
		utils.Error(c, http.StatusServiceUnavailable,
			"Online payment is not available right now",
			"RAZORPAY_KEY_ID/RAZORPAY_KEY_SECRET unset")
		return
	}

	amountPaise := services.ToPaise(price)

	order, err := razorpayClient().CreateOrder(c.Request.Context(), amountPaise, "INR",
		"sub_"+firmID[:8]+"_"+cycle,
		map[string]string{
			"kind":          "subscription",
			"firm_id":       firmID,
			"plan":          req.Plan,
			"billing_cycle": cycle,
		})
	if err != nil {
		if errors.Is(err, services.ErrGatewayNotConfigured) {
			utils.Error(c, http.StatusServiceUnavailable,
				"Online payment is not available right now", err.Error())
			return
		}
		utils.Error(c, http.StatusBadGateway, "Could not start checkout", err.Error())
		return
	}

	// Record the agreed amount so activation settles against it rather than
	// against anything the client sends back.
	if _, err := config.DB.Exec(`
		INSERT INTO payment_orders
			(id, firm_id, kind, plan_id, billing_cycle, order_id, amount_paise, currency, status, created_by)
		VALUES (gen_random_uuid(), $1::uuid, 'subscription', $2::uuid, $3, $4, $5, 'INR', 'created', $6::uuid)
	`, firmID, planID, cycle, order.ID, amountPaise, utils.UserID(c)); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Could not record order", err.Error())
		return
	}

	utils.Success(c, http.StatusOK, "Checkout started", gin.H{
		"order_id":      order.ID,
		"amount":        amountPaise,
		"amount_rupees": price,
		"currency":      "INR",
		"plan":          req.Plan,
		"plan_name":     displayName,
		"billing_cycle": cycle,
		"key_id":        razorpayClient().KeyID(),
	})
}

// ─── ACTIVATE (client callback) ──────────────
// POST /subscription/activate
//
// The checkout sheet returns here on success. This is the fast path so the app
// can move on immediately; the webhook below is the authoritative one, because
// a user who kills the app after paying never reaches this handler.
func ActivateSubscription(c *gin.Context) {
	firmID, ok := utils.RequireFirm(c)
	if !ok {
		return
	}

	var req struct {
		RazorpayOrderID   string `json:"razorpay_order_id" binding:"required"`
		RazorpayPaymentID string `json:"razorpay_payment_id" binding:"required"`
		RazorpaySignature string `json:"razorpay_signature" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}

	if err := razorpayClient().VerifyPaymentSignature(
		req.RazorpayOrderID, req.RazorpayPaymentID, req.RazorpaySignature,
	); err != nil {
		if errors.Is(err, services.ErrGatewayNotConfigured) {
			utils.Error(c, http.StatusServiceUnavailable,
				"Online payment is not available right now", err.Error())
			return
		}
		utils.Error(c, http.StatusBadRequest, "Invalid payment signature", err.Error())
		return
	}

	status, err := activateFromOrder(req.RazorpayOrderID, req.RazorpayPaymentID, firmID, "razorpay")
	if err != nil {
		if errors.Is(err, errOrderNotFound) {
			utils.Error(c, http.StatusBadRequest, "Unknown order", err.Error())
			return
		}
		if errors.Is(err, errAlreadyApplied) {
			// The webhook beat the client back. Not an error for the user.
			utils.Success(c, http.StatusOK, "Subscription active", currentSubscription(firmID))
			return
		}
		utils.Error(c, http.StatusInternalServerError, "Could not activate subscription", err.Error())
		return
	}

	utils.Success(c, http.StatusOK, "Subscription active", status)
}

// TestActivateSubscription settles a firm's latest subscription checkout
// exactly like ActivateSubscription does — same activateFromOrder call, same
// subscription_payments/subscriptions/firms.plan_id updates, same admin
// notification — but skips Razorpay's signature check. Exists purely so
// plan-gated features can be tested without a working payment gateway.
//
// Gated behind ALLOW_TEST_PAYMENT_BYPASS, same as TestMarkConsultationPaid in
// consultation_controller.go — unset in any real deployment, this 404s as if
// the route never existed. Never enable this where real firms are billed.
func TestActivateSubscription(c *gin.Context) {
	if !strings.EqualFold(config.GetEnv("ALLOW_TEST_PAYMENT_BYPASS", ""), "true") {
		utils.Error(c, http.StatusNotFound, "Not found", "")
		return
	}
	firmID, ok := utils.RequireFirm(c)
	if !ok {
		return
	}

	var orderID string
	if err := config.DB.QueryRow(`
		SELECT order_id FROM payment_orders
		WHERE firm_id=$1::uuid AND kind='subscription'
		ORDER BY created_at DESC LIMIT 1
	`, firmID).Scan(&orderID); err != nil {
		utils.Error(c, http.StatusNotFound, "No subscription checkout found for this firm", "")
		return
	}

	status, err := activateFromOrder(orderID, "TEST_BYPASS_"+uuid.New().String(), firmID, "test")
	if err != nil {
		if errors.Is(err, errOrderNotFound) {
			utils.Error(c, http.StatusBadRequest, "Unknown order", err.Error())
			return
		}
		if errors.Is(err, errAlreadyApplied) {
			utils.Success(c, http.StatusOK, "Subscription active", currentSubscription(firmID))
			return
		}
		utils.Error(c, http.StatusInternalServerError, "Could not activate subscription", err.Error())
		return
	}

	utils.Success(c, http.StatusOK, "TEST payment marked paid — subscription active", status)
}

// ─── DEMO PAYMENT ────────────────────────────
// POST /subscription/demo-pay  {"plan":"solo","billing_cycle":"monthly"}
//
// Real payment gateway integration is not available yet — CreateSubscriptionCheckout
// above 503s without RAZORPAY_KEY_ID/SECRET configured, and TestActivateSubscription
// is a dev-only bypass that 404s unless ALLOW_TEST_PAYMENT_BYPASS=true is set, so
// neither gives an ordinary deployment any way to actually buy a plan. This is a
// real, always-available DEMO payment: no card/UPI/bank details are collected or
// asked for anywhere, no money moves, and every record this writes is explicitly
// tagged payment_mode='demo' (never 'razorpay') so it can never be mistaken for a
// real transaction in the payment/subscription history. Swapping in a real gateway
// later only means adding another payment_mode value next to this one — it does
// not touch activateFromOrder, the webhook, or this handler's callers.
//
// Unlike activateFromOrder (used by the real gateway path and already correct for
// that use), this holds a single row lock across BOTH the "already active" check
// and the activation write, so two demo-pay requests fired at the same instant for
// the same firm cannot both activate: the second blocks on the lock, then re-reads
// a state that already reflects the first's commit and is correctly rejected.
func DemoActivateSubscription(c *gin.Context) {
	firmID, ok := utils.RequireFirm(c)
	if !ok {
		return
	}
	if !utils.IsAdmin(c) {
		utils.Error(c, http.StatusForbidden,
			"Only a firm admin can change the subscription", "insufficient role")
		return
	}

	var req struct {
		Plan         string `json:"plan" binding:"required"`
		BillingCycle string `json:"billing_cycle"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}
	cycle := req.BillingCycle
	if cycle == "" {
		cycle = "monthly"
	}
	if cycle != "monthly" && cycle != "yearly" {
		utils.Error(c, http.StatusBadRequest, "Invalid billing cycle",
			"expected 'monthly' or 'yearly'")
		return
	}

	// The price is read from the plans table, never trusted from the client,
	// same rule CreateSubscriptionCheckout enforces for the real gateway path.
	var planID, displayName string
	var monthly, yearly float64
	err := config.DB.QueryRow(`
		SELECT id, display_name, price_monthly, price_yearly
		FROM plans WHERE name = $1 AND is_active = true
	`, req.Plan).Scan(&planID, &displayName, &monthly, &yearly)
	if err == sql.ErrNoRows {
		utils.Error(c, http.StatusBadRequest, "Unknown plan", "no such active plan")
		return
	}
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to read plan", err.Error())
		return
	}
	price := monthly
	if cycle == "yearly" {
		price = yearly
	}
	if price <= 0 {
		utils.Error(c, http.StatusBadRequest,
			"That plan is free — no payment is needed", "zero-price plan")
		return
	}
	amountPaise := services.ToPaise(price)

	tx, err := config.DB.Begin()
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Could not start payment", err.Error())
		return
	}
	defer tx.Rollback()

	var curStatus string
	var curEnd sql.NullTime
	var subID sql.NullString
	_ = tx.QueryRow(`
		SELECT id::text, status, current_period_end FROM subscriptions
		WHERE firm_id = $1::uuid FOR UPDATE
	`, firmID).Scan(&subID, &curStatus, &curEnd)

	now := time.Now().UTC()
	if curStatus == "active" && curEnd.Valid && curEnd.Time.After(now) {
		utils.Error(c, http.StatusConflict,
			"Your subscription is already active",
			fmt.Sprintf("current plan is active until %s", curEnd.Time.Format("2 Jan 2006")))
		return
	}

	period := 30 * 24 * time.Hour
	if cycle == "yearly" {
		period = 365 * 24 * time.Hour
	}
	start := now
	periodEnd := start.Add(period)

	orderID := "DEMO-ORDER-" + uuid.New().String()
	paymentID := "DEMO-" + strings.ToUpper(strings.ReplaceAll(uuid.New().String(), "-", ""))[:10]

	if _, err := tx.Exec(`
		INSERT INTO payment_orders
			(id, firm_id, kind, plan_id, billing_cycle, order_id, payment_id,
			 amount_paise, currency, status, payment_mode, created_by)
		VALUES (gen_random_uuid(), $1::uuid, 'subscription', $2::uuid, $3, $4, $5,
			$6, 'INR', 'paid', 'demo', $7::uuid)
	`, firmID, planID, cycle, orderID, paymentID, amountPaise, utils.UserID(c)); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Could not record demo order", err.Error())
		return
	}

	if _, err := tx.Exec(`
		INSERT INTO subscription_payments
			(firm_id, subscription_id, plan_id, amount, billing_cycle,
			 order_id, payment_id, status, period_start, period_end, payment_mode)
		VALUES ($1::uuid, NULLIF($2,'')::uuid, $3::uuid, $4, $5, $6, $7, 'captured', $8, $9, 'demo')
	`, firmID, subID.String, planID, price, cycle, orderID, paymentID, start, periodEnd); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Could not record demo payment", err.Error())
		return
	}

	if _, err := tx.Exec(`
		UPDATE subscriptions SET
			plan_id            = $1::uuid,
			billing_cycle      = $2,
			amount             = $3,
			status             = 'active',
			current_period_end = $4,
			started_at         = COALESCE(started_at, $5),
			last_payment_id    = $6,
			last_payment_at    = NOW(),
			grace_until        = NULL,
			cancelled_at       = NULL,
			updated_at         = NOW()
		WHERE firm_id = $7::uuid
	`, planID, cycle, price, periodEnd, now, paymentID, firmID); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Could not activate demo subscription", err.Error())
		return
	}

	if _, err := tx.Exec(`
		UPDATE firms SET plan_id = $1::uuid, updated_at = NOW() WHERE id = $2::uuid
	`, planID, firmID); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Could not activate demo subscription", err.Error())
		return
	}

	if err := tx.Commit(); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Could not activate demo subscription", err.Error())
		return
	}

	log.Printf("[billing] firm %s DEMO-activated on %s until %s", firmID, cycle, periodEnd.Format(time.RFC3339))
	notifyFirmAdmins(firmID, "Subscription active (demo)",
		fmt.Sprintf("Your %s plan is active until %s. This was a demo payment.",
			displayName, periodEnd.Format("2 Jan 2006")))

	utils.Success(c, http.StatusCreated, "Subscription Activated Successfully!", gin.H{
		"plan_name":      displayName,
		"amount":         price,
		"billing_cycle":  cycle,
		"start_date":     start,
		"expiry_date":    periodEnd,
		"transaction_id": paymentID,
		"payment_mode":   "demo",
		"status":         "active",
	})
}

// ─── WEBHOOK ─────────────────────────────────
// POST /webhooks/razorpay
//
// Unauthenticated by definition — anyone can POST here — so the HMAC signature
// over the raw body is the only thing that makes it trustworthy. It runs
// outside the auth middleware and must never read a firm id from anything but
// the order it looks up.
func RazorpayWebhook(c *gin.Context) {
	if !razorpayClient().WebhookConfigured() {
		// 503 rather than silently accepting: an unconfigured webhook endpoint
		// that returns 200 looks healthy in the gateway dashboard while
		// granting nothing.
		utils.Error(c, http.StatusServiceUnavailable,
			"Webhook not configured", "RAZORPAY_WEBHOOK_SECRET unset")
		return
	}

	body, err := io.ReadAll(io.LimitReader(c.Request.Body, 1<<20))
	if err != nil {
		utils.Error(c, http.StatusBadRequest, "Could not read body", err.Error())
		return
	}

	if err := razorpayClient().VerifyWebhookSignature(body, c.GetHeader("X-Razorpay-Signature")); err != nil {
		log.Printf("[webhook] rejected: %v", err)
		utils.Error(c, http.StatusUnauthorized, "Invalid signature", "")
		return
	}

	var event struct {
		Event   string `json:"event"`
		Payload struct {
			Payment struct {
				Entity struct {
					ID      string `json:"id"`
					OrderID string `json:"order_id"`
					Status  string `json:"status"`
					Amount  int64  `json:"amount"`
				} `json:"entity"`
			} `json:"payment"`
		} `json:"payload"`
	}
	if err := json.Unmarshal(body, &event); err != nil {
		utils.Error(c, http.StatusBadRequest, "Malformed payload", err.Error())
		return
	}

	// Razorpay sends its event id in a header, not the body.
	eventID := c.GetHeader("X-Razorpay-Event-Id")
	if eventID == "" {
		eventID = event.Payload.Payment.Entity.ID + ":" + event.Event
	}

	// Record first. Gateways retry aggressively and deliver out of order, so
	// the unique index on (provider, event_id) is what turns a replay into a
	// no-op instead of a second billing period granted for one payment.
	res, err := config.DB.Exec(`
		INSERT INTO webhook_events (provider, event_id, event_type, payload)
		VALUES ('razorpay', $1, $2, $3)
		ON CONFLICT (provider, event_id) DO NOTHING
	`, eventID, event.Event, body)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Could not record event", err.Error())
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		// Already seen. Answer 200 or the gateway keeps retrying forever.
		c.JSON(http.StatusOK, gin.H{"success": true, "message": "Duplicate event ignored"})
		return
	}

	var handlerErr error
	switch event.Event {
	case "payment.captured", "order.paid":
		p := event.Payload.Payment.Entity
		if p.OrderID != "" {
			// firmID is empty: activateFromOrder resolves the tenant from the
			// recorded order, never from the request.
			_, handlerErr = activateFromOrder(p.OrderID, p.ID, "", "razorpay")
			if errors.Is(handlerErr, errAlreadyApplied) || errors.Is(handlerErr, errOrderNotFound) {
				// Not-found covers invoice orders, which the invoice flow
				// handles; neither is a delivery failure.
				handlerErr = nil
			}
		}
	case "payment.failed":
		p := event.Payload.Payment.Entity
		config.DB.Exec(`
			UPDATE payment_orders SET status='failed', payment_id=$1, updated_at=NOW()
			WHERE order_id=$2 AND status='created'
		`, p.ID, p.OrderID)
	default:
		// Unhandled event types are recorded and acknowledged.
	}

	errText := ""
	if handlerErr != nil {
		errText = handlerErr.Error()
		log.Printf("[webhook] %s (%s) failed: %v", event.Event, eventID, handlerErr)
	}
	config.DB.Exec(`
		UPDATE webhook_events SET processed_at=NOW(), error=NULLIF($1,'')
		WHERE provider='razorpay' AND event_id=$2
	`, errText, eventID)

	// Always 200 once the event is durably recorded. Returning 5xx here makes
	// the gateway retry an event that is already stored, and the retry is
	// deduplicated anyway — so the retry loop would never terminate.
	c.JSON(http.StatusOK, gin.H{"success": true, "message": "Received"})
}

var (
	errOrderNotFound  = errors.New("no matching subscription order")
	errAlreadyApplied = errors.New("payment already applied")
)

// activateFromOrder is the single place a subscription becomes paid. Both the
// client callback and the webhook funnel through it, so they cannot drift.
//
// expectFirmID is checked when the caller is an authenticated user; the webhook
// passes "" because it has no session and takes the tenant from the order row.
func activateFromOrder(orderID, paymentID, expectFirmID, paymentMode string) (gin.H, error) {
	tx, err := config.DB.Begin()
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	var (
		firmID      string
		planID      sql.NullString
		cycle       string
		amountPaise int64
		orderStatus string
	)
	err = tx.QueryRow(`
		SELECT firm_id::text, plan_id::text, COALESCE(billing_cycle,'monthly'),
		       amount_paise, status
		FROM payment_orders
		WHERE order_id = $1 AND kind = 'subscription'
		FOR UPDATE
	`, orderID).Scan(&firmID, &planID, &cycle, &amountPaise, &orderStatus)
	if err == sql.ErrNoRows {
		return nil, errOrderNotFound
	}
	if err != nil {
		return nil, err
	}

	// A signed-in caller may only settle their own firm's order.
	if expectFirmID != "" && firmID != expectFirmID {
		return nil, errOrderNotFound
	}

	period := 30 * 24 * time.Hour
	if cycle == "yearly" {
		period = 365 * 24 * time.Hour
	}

	now := time.Now().UTC()

	// Extend from the existing expiry when the firm renews early, so paying
	// ahead of time does not throw away the days they already own.
	var currentEnd sql.NullTime
	var subID sql.NullString
	tx.QueryRow(`
		SELECT id::text, current_period_end FROM subscriptions WHERE firm_id = $1::uuid
	`, firmID).Scan(&subID, &currentEnd)

	start := now
	if currentEnd.Valid && currentEnd.Time.After(now) {
		start = currentEnd.Time
	}
	periodEnd := start.Add(period)

	// The unique index on payment_id is the real idempotency guard: a replayed
	// webhook and a retried client callback both land here, and only the first
	// inserts.
	res, err := tx.Exec(`
		INSERT INTO subscription_payments
			(firm_id, subscription_id, plan_id, amount, billing_cycle,
			 order_id, payment_id, status, period_start, period_end, payment_mode)
		VALUES ($1::uuid, NULLIF($2,'')::uuid, $3::uuid, $4, $5, $6, $7, 'captured', $8, $9, $10)
		ON CONFLICT (payment_id) DO NOTHING
	`, firmID, subID.String, planID, float64(amountPaise)/100, cycle,
		orderID, paymentID, start, periodEnd, paymentMode)
	if err != nil {
		return nil, err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return nil, errAlreadyApplied
	}

	if _, err := tx.Exec(`
		UPDATE subscriptions SET
			plan_id            = $1::uuid,
			billing_cycle      = $2,
			amount             = $3,
			status             = 'active',
			current_period_end = $4,
			started_at         = COALESCE(started_at, $5),
			last_payment_id    = $6,
			last_payment_at    = NOW(),
			grace_until        = NULL,
			cancelled_at       = NULL,
			updated_at         = NOW()
		WHERE firm_id = $7::uuid
	`, planID, cycle, float64(amountPaise)/100, periodEnd, now, paymentID, firmID); err != nil {
		return nil, err
	}

	if _, err := tx.Exec(`
		UPDATE firms SET plan_id = $1::uuid, updated_at = NOW() WHERE id = $2::uuid
	`, planID, firmID); err != nil {
		return nil, err
	}

	if _, err := tx.Exec(`
		UPDATE payment_orders SET status='paid', payment_id=$1, updated_at=NOW()
		WHERE order_id=$2
	`, paymentID, orderID); err != nil {
		return nil, err
	}

	if err := tx.Commit(); err != nil {
		return nil, err
	}

	log.Printf("[billing] firm %s activated on %s until %s", firmID, cycle, periodEnd.Format(time.RFC3339))

	notifyFirmAdmins(firmID, "Subscription active",
		fmt.Sprintf("Your plan is active until %s.", periodEnd.Format("2 Jan 2006")))

	return currentSubscription(firmID), nil
}

// notifyFirmAdmins posts an in-app notification (+ push) to every lawyer at
// the firm — there is no separate "admin"/owner role to target specifically.
func notifyFirmAdmins(firmID, title, message string) {
	rows, err := config.DB.Query(`
		SELECT u.id FROM users u
		JOIN roles r ON u.role_id = r.id
		WHERE u.firm_id = $1::uuid AND u.is_active = true AND r.name = 'lawyer'
	`, firmID)
	if err != nil {
		return
	}
	defer rows.Close()
	for rows.Next() {
		var adminID string
		if rows.Scan(&adminID) == nil {
			utils.Notify(adminID, firmID, title, message, "general")
		}
	}
}

// currentSubscription re-reads the firm's entitlement for a response body.
func currentSubscription(firmID string) gin.H {
	var status, planName string
	var periodEnd sql.NullTime
	config.DB.QueryRow(`
		SELECT s.status, COALESCE(p.display_name,''), s.current_period_end
		FROM subscriptions s
		LEFT JOIN plans p ON s.plan_id = p.id
		WHERE s.firm_id = $1::uuid
	`, firmID).Scan(&status, &planName, &periodEnd)

	out := gin.H{"status": status, "plan_name": planName, "is_active": status == "active"}
	if periodEnd.Valid {
		out["current_period_end"] = periodEnd.Time
		out["days_remaining"] = int(time.Until(periodEnd.Time).Hours() / 24)
	}
	return out
}

// ─── CANCEL ──────────────────────────────────
// POST /subscription/cancel
//
// Marks the subscription cancelled but leaves access running to the end of the
// period already paid for. Revoking immediately would be taking money for days
// not delivered.
func CancelSubscription(c *gin.Context) {
	firmID, ok := utils.RequireFirm(c)
	if !ok {
		return
	}
	if !utils.IsAdmin(c) {
		utils.Error(c, http.StatusForbidden,
			"Only a firm admin can cancel the subscription", "insufficient role")
		return
	}

	res, err := config.DB.Exec(`
		UPDATE subscriptions SET status='cancelled', cancelled_at=NOW(), updated_at=NOW()
		WHERE firm_id=$1::uuid AND status IN ('active','past_due','trial')
	`, firmID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Could not cancel", err.Error())
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		utils.Error(c, http.StatusNotFound, "No active subscription to cancel", "")
		return
	}

	utils.LogAudit(c, utils.AuditEntry{
		Action:      "SUBSCRIPTION_UPDATED",
		Module:      "subscriptions",
		TargetType:  "firm",
		TargetID:    firmID,
		Description: "Subscription cancelled",
		After:       map[string]string{"status": "cancelled"},
	})

	utils.Success(c, http.StatusOK,
		"Subscription cancelled. Access continues until the end of the paid period.",
		currentSubscription(firmID))
}

// ─── BILLING HISTORY ─────────────────────────
// GET /subscription/payments
func GetSubscriptionPayments(c *gin.Context) {
	firmID, ok := utils.RequireFirm(c)
	if !ok {
		return
	}
	page := ParsePagination(c)

	rows, err := config.DB.Query(`
		SELECT sp.id, sp.amount, sp.currency, COALESCE(sp.billing_cycle,''),
		       COALESCE(p.display_name,''), sp.payment_id,
		       sp.period_start, sp.period_end, sp.created_at,
		       sp.status, sp.payment_mode
		FROM subscription_payments sp
		LEFT JOIN plans p ON sp.plan_id = p.id
		WHERE sp.firm_id = $1::uuid
		ORDER BY sp.created_at DESC
		LIMIT $2 OFFSET $3
	`, firmID, page.Limit, page.Offset)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch billing history", err.Error())
		return
	}
	defer rows.Close()

	type Row struct {
		ID           string    `json:"id"`
		Amount       float64   `json:"amount"`
		Currency     string    `json:"currency"`
		BillingCycle string    `json:"billing_cycle"`
		PlanName     string    `json:"plan_name"`
		PaymentID    string    `json:"payment_id"`
		PeriodStart  time.Time `json:"period_start"`
		PeriodEnd    time.Time `json:"period_end"`
		CreatedAt    time.Time `json:"created_at"`
		Status       string    `json:"status"`
		PaymentMode  string    `json:"payment_mode"`
	}

	out := []Row{}
	for rows.Next() {
		var r Row
		if err := rows.Scan(&r.ID, &r.Amount, &r.Currency, &r.BillingCycle,
			&r.PlanName, &r.PaymentID, &r.PeriodStart, &r.PeriodEnd, &r.CreatedAt,
			&r.Status, &r.PaymentMode); err != nil {
			utils.Error(c, http.StatusInternalServerError, "Failed to read history", err.Error())
			return
		}
		out = append(out, r)
	}

	utils.SuccessWithMeta(c, http.StatusOK, "Billing history fetched", out, page.Meta(len(out)))
}
