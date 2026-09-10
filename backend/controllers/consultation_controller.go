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

// consultationCallType maps whatever the booking screen stored in
// consultation_type ("Audio Call", "Video Call", "Chat", "audio_call", ...)
// to a fixed key, the same case-insensitive rule already used on both the
// client portal and lawyer dashboard sides, so the two independent
// front-end copies of this logic and this one agree.
func consultationCallType(rawType string) string {
	t := strings.ToLower(rawType)
	if strings.Contains(t, "audio") {
		return "audio"
	}
	if strings.Contains(t, "video") {
		return "video"
	}
	return "chat"
}

// BookConsultation - Client books with lawyer
func BookConsultation(c *gin.Context) {
	userID := utils.UserID(c)

	var req struct {
		LawyerID         string `json:"lawyer_id" binding:"required"`
		ConsultationType string `json:"consultation_type" binding:"required"`
		ConsultationDate string `json:"consultation_date" binding:"required"`
		ConsultationTime string `json:"consultation_time" binding:"required"`
		Notes            string `json:"notes"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}

	if !isUUID(req.LawyerID) {
		utils.Error(c, http.StatusBadRequest, "Invalid lawyer_id", "not a uuid")
		return
	}

	// The booking used to be written against whatever lawyer_id arrived, so a
	// consultation could be filed against a client's or a student's account.
	var lawyerName string
	if err := config.DB.QueryRow(`
		SELECT u.name FROM users u JOIN roles r ON u.role_id = r.id
		WHERE u.id=$1::uuid AND u.is_active=true AND r.name IN ('admin','lawyer')
	`, req.LawyerID).Scan(&lawyerName); err != nil {
		utils.Error(c, http.StatusBadRequest, "Unknown lawyer", "no such active lawyer")
		return
	}

	id := uuid.New().String()
	_, err := config.DB.Exec(`
		INSERT INTO consultations (
			id, client_id, lawyer_id, consultation_type,
			consultation_date, consultation_time, notes, status, created_at
		) VALUES ($1, $2::uuid, $3::uuid, $4, $5::date, $6, $7, 'pending', NOW())
	`, id, userID, req.LawyerID, req.ConsultationType,
		req.ConsultationDate, req.ConsultationTime, req.Notes)

	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to book consultation", err.Error())
		return
	}

	utils.Success(c, http.StatusCreated, "Consultation booked successfully", gin.H{
		"id":                id,
		"consultation_type": req.ConsultationType,
		"consultation_date": req.ConsultationDate,
		"consultation_time": req.ConsultationTime,
		"status":            "pending",
		"lawyer_name":       lawyerName,
	})
}

// consultationPricePaise is the single place a consultation's price is
// decided. Every consultation costs a flat ₹5 today, regardless of lawyer or
// type; when lawyers set their own rates this becomes a lookup (e.g. by
// lawyerID/consultationType) instead of a rewrite of the payment flow that
// calls it.
func consultationPricePaise(lawyerID, consultationType string) int64 {
	return 500 // ₹5
}

// ─── CREATE CONSULTATION CHECKOUT ────────────
// POST /portal/book-consultation/checkout
//
// Opens a Razorpay order for a consultation booking. The consultations row is
// created now, in 'pending' status with payment_status 'pending' — it is
// invisible to the lawyer (see the payment_status filter in
// GetLawyerConsultations) until VerifyConsultationPayment marks it paid.
// Nothing is confirmed until the payment is verified.
//
// Passing consultation_id resumes an existing unpaid booking instead of
// creating a new one, so retrying a failed/cancelled payment does not leave
// duplicate bookings behind.
func CreateConsultationCheckout(c *gin.Context) {
	userID := utils.UserID(c)

	var req struct {
		ConsultationID   string `json:"consultation_id"`
		LawyerID         string `json:"lawyer_id"`
		ConsultationType string `json:"consultation_type"`
		ConsultationDate string `json:"consultation_date"`
		ConsultationTime string `json:"consultation_time"`
		Notes            string `json:"notes"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}

	if !razorpayClient().Configured() {
		utils.Error(c, http.StatusServiceUnavailable,
			"Online payment is not configured", "RAZORPAY_KEY_ID/RAZORPAY_KEY_SECRET unset")
		return
	}

	var consultationID, lawyerID, lawyerName, consultType, consultDate, consultTime string

	if req.ConsultationID != "" {
		// Retry: reuse the same booking rather than creating a duplicate. Only
		// the client who owns it, and only while it is still unpaid, may retry.
		if !isUUID(req.ConsultationID) {
			utils.Error(c, http.StatusBadRequest, "Invalid consultation_id", "not a uuid")
			return
		}
		err := config.DB.QueryRow(`
			SELECT co.id::text, co.lawyer_id::text, COALESCE(l.name,''),
			       co.consultation_type, co.consultation_date::text, co.consultation_time
			FROM consultations co
			JOIN users l ON co.lawyer_id = l.id
			WHERE co.id=$1::uuid AND co.client_id=$2::uuid AND co.payment_status IN ('pending','failed')
		`, req.ConsultationID, userID).Scan(
			&consultationID, &lawyerID, &lawyerName, &consultType, &consultDate, &consultTime)
		if err == sql.ErrNoRows {
			utils.Error(c, http.StatusNotFound, "Booking not found",
				"already paid, cancelled, or not yours to retry")
			return
		}
		if err != nil {
			utils.Error(c, http.StatusInternalServerError, "Failed to load booking", err.Error())
			return
		}
	} else {
		if req.LawyerID == "" || req.ConsultationType == "" ||
			req.ConsultationDate == "" || req.ConsultationTime == "" {
			utils.Error(c, http.StatusBadRequest, "Invalid request",
				"lawyer_id, consultation_type, consultation_date and consultation_time are required")
			return
		}
		if !isUUID(req.LawyerID) {
			utils.Error(c, http.StatusBadRequest, "Invalid lawyer_id", "not a uuid")
			return
		}
		if err := config.DB.QueryRow(`
			SELECT u.name FROM users u JOIN roles r ON u.role_id = r.id
			WHERE u.id=$1::uuid AND u.is_active=true AND r.name IN ('admin','lawyer')
		`, req.LawyerID).Scan(&lawyerName); err != nil {
			utils.Error(c, http.StatusBadRequest, "Unknown lawyer", "no such active lawyer")
			return
		}

		lawyerID = req.LawyerID
		consultType = req.ConsultationType
		consultDate = req.ConsultationDate
		consultTime = req.ConsultationTime
		consultationID = uuid.New().String()

		if _, err := config.DB.Exec(`
			INSERT INTO consultations (
				id, client_id, lawyer_id, consultation_type,
				consultation_date, consultation_time, notes, status,
				payment_status, amount_paise, created_at
			) VALUES ($1, $2::uuid, $3::uuid, $4, $5::date, $6, $7, 'pending',
				'pending', $8, NOW())
		`, consultationID, userID, lawyerID, consultType, consultDate, consultTime,
			req.Notes, consultationPricePaise(lawyerID, consultType)); err != nil {
			utils.Error(c, http.StatusInternalServerError, "Failed to start booking", err.Error())
			return
		}
	}

	amountPaise := consultationPricePaise(lawyerID, consultType)

	order, err := razorpayClient().CreateOrder(c.Request.Context(), amountPaise, "INR",
		"consult_"+consultationID[:8],
		map[string]string{
			"kind":            "consultation",
			"consultation_id": consultationID,
			"client_id":       userID,
			"lawyer_id":       lawyerID,
		})
	if err != nil {
		if errors.Is(err, services.ErrGatewayNotConfigured) {
			utils.Error(c, http.StatusServiceUnavailable,
				"Online payment is not configured", err.Error())
			return
		}
		utils.Error(c, http.StatusBadGateway, "Could not start payment", err.Error())
		return
	}

	if _, err := config.DB.Exec(`
		INSERT INTO payment_orders (id, kind, consultation_id, order_id, amount_paise, currency, status, created_by)
		VALUES (gen_random_uuid(), 'consultation', $1::uuid, $2, $3, 'INR', 'created', $4::uuid)
	`, consultationID, order.ID, amountPaise, userID); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Could not record order", err.Error())
		return
	}

	utils.Success(c, http.StatusOK, "Checkout started", gin.H{
		"consultation_id":   consultationID,
		"order_id":          order.ID,
		"amount":            amountPaise,
		"amount_rupees":     float64(amountPaise) / 100,
		"currency":          "INR",
		"key_id":            razorpayClient().KeyID(),
		"lawyer_id":         lawyerID,
		"lawyer_name":       lawyerName,
		"consultation_type": consultType,
		"consultation_date": consultDate,
		"consultation_time": consultTime,
	})
}

var (
	errConsultationOrderNotFound = errors.New("no matching consultation order")
	errNotYourConsultation       = errors.New("not your booking")
)

// confirmConsultationPayment is the single place a consultation payment
// becomes 'paid'. Mirrors activateFromOrder in subscription_billing_controller.go:
// resolve the order under FOR UPDATE, no-op if it was already settled, then
// confirm the booking and close the order together in one transaction.
//
// A replayed call (double-tap, retried client callback) lands on the
// "already paid" branch and simply returns the current state — no second
// update, no second notification, no duplicate booking.
func confirmConsultationPayment(orderID, paymentID, callerID string) (gin.H, error) {
	tx, err := config.DB.Begin()
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	var consultationID, clientID string
	var amountPaise int64
	var orderStatus string
	err = tx.QueryRow(`
		SELECT po.consultation_id::text, co.client_id::text, po.amount_paise, po.status
		FROM payment_orders po
		JOIN consultations co ON co.id = po.consultation_id
		WHERE po.order_id=$1 AND po.kind='consultation'
		FOR UPDATE OF po
	`, orderID).Scan(&consultationID, &clientID, &amountPaise, &orderStatus)
	if err == sql.ErrNoRows {
		return nil, errConsultationOrderNotFound
	}
	if err != nil {
		return nil, err
	}
	if clientID != callerID {
		return nil, errNotYourConsultation
	}

	if orderStatus != "paid" {
		// Payment only proves the client paid — it does not grant them a slot
		// on the lawyer's calendar. This used to jump straight to 'confirmed',
		// which skipped the lawyer's accept/reject decision entirely: every
		// paid booking silently confirmed itself and the lawyer's existing
		// Pending/Confirm/Decline UI never actually saw a booking to act on.
		// Leaving status at 'pending' here is what makes that already-built
		// accept/reject flow (see UpdateConsultation) actually run.
		if _, err := tx.Exec(`
			UPDATE consultations SET
				status='pending', payment_status='paid',
				razorpay_payment_id=$1, paid_at=NOW(), updated_at=NOW()
			WHERE id=$2::uuid
		`, paymentID, consultationID); err != nil {
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
		notifyConsultationPaid(consultationID, amountPaise)
	}

	return fetchConsultationSummary(consultationID), nil
}

// fetchConsultationSummary re-reads a booking for a payment-flow response
// body, after either a fresh confirmation or a replayed one.
func fetchConsultationSummary(consultationID string) gin.H {
	var status, paymentStatus, consultType, consultDate, consultTime, lawyerName, clientName string
	var amountPaise sql.NullInt64
	config.DB.QueryRow(`
		SELECT co.status, co.payment_status, co.consultation_type,
		       co.consultation_date::text, co.consultation_time,
		       COALESCE(l.name,''), COALESCE(cl.name,''), co.amount_paise
		FROM consultations co
		LEFT JOIN users l  ON co.lawyer_id = l.id
		LEFT JOIN users cl ON co.client_id = cl.id
		WHERE co.id = $1::uuid
	`, consultationID).Scan(&status, &paymentStatus, &consultType, &consultDate, &consultTime,
		&lawyerName, &clientName, &amountPaise)

	out := gin.H{
		"id":                 consultationID,
		"status":             status,
		"payment_status":     paymentStatus,
		"consultation_type":  consultType,
		"consultation_date":  consultDate,
		"consultation_time":  consultTime,
		"lawyer_name":        lawyerName,
		"client_name":        clientName,
	}
	if amountPaise.Valid {
		out["amount_rupees"] = float64(amountPaise.Int64) / 100
	}
	return out
}

// notifyConsultationPaid tells the lawyer a paid booking has landed and the
// client that their payment went through, via the existing in-app +
// push-notification pipeline (utils.NotifyWithRef). Mirrors
// notifyPaymentRecorded in payment_gateway_controller.go — failures here
// never fail the payment, which has already been committed.
func notifyConsultationPaid(consultationID string, amountPaise int64) {
	var lawyerID, clientID, lawyerFirmID, lawyerName, clientName string
	var consultType, consultDate, consultTime string
	err := config.DB.QueryRow(`
		SELECT co.lawyer_id::text, co.client_id::text, COALESCE(l.firm_id::text,''),
		       COALESCE(l.name,'Your lawyer'), COALESCE(cl.name,'Your client'),
		       co.consultation_type, co.consultation_date::text, co.consultation_time
		FROM consultations co
		JOIN users l  ON co.lawyer_id = l.id
		JOIN users cl ON co.client_id = cl.id
		WHERE co.id = $1::uuid
	`, consultationID).Scan(&lawyerID, &clientID, &lawyerFirmID, &lawyerName, &clientName,
		&consultType, &consultDate, &consultTime)
	if err != nil {
		return
	}

	amount := formatINR(float64(amountPaise) / 100)

	utils.NotifyWithRef(lawyerID, lawyerFirmID,
		"New booking request",
		fmt.Sprintf("%s requested a %s consultation with you on %s at %s (paid: %s). Accept or reject it from My Bookings.",
			clientName, consultType, consultDate, consultTime, amount),
		"booking_request", consultationID, "consultation")

	utils.NotifyWithRef(clientID, "",
		"Payment successful — awaiting lawyer confirmation",
		fmt.Sprintf("Your payment of %s was successful. Your %s consultation request with %s on %s at %s is waiting for the lawyer to accept.",
			amount, consultType, lawyerName, consultDate, consultTime),
		"general", consultationID, "consultation")
}

// ─── VERIFY CONSULTATION PAYMENT ─────────────
// POST /portal/book-consultation/verify
//
// The checkout screen returns here after Razorpay reports success. Signature
// verification is mandatory — nothing here trusts the frontend's word that
// payment succeeded; the server recomputes it against RAZORPAY_KEY_SECRET.
// Only once that passes does confirmConsultationPayment confirm the booking.
func VerifyConsultationPayment(c *gin.Context) {
	userID := utils.UserID(c)

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
				"Online payment is not configured", err.Error())
			return
		}
		utils.Error(c, http.StatusBadRequest, "Invalid payment signature", err.Error())
		return
	}

	result, err := confirmConsultationPayment(req.RazorpayOrderID, req.RazorpayPaymentID, userID)
	if err != nil {
		switch {
		case errors.Is(err, errConsultationOrderNotFound):
			utils.Error(c, http.StatusBadRequest, "Unknown order", "no matching consultation order")
		case errors.Is(err, errNotYourConsultation):
			utils.Error(c, http.StatusForbidden, "Not your booking", "")
		default:
			utils.Error(c, http.StatusInternalServerError, "Failed to confirm booking", err.Error())
		}
		return
	}

	utils.Success(c, http.StatusOK, "Payment verified — booking confirmed", result)
}

// GetMyConsultations - Client sees their bookings
func GetMyConsultations(c *gin.Context) {
	userID, _ := c.Get("user_id")

	rows, err := config.DB.Query(`
		SELECT con.id, con.consultation_type,
			con.consultation_date::text, con.consultation_time,
			con.status, COALESCE(con.notes,''),
			COALESCE(con.lawyer_notes,''), COALESCE(con.meeting_link,''),
			con.lawyer_id::text,
			COALESCE(u.name,'') as lawyer_name,
			COALESCE(u.phone,'') as lawyer_phone,
			con.payment_status, COALESCE(con.amount_paise,0),
			COALESCE(con.call_duration_seconds,0),
			con.created_at
		FROM consultations con
		LEFT JOIN users u ON con.lawyer_id = u.id
		WHERE con.client_id = $1::uuid
		ORDER BY con.consultation_date DESC
	`, userID)

	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch consultations", err.Error())
		return
	}
	defer rows.Close()

	type Consultation struct {
		ID                  string    `json:"id"`
		ConsultationType    string    `json:"consultation_type"`
		ConsultationDate    string    `json:"consultation_date"`
		ConsultationTime    string    `json:"consultation_time"`
		Status              string    `json:"status"`
		Notes               string    `json:"notes"`
		LawyerNotes         string    `json:"lawyer_notes"`
		MeetingLink         string    `json:"meeting_link"`
		LawyerID            string    `json:"lawyer_id"`
		LawyerName          string    `json:"lawyer_name"`
		LawyerPhone         string    `json:"lawyer_phone"`
		PaymentStatus       string    `json:"payment_status"`
		AmountPaise         int64     `json:"amount_paise"`
		CallDurationSeconds int       `json:"call_duration_seconds"`
		CreatedAt           time.Time `json:"created_at"`
	}

	consultations := []Consultation{}
	for rows.Next() {
		var con Consultation
		rows.Scan(
			&con.ID, &con.ConsultationType, &con.ConsultationDate,
			&con.ConsultationTime, &con.Status, &con.Notes,
			&con.LawyerNotes, &con.MeetingLink, &con.LawyerID,
			&con.LawyerName, &con.LawyerPhone,
			&con.PaymentStatus, &con.AmountPaise, &con.CallDurationSeconds, &con.CreatedAt,
		)
		consultations = append(consultations, con)
	}

	utils.Success(c, http.StatusOK, "Consultations fetched", consultations)
}

// GetLawyerConsultations - Lawyer sees all booking requests
func GetLawyerConsultations(c *gin.Context) {
	userID, _ := c.Get("user_id")
	status := c.Query("status")

	// payment_status = 'paid' is not optional here: an unpaid consultation
	// (still mid-checkout, abandoned, or created through the old free
	// /portal/book-consultation path) must never reach the lawyer's booking
	// list. The lawyer only ever sees a booking once it is paid and confirmed.
	query := `
		SELECT con.id, con.consultation_type,
			con.consultation_date::text, con.consultation_time,
			con.status, COALESCE(con.notes,''),
			COALESCE(con.lawyer_notes,''), COALESCE(con.meeting_link,''),
			COALESCE(u.name,'') as client_name,
			COALESCE(u.email,'') as client_email,
			COALESCE(u.phone,'') as client_phone,
			con.payment_status, COALESCE(con.amount_paise,0),
			COALESCE(con.call_duration_seconds,0),
			con.created_at
		FROM consultations con
		LEFT JOIN users u ON con.client_id = u.id
		WHERE con.lawyer_id = $1::uuid AND con.payment_status = 'paid'`

	args := []interface{}{userID}
	if status != "" {
		query += ` AND con.status = $2`
		args = append(args, status)
	}
	query += ` ORDER BY con.consultation_date ASC`

	rows, err := config.DB.Query(query, args...)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch consultations", err.Error())
		return
	}
	defer rows.Close()

	type Consultation struct {
		ID                  string    `json:"id"`
		ConsultationType    string    `json:"consultation_type"`
		ConsultationDate    string    `json:"consultation_date"`
		ConsultationTime    string    `json:"consultation_time"`
		Status              string    `json:"status"`
		Notes               string    `json:"notes"`
		LawyerNotes         string    `json:"lawyer_notes"`
		MeetingLink         string    `json:"meeting_link"`
		ClientName          string    `json:"client_name"`
		ClientEmail         string    `json:"client_email"`
		ClientPhone         string    `json:"client_phone"`
		PaymentStatus       string    `json:"payment_status"`
		AmountPaise         int64     `json:"amount_paise"`
		CallDurationSeconds int       `json:"call_duration_seconds"`
		CreatedAt           time.Time `json:"created_at"`
	}

	consultations := []Consultation{}
	for rows.Next() {
		var con Consultation
		rows.Scan(
			&con.ID, &con.ConsultationType, &con.ConsultationDate,
			&con.ConsultationTime, &con.Status, &con.Notes,
			&con.LawyerNotes, &con.MeetingLink,
			&con.ClientName, &con.ClientEmail, &con.ClientPhone,
			&con.PaymentStatus, &con.AmountPaise, &con.CallDurationSeconds, &con.CreatedAt,
		)
		consultations = append(consultations, con)
	}

	utils.Success(c, http.StatusOK, "Consultations fetched", consultations)
}

// validEarningsStatus is the set of filters the Billing screen's chips send.
// "all" means no filter.
func validEarningsStatus(s string) bool {
	switch s {
	case "all", "paid", "pending", "refunded":
		return true
	}
	return false
}

// GetLawyerEarnings - Lawyer's Billing tab: a read-only ledger of money from
// consultation payments. Distinct from GetLawyerConsultations (the booking
// queue, which only ever shows payment_status='paid' rows): this is a money
// view, so a pending or refunded payment attempt is legitimate to show here
// even though it never becomes an actionable booking request.
//
// GET /consultations/earnings?status=all|paid|pending|refunded&from=&to=
func GetLawyerEarnings(c *gin.Context) {
	userID, _ := c.Get("user_id")
	status := c.DefaultQuery("status", "all")
	if !validEarningsStatus(status) {
		utils.Error(c, http.StatusBadRequest, "Invalid status",
			"expected one of: all, paid, pending, refunded")
		return
	}
	from := c.Query("from") // YYYY-MM-DD, inclusive
	to := c.Query("to")     // YYYY-MM-DD, inclusive

	// amount_paise IS NOT NULL excludes bookings made through the old free
	// /portal/book-consultation path (never a payment transaction to begin
	// with) from every count below — earnings, and this ledger, are about
	// money that actually moved through Razorpay.
	summary := gin.H{}
	var totalPaise, pendingPaise, refundedPaise sql.NullInt64
	var paidCount, pendingCount, refundedCount, totalCount int
	err := config.DB.QueryRow(`
		SELECT
			COALESCE(SUM(amount_paise) FILTER (WHERE payment_status='paid'), 0),
			COALESCE(SUM(amount_paise) FILTER (WHERE payment_status='pending'), 0),
			COALESCE(SUM(amount_paise) FILTER (WHERE payment_status='refunded'), 0),
			COUNT(*) FILTER (WHERE payment_status='paid'),
			COUNT(*) FILTER (WHERE payment_status='pending'),
			COUNT(*) FILTER (WHERE payment_status='refunded'),
			COUNT(*)
		FROM consultations
		WHERE lawyer_id = $1::uuid AND amount_paise IS NOT NULL
	`, userID).Scan(&totalPaise, &pendingPaise, &refundedPaise,
		&paidCount, &pendingCount, &refundedCount, &totalCount)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to compute earnings", err.Error())
		return
	}

	earnings := float64(totalPaise.Int64) / 100
	summary["total_earnings"] = earnings
	// Razorpay settles to the firm's bank account on its own cycle; nothing in
	// this app tracks that settlement, so "received" is the same figure as
	// "earnings" today — both mean "successfully paid by the client".
	summary["total_received"] = earnings
	summary["pending_amount"] = float64(pendingPaise.Int64) / 100
	summary["refunded_amount"] = float64(refundedPaise.Int64) / 100
	summary["completed_payments"] = paidCount
	summary["pending_payments"] = pendingCount
	summary["refunded_payments"] = refundedCount
	summary["total_transactions"] = totalCount

	page := ParsePagination(c)

	query := `
		SELECT co.id, co.consultation_type, co.consultation_date::text, co.consultation_time,
		       COALESCE(u.name,'') as client_name,
		       co.payment_status, COALESCE(co.amount_paise,0),
		       COALESCE(co.razorpay_payment_id,''), COALESCE(co.payment_method,''),
		       co.paid_at, co.created_at,
		       COALESCE(o.order_id,'')
		FROM consultations co
		LEFT JOIN users u ON co.client_id = u.id
		LEFT JOIN LATERAL (
			SELECT order_id FROM payment_orders po
			WHERE po.consultation_id = co.id
			ORDER BY po.updated_at DESC LIMIT 1
		) o ON true
		WHERE co.lawyer_id = $1::uuid AND co.amount_paise IS NOT NULL`

	args := []interface{}{userID}
	if status != "all" {
		query += fmt.Sprintf(" AND co.payment_status = $%d", len(args)+1)
		args = append(args, status)
	}
	if from != "" {
		query += fmt.Sprintf(" AND co.consultation_date >= $%d::date", len(args)+1)
		args = append(args, from)
	}
	if to != "" {
		query += fmt.Sprintf(" AND co.consultation_date <= $%d::date", len(args)+1)
		args = append(args, to)
	}
	query += fmt.Sprintf(" ORDER BY co.created_at DESC LIMIT $%d OFFSET $%d", len(args)+1, len(args)+2)
	args = append(args, page.Limit, page.Offset)

	rows, err := config.DB.Query(query, args...)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch transactions", err.Error())
		return
	}
	defer rows.Close()

	type Transaction struct {
		ID                string     `json:"id"`
		ConsultationType  string     `json:"consultation_type"`
		ConsultationDate  string     `json:"consultation_date"`
		ConsultationTime  string     `json:"consultation_time"`
		ClientName        string     `json:"client_name"`
		PaymentStatus     string     `json:"payment_status"`
		AmountPaise       int64      `json:"amount_paise"`
		RazorpayPaymentID string     `json:"razorpay_payment_id"`
		PaymentMethod     string     `json:"payment_method"`
		PaidAt            *time.Time `json:"paid_at"`
		CreatedAt         time.Time  `json:"created_at"`
		RazorpayOrderID   string     `json:"razorpay_order_id"`
	}

	transactions := []Transaction{}
	for rows.Next() {
		var t Transaction
		var paidAt sql.NullTime
		if err := rows.Scan(&t.ID, &t.ConsultationType, &t.ConsultationDate, &t.ConsultationTime,
			&t.ClientName, &t.PaymentStatus, &t.AmountPaise,
			&t.RazorpayPaymentID, &t.PaymentMethod, &paidAt, &t.CreatedAt,
			&t.RazorpayOrderID); err != nil {
			utils.Error(c, http.StatusInternalServerError, "Failed to read transactions", err.Error())
			return
		}
		if paidAt.Valid {
			t.PaidAt = &paidAt.Time
		}
		transactions = append(transactions, t)
	}

	utils.SuccessWithMeta(c, http.StatusOK, "Earnings fetched", gin.H{
		"summary":      summary,
		"transactions": transactions,
	}, page.Meta(len(transactions)))
}

// GetConsultation - Get single consultation
func GetConsultation(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "not a uuid")
		return
	}
	// This route is mounted for both the client and the lawyer side, and the
	// query matched on the id alone — so any authenticated user could read any
	// consultation, including the client's private notes and the meeting link.
	userID := utils.UserID(c)

	var con struct {
		ID               string    `json:"id"`
		ConsultationType string    `json:"consultation_type"`
		ConsultationDate string    `json:"consultation_date"`
		ConsultationTime string    `json:"consultation_time"`
		Status           string    `json:"status"`
		Notes            string    `json:"notes"`
		LawyerNotes      string    `json:"lawyer_notes"`
		MeetingLink      string    `json:"meeting_link"`
		LawyerName       string    `json:"lawyer_name"`
		ClientName       string    `json:"client_name"`
		PaymentStatus    string    `json:"payment_status"`
		AmountPaise      int64     `json:"amount_paise"`
		CreatedAt        time.Time `json:"created_at"`
	}

	err := config.DB.QueryRow(`
		SELECT con.id, con.consultation_type,
			con.consultation_date::text, con.consultation_time,
			con.status, COALESCE(con.notes,''),
			COALESCE(con.lawyer_notes,''), COALESCE(con.meeting_link,''),
			COALESCE(l.name,''), COALESCE(cl.name,''),
			con.payment_status, COALESCE(con.amount_paise,0),
			con.created_at
		FROM consultations con
		LEFT JOIN users l  ON con.lawyer_id = l.id
		LEFT JOIN users cl ON con.client_id = cl.id
		WHERE con.id = $1::uuid
		  AND (con.lawyer_id = $2::uuid OR con.client_id = $2::uuid)
	`, id, userID).Scan(
		&con.ID, &con.ConsultationType,
		&con.ConsultationDate, &con.ConsultationTime,
		&con.Status, &con.Notes, &con.LawyerNotes, &con.MeetingLink,
		&con.LawyerName, &con.ClientName,
		&con.PaymentStatus, &con.AmountPaise, &con.CreatedAt,
	)

	if err != nil {
		utils.Error(c, http.StatusNotFound, "Consultation not found", err.Error())
		return
	}

	utils.Success(c, http.StatusOK, "Consultation fetched", con)
}

// UpdateConsultation - Lawyer confirms/cancels and adds meeting link
func UpdateConsultation(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "not a uuid")
		return
	}
	// utils.UserID never panics; the old `userID.(string)` assertion did,
	// taking the whole process down if the claim was ever absent.
	userID := utils.UserID(c)

	var req struct {
		Status      string `json:"status"`
		LawyerNotes string `json:"lawyer_notes"`
		MeetingLink string `json:"meeting_link"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}

	if req.Status != "" && !validConsultationStatus(req.Status) {
		utils.Error(c, http.StatusBadRequest, "Invalid status",
			"expected one of: pending, confirmed, rejected, completed, cancelled")
		return
	}

	// Authorize and update in one statement, so nothing can change between the
	// ownership check and the write.
	// $N::text on every placeholder — see UpdateProfile (auth_controller.go)
	// for why: this same CASE-with-reused-placeholder shape is what broke
	// UpdateCase in production with "inconsistent types deduced".
	// RETURNING the booking's own details so the client can be notified of
	// the lawyer's accept/reject decision below, without a second round trip.
	var clientID, consultType, consultDate, consultTime string
	err := config.DB.QueryRow(`
		UPDATE consultations SET
		  status       = CASE WHEN $1::text != '' THEN $1::text ELSE status END,
		  lawyer_notes = CASE WHEN $2::text != '' THEN $2::text ELSE lawyer_notes END,
		  meeting_link = CASE WHEN $3::text != '' THEN $3::text ELSE meeting_link END,
		  updated_at   = NOW()
		WHERE id=$4::uuid AND lawyer_id=$5::uuid
		RETURNING client_id::text, consultation_type, consultation_date::text, consultation_time
	`, req.Status, req.LawyerNotes, req.MeetingLink, id, userID).Scan(
		&clientID, &consultType, &consultDate, &consultTime)

	if err == sql.ErrNoRows {
		utils.Error(c, http.StatusNotFound, "Consultation not found", "not the assigned lawyer")
		return
	}
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to update", err.Error())
		return
	}

	// Tell the client the lawyer's decision — previously this endpoint never
	// notified them at all, so a rejected booking just silently vanished
	// from their perspective with no explanation.
	if req.Status == "confirmed" {
		utils.NotifyWithRef(clientID, "",
			"Booking accepted",
			fmt.Sprintf("Your %s consultation on %s at %s has been accepted by your lawyer.",
				consultType, consultDate, consultTime),
			"booking_accepted", id, "consultation")
	} else if req.Status == "rejected" {
		utils.NotifyWithRef(clientID, "",
			"Booking rejected",
			fmt.Sprintf("Your %s consultation request for %s at %s was rejected by the lawyer.",
				consultType, consultDate, consultTime),
			"booking_rejected", id, "consultation")
	}

	utils.Success(c, http.StatusOK, "Consultation updated", gin.H{"id": id, "status": req.Status})
}

// InitiateConsultationCall - Lawyer starts an Audio/Video call for a
// confirmed consultation. This never places the call itself (that still
// happens locally in the app — the phone's own dialer for audio, the
// lawyer-set meeting link for video); it only rings the client through the
// existing push-notification pipeline, carrying enough reference data
// (consultation id + call type) for the client app to show an incoming-call
// screen and fetch the rest of the consultation's details itself.
//
// Only the lawyer actually assigned to this confirmed booking may ring it —
// verified by the same id+lawyer_id ownership check UpdateConsultation uses,
// not by anything the client supplied.
// InitiateConsultationCall rings the *other* party on a confirmed
// Audio/Video consultation — either side may call the other (a lawyer
// calling their client, or a client calling their lawyer), since the
// in-app WebRTC call session (see CallSignalingWS) is symmetric.
func InitiateConsultationCall(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "not a uuid")
		return
	}
	userID := utils.UserID(c)

	var lawyerID, clientID, consultationType, status, paymentStatus, lawyerName, clientName string
	err := config.DB.QueryRow(`
		SELECT co.lawyer_id::text, co.client_id::text, co.consultation_type, co.status,
		       COALESCE(co.payment_status,'pending'),
		       COALESCE(l.name,'Your lawyer'), COALESCE(cl.name,'The client')
		FROM consultations co
		JOIN users l ON co.lawyer_id = l.id
		JOIN users cl ON co.client_id = cl.id
		WHERE co.id = $1::uuid
	`, id).Scan(&lawyerID, &clientID, &consultationType, &status, &paymentStatus, &lawyerName, &clientName)
	if err != nil {
		utils.Error(c, http.StatusNotFound, "Consultation not found", "")
		return
	}
	if userID != lawyerID && userID != clientID {
		utils.Error(c, http.StatusForbidden, "Not a participant on this consultation", "")
		return
	}
	if status != "confirmed" {
		utils.Error(c, http.StatusBadRequest, "Consultation is not confirmed", "call requires a confirmed booking")
		return
	}
	// UpdateConsultation lets a lawyer set status='confirmed' directly (e.g.
	// confirming a booking made before payment, or a manually-arranged one)
	// with no payment_status condition — so 'confirmed' alone never implied
	// paid. This endpoint is the only path that actually starts a call, so
	// it's the one place that has to check payment_status itself rather than
	// trusting status='confirmed', or a lawyer could confirm and immediately
	// call/be called on a booking nobody has paid for yet.
	if paymentStatus != "paid" {
		utils.Error(c, http.StatusPaymentRequired,
			"Payment for this consultation has not been completed yet",
			"call requires payment_status=paid")
		return
	}

	callType := consultationCallType(consultationType)
	if callType == "chat" {
		utils.Error(c, http.StatusBadRequest, "This consultation is chat-only",
			"audio/video calling is not available for a Chat booking")
		return
	}

	title := "📞 Incoming Audio Call"
	if callType == "video" {
		title = "🎥 Incoming Video Call"
	}

	// Ring whichever side didn't place the call.
	calleeID, callerName := clientID, lawyerName
	if userID == clientID {
		calleeID, callerName = lawyerID, clientName
	}
	body := fmt.Sprintf("%s is calling you.", callerName)

	utils.NotifyWithRef(calleeID, "", title, body, "incoming_call_"+callType, id, "consultation")

	utils.Success(c, http.StatusOK, "Call initiated", gin.H{"call_type": callType})
}

// RespondToConsultationCall - the callee accepts/declines an incoming call
// and the caller is notified back through the same existing push mechanism.
// Works for either direction (lawyer calling client, or client calling
// lawyer) — only whichever of the two is actually on this consultation may
// respond to it.
func RespondToConsultationCall(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "not a uuid")
		return
	}
	userID := utils.UserID(c)

	var req struct {
		Response string `json:"response" binding:"required"` // "accepted" | "declined"
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}
	if req.Response != "accepted" && req.Response != "declined" {
		utils.Error(c, http.StatusBadRequest, "Invalid response", "expected accepted or declined")
		return
	}

	var lawyerID, lawyerFirmID, clientID, lawyerName, clientName string
	err := config.DB.QueryRow(`
		SELECT co.lawyer_id::text, COALESCE(l.firm_id::text,''), co.client_id::text,
		       COALESCE(l.name,'The lawyer'), COALESCE(cl.name,'The client')
		FROM consultations co
		JOIN users l ON co.lawyer_id = l.id
		JOIN users cl ON co.client_id = cl.id
		WHERE co.id = $1::uuid
	`, id).Scan(&lawyerID, &lawyerFirmID, &clientID, &lawyerName, &clientName)
	if err != nil {
		utils.Error(c, http.StatusNotFound, "Consultation not found", "")
		return
	}
	if userID != lawyerID && userID != clientID {
		utils.Error(c, http.StatusForbidden, "Not a participant on this consultation", "")
		return
	}

	// Notify whichever side didn't respond — i.e. the original caller.
	callerID, callerFirmID, responderName := lawyerID, lawyerFirmID, clientName
	if userID == lawyerID {
		callerID, callerFirmID, responderName = clientID, "", lawyerName
	}

	title := "Call Declined"
	body := fmt.Sprintf("%s declined the call.", responderName)
	if req.Response == "accepted" {
		title = "Call Accepted"
		body = fmt.Sprintf("%s accepted the call.", responderName)
	}
	utils.NotifyWithRef(callerID, callerFirmID, title, body, "call_response_"+req.Response, id, "consultation")

	utils.Success(c, http.StatusOK, "Response recorded", nil)
}

// CancelConsultationCall - the caller hangs up/cancels before the callee has
// answered. Only reachable pre-answer: once both sides have joined the
// WebRTC session (see CallSignalingWS), a hangup there already reaches the
// other side directly over the socket. Before that — while the callee is
// still on the ringing IncomingCallScreen and has no socket open yet — this
// is the only channel back to them, so it rings down the same existing push
// pipeline every other call notification already uses.
func CancelConsultationCall(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "not a uuid")
		return
	}
	userID := utils.UserID(c)

	var lawyerID, lawyerFirmID, clientID, lawyerName, clientName string
	err := config.DB.QueryRow(`
		SELECT co.lawyer_id::text, COALESCE(l.firm_id::text,''), co.client_id::text,
		       COALESCE(l.name,'The lawyer'), COALESCE(cl.name,'The client')
		FROM consultations co
		JOIN users l ON co.lawyer_id = l.id
		JOIN users cl ON co.client_id = cl.id
		WHERE co.id = $1::uuid
	`, id).Scan(&lawyerID, &lawyerFirmID, &clientID, &lawyerName, &clientName)
	if err != nil {
		utils.Error(c, http.StatusNotFound, "Consultation not found", "")
		return
	}
	if userID != lawyerID && userID != clientID {
		utils.Error(c, http.StatusForbidden, "Not a participant on this consultation", "")
		return
	}

	calleeID, calleeFirmID, callerName := clientID, "", lawyerName
	if userID == clientID {
		calleeID, calleeFirmID, callerName = lawyerID, lawyerFirmID, clientName
	}

	utils.NotifyWithRef(calleeID, calleeFirmID, "Call Ended",
		fmt.Sprintf("%s ended the call.", callerName),
		"call_cancelled", id, "consultation")

	utils.Success(c, http.StatusOK, "Call cancelled", nil)
}

// SaveCallDuration records how long a call actually lasted, added to any
// duration already saved (a consultation can involve more than one call
// attempt — a dropped call redialed). This was never recorded anywhere
// before, so consultation history had nothing to show for a completed call.
func SaveCallDuration(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "not a uuid")
		return
	}
	userID := utils.UserID(c)

	var req struct {
		DurationSeconds int `json:"duration_seconds" binding:"required,min=1"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		// A call that never connected has nothing worth recording — not an
		// error, just nothing to do.
		utils.Success(c, http.StatusOK, "Nothing to record", nil)
		return
	}

	res, err := config.DB.Exec(`
		UPDATE consultations SET call_duration_seconds = call_duration_seconds + $1, updated_at=NOW()
		WHERE id=$2::uuid AND (lawyer_id=$3::uuid OR client_id=$3::uuid)
	`, req.DurationSeconds, id, userID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to save call duration", err.Error())
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		utils.Error(c, http.StatusForbidden, "Not a participant on this consultation", "")
		return
	}

	utils.Success(c, http.StatusOK, "Call duration saved", nil)
}

// CancelConsultation - Client cancels their booking
func CancelConsultation(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "not a uuid")
		return
	}
	userID := utils.UserID(c)

	// Only a booking that has not already happened can be cancelled, and the
	// Exec result is checked — it was previously discarded, so the endpoint
	// reported success even when it changed nothing.
	res, err := config.DB.Exec(`
		UPDATE consultations SET status='cancelled', updated_at=NOW()
		WHERE id=$1::uuid AND client_id=$2::uuid
		  AND status IN ('pending','confirmed')
	`, id, userID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to cancel", err.Error())
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		utils.Error(c, http.StatusNotFound, "Consultation not found", "already closed or not yours")
		return
	}

	utils.Success(c, http.StatusOK, "Consultation cancelled", nil)
}

func validConsultationStatus(s string) bool {
	switch s {
	case "pending", "confirmed", "rejected", "completed", "cancelled":
		return true
	}
	return false
}
