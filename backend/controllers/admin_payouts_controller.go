package controllers

import (
	"database/sql"
	"fmt"
	"libra/config"
	"libra/utils"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

// ─── PAYOUTS & SETTLEMENTS (Super Admin only) ──────────────────────────
//
// There is no commission/payout system anywhere else in this codebase (see
// the accounting note on AdminGetRevenue): a consultation payment is booked
// 100% as lawyer earnings the instant the client pays, with no platform
// commission or GST ever deducted from it, and nothing previously recorded
// whether the platform had actually transferred that money to the lawyer.
//
// This module reuses that existing earnings source exactly as-is (gross
// earnings = SUM(consultations.amount_paise) WHERE payment_status='paid',
// the same figure AdminGetRevenue calls "lawyer_earnings_gross") and adds
// only the one missing piece: a real settlement record (migration 027,
// lawyer_payouts/lawyer_payout_items) a Super Admin creates when they
// actually pay a lawyer. "Pending" is therefore always a paid consultation
// with no linked payout item — never a guessed number — and platform
// commission/GST read a true ₹0 throughout, because no such deduction
// exists to report.

// payoutLawyerBase is the shared FROM/JOIN for every query that aggregates
// a lawyer's consultation earnings against their settlement history.
const payoutLawyerBase = `
	FROM users u
	JOIN roles r ON u.role_id = r.id
	LEFT JOIN consultations co ON co.lawyer_id = u.id AND co.payment_status = 'paid'
	LEFT JOIN lawyer_payout_items lpi ON lpi.consultation_id = co.id
	WHERE r.name = 'lawyer'`

func payoutDateFilter(col, from, to string, args *[]interface{}) string {
	clause := ""
	if from != "" {
		*args = append(*args, from)
		clause += fmt.Sprintf(" AND %s >= $%d::date", col, len(*args))
	}
	if to != "" {
		*args = append(*args, to)
		clause += fmt.Sprintf(" AND %s < ($%d::date + INTERVAL '1 day')", col, len(*args))
	}
	return clause
}

// AdminGetPayoutStats - GET /admin/payouts/stats
func AdminGetPayoutStats(c *gin.Context) {
	var out struct {
		TotalLawyerEarnings    float64 `json:"total_lawyer_earnings"`
		TotalPlatformCommission float64 `json:"total_platform_commission"`
		TotalGST               float64 `json:"total_gst"`
		TotalNetPayout         float64 `json:"total_net_lawyer_payout"`
		PendingPayout          float64 `json:"pending_payout"`
		PaidPayout             float64 `json:"paid_payout"`
		LawyersAwaitingPayout  int     `json:"lawyers_awaiting_payout"`
		CompletedSettlements   int     `json:"completed_settlements"`
	}

	config.DB.QueryRow(`SELECT COALESCE(SUM(amount_paise),0)/100.0 FROM consultations WHERE payment_status='paid'`).
		Scan(&out.TotalLawyerEarnings)

	// No commission/GST calculation exists for consultation earnings — see
	// the file header. Read as real 0, not invented.
	out.TotalPlatformCommission = 0
	out.TotalGST = 0
	out.TotalNetPayout = out.TotalLawyerEarnings - out.TotalPlatformCommission - out.TotalGST

	config.DB.QueryRow(`
		SELECT COALESCE(SUM(co.amount_paise),0)/100.0
		FROM consultations co
		LEFT JOIN lawyer_payout_items lpi ON lpi.consultation_id = co.id
		WHERE co.payment_status = 'paid' AND lpi.id IS NULL
	`).Scan(&out.PendingPayout)

	config.DB.QueryRow(`SELECT COALESCE(SUM(net_amount),0) FROM lawyer_payouts WHERE status='paid'`).Scan(&out.PaidPayout)

	config.DB.QueryRow(`
		SELECT COUNT(DISTINCT co.lawyer_id)
		FROM consultations co
		LEFT JOIN lawyer_payout_items lpi ON lpi.consultation_id = co.id
		WHERE co.payment_status = 'paid' AND lpi.id IS NULL
	`).Scan(&out.LawyersAwaitingPayout)

	config.DB.QueryRow(`SELECT COUNT(*) FROM lawyer_payouts WHERE status='paid'`).Scan(&out.CompletedSettlements)

	utils.Success(c, http.StatusOK, "Payout stats fetched", out)
}

// AdminGetLawyerPayoutList - GET /admin/payouts/lawyers?search=&status=&page=
// Lawyer-wise earnings table. status filters on whether the lawyer
// currently has any pending (unsettled) amount: "pending" | "settled".
func AdminGetLawyerPayoutList(c *gin.Context) {
	search := c.Query("search")
	status := c.Query("status")
	page := ParsePagination(c)

	query := `
		SELECT u.id, u.name, u.email,
		       COUNT(co.id) AS total_consultations,
		       COALESCE(SUM(co.amount_paise),0)/100.0 AS gross_earnings,
		       COALESCE(SUM(co.amount_paise) FILTER (WHERE lpi.id IS NULL),0)/100.0 AS pending_amount,
		       COALESCE(SUM(co.amount_paise) FILTER (WHERE lpi.id IS NOT NULL),0)/100.0 AS paid_amount,
		       (SELECT MAX(lp.payout_date) FROM lawyer_payouts lp WHERE lp.lawyer_id = u.id AND lp.status='paid') AS last_payout_date
	` + payoutLawyerBase
	args := []interface{}{}
	if search != "" {
		args = append(args, "%"+search+"%")
		query += fmt.Sprintf(` AND (u.name ILIKE $%d OR u.email ILIKE $%d)`, len(args), len(args))
	}
	query += ` GROUP BY u.id, u.name, u.email`
	if status == "pending" {
		query += ` HAVING COALESCE(SUM(co.amount_paise) FILTER (WHERE lpi.id IS NULL),0) > 0`
	} else if status == "settled" {
		query += ` HAVING COALESCE(SUM(co.amount_paise) FILTER (WHERE lpi.id IS NULL),0) = 0 AND COUNT(co.id) > 0`
	}
	query += ` ORDER BY gross_earnings DESC`
	args = append(args, page.Limit, page.Offset)
	query += fmt.Sprintf(` LIMIT $%d OFFSET $%d`, len(args)-1, len(args))

	rows, err := config.DB.Query(query, args...)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch lawyer earnings", err.Error())
		return
	}
	defer rows.Close()

	type Row struct {
		ID                string   `json:"id"`
		Name              string   `json:"name"`
		Email             string   `json:"email"`
		TotalConsultations int     `json:"total_consultations"`
		GrossEarnings     float64  `json:"gross_earnings"`
		PlatformCommission float64 `json:"platform_commission"`
		GST               float64  `json:"gst"`
		NetPayout         float64  `json:"net_payout"`
		PendingAmount     float64  `json:"pending_amount"`
		PaidAmount        float64  `json:"paid_amount"`
		LastPayoutDate    *string  `json:"last_payout_date"`
		PayoutStatus      string   `json:"payout_status"`
	}

	out := []Row{}
	for rows.Next() {
		var r Row
		var lastPayout sql.NullTime
		if err := rows.Scan(&r.ID, &r.Name, &r.Email, &r.TotalConsultations,
			&r.GrossEarnings, &r.PendingAmount, &r.PaidAmount, &lastPayout); err != nil {
			continue
		}
		r.NetPayout = r.GrossEarnings // commission=gst=0, see header note
		if lastPayout.Valid {
			s := lastPayout.Time.Format(time.RFC3339)
			r.LastPayoutDate = &s
		}
		if r.PendingAmount > 0 {
			r.PayoutStatus = "pending"
		} else if r.TotalConsultations > 0 {
			r.PayoutStatus = "settled"
		} else {
			r.PayoutStatus = "no_earnings"
		}
		out = append(out, r)
	}
	utils.SuccessWithMeta(c, http.StatusOK, "Lawyer earnings fetched", out, page.Meta(len(out)))
}

// AdminGetLawyerPayoutDetail - GET /admin/payouts/lawyers/:id
func AdminGetLawyerPayoutDetail(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "not a uuid")
		return
	}

	var lawyer struct {
		ID                 string `json:"id"`
		Name               string `json:"name"`
		Email              string `json:"email"`
		Phone              string `json:"phone"`
		VerificationStatus string `json:"verification_status"`
	}
	err := config.DB.QueryRow(`
		SELECT u.id, u.name, u.email, COALESCE(u.phone,''), COALESCE(u.verification_status,'')
		FROM users u JOIN roles r ON u.role_id = r.id
		WHERE u.id = $1 AND r.name = 'lawyer'
	`, id).Scan(&lawyer.ID, &lawyer.Name, &lawyer.Email, &lawyer.Phone, &lawyer.VerificationStatus)
	if err != nil {
		utils.Error(c, http.StatusNotFound, "Lawyer not found", err.Error())
		return
	}

	var summary struct {
		TotalConsultations int     `json:"total_consultations"`
		GrossEarnings      float64 `json:"gross_earnings"`
		PlatformCommission float64 `json:"platform_commission"`
		GST                float64 `json:"gst"`
		NetEarnings        float64 `json:"net_earnings"`
		TotalPaid          float64 `json:"total_paid"`
		TotalPending       float64 `json:"total_pending"`
	}
	config.DB.QueryRow(`
		SELECT COUNT(co.id),
		       COALESCE(SUM(co.amount_paise),0)/100.0,
		       COALESCE(SUM(co.amount_paise) FILTER (WHERE lpi.id IS NOT NULL),0)/100.0,
		       COALESCE(SUM(co.amount_paise) FILTER (WHERE lpi.id IS NULL),0)/100.0
		FROM consultations co
		LEFT JOIN lawyer_payout_items lpi ON lpi.consultation_id = co.id
		WHERE co.lawyer_id = $1 AND co.payment_status = 'paid'
	`, id).Scan(&summary.TotalConsultations, &summary.GrossEarnings, &summary.TotalPaid, &summary.TotalPending)
	summary.NetEarnings = summary.GrossEarnings

	page := ParsePagination(c)
	rows, err := config.DB.Query(`
		SELECT co.id, co.consultation_type, co.consultation_date::text, co.consultation_time,
		       COALESCE(cl.name,''), COALESCE(co.amount_paise,0), co.call_duration_seconds,
		       co.paid_at, lpi.payout_id, lp.payout_date, lp.status
		FROM consultations co
		LEFT JOIN users cl ON co.client_id = cl.id
		LEFT JOIN lawyer_payout_items lpi ON lpi.consultation_id = co.id
		LEFT JOIN lawyer_payouts lp ON lp.id = lpi.payout_id
		WHERE co.lawyer_id = $1 AND co.payment_status = 'paid'
		ORDER BY co.paid_at DESC NULLS LAST
		LIMIT $2 OFFSET $3
	`, id, page.Limit, page.Offset)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch transactions", err.Error())
		return
	}
	defer rows.Close()

	type Txn struct {
		ID                 string   `json:"id"`
		ConsultationID     string   `json:"consultation_id"`
		ClientName         string   `json:"client_name"`
		ServiceType        string   `json:"service_type"`
		Date               string   `json:"date"`
		Time               string   `json:"time"`
		DurationSeconds    int      `json:"duration_seconds"`
		GrossAmount        float64  `json:"gross_amount"`
		PlatformCommission float64  `json:"platform_commission"`
		GST                float64  `json:"gst"`
		LawyerEarning      float64  `json:"lawyer_earning"`
		PayoutStatus       string   `json:"payout_status"`
		PayoutDate         *string  `json:"payout_date"`
	}
	txns := []Txn{}
	for rows.Next() {
		var t Txn
		var amountPaise int64
		var paidAt sql.NullTime
		var payoutID sql.NullString
		var payoutDate sql.NullTime
		var payoutStatus sql.NullString
		if err := rows.Scan(&t.ID, &t.ServiceType, &t.Date, &t.Time, &t.ClientName,
			&amountPaise, &t.DurationSeconds, &paidAt, &payoutID, &payoutDate, &payoutStatus); err != nil {
			continue
		}
		t.ConsultationID = t.ID
		t.GrossAmount = float64(amountPaise) / 100
		t.LawyerEarning = t.GrossAmount
		if payoutID.Valid {
			t.PayoutStatus = payoutStatus.String
			if payoutDate.Valid {
				s := payoutDate.Time.Format(time.RFC3339)
				t.PayoutDate = &s
			}
		} else {
			t.PayoutStatus = "pending"
		}
		txns = append(txns, t)
	}

	utils.Success(c, http.StatusOK, "Lawyer payout detail fetched", gin.H{
		"lawyer":       lawyer,
		"summary":      summary,
		"transactions": txns,
		"meta":         page.Meta(len(txns)),
	})
}

// AdminGetPendingPayouts - GET /admin/payouts/pending?search=
// Grouped by lawyer — every lawyer with at least one paid, unsettled
// consultation.
func AdminGetPendingPayouts(c *gin.Context) {
	search := c.Query("search")
	query := `
		SELECT u.id, u.name, u.email,
		       COUNT(co.id) AS txn_count,
		       COALESCE(SUM(co.amount_paise),0)/100.0 AS pending_amount,
		       MIN(co.paid_at) AS oldest_pending
		FROM users u
		JOIN roles r ON u.role_id = r.id
		JOIN consultations co ON co.lawyer_id = u.id AND co.payment_status = 'paid'
		LEFT JOIN lawyer_payout_items lpi ON lpi.consultation_id = co.id
		WHERE r.name = 'lawyer' AND lpi.id IS NULL`
	args := []interface{}{}
	if search != "" {
		args = append(args, "%"+search+"%")
		query += fmt.Sprintf(` AND (u.name ILIKE $%d OR u.email ILIKE $%d)`, len(args), len(args))
	}
	query += ` GROUP BY u.id, u.name, u.email ORDER BY pending_amount DESC`

	rows, err := config.DB.Query(query, args...)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch pending payouts", err.Error())
		return
	}
	defer rows.Close()

	type Row struct {
		LawyerID       string  `json:"lawyer_id"`
		LawyerName     string  `json:"lawyer_name"`
		LawyerEmail    string  `json:"lawyer_email"`
		TransactionCount int   `json:"transaction_count"`
		PendingAmount  float64 `json:"pending_amount"`
		OldestPending  *string `json:"oldest_pending_transaction"`
		Status         string  `json:"status"`
	}
	out := []Row{}
	for rows.Next() {
		var r Row
		var oldest sql.NullTime
		if err := rows.Scan(&r.LawyerID, &r.LawyerName, &r.LawyerEmail, &r.TransactionCount, &r.PendingAmount, &oldest); err != nil {
			continue
		}
		if oldest.Valid {
			s := oldest.Time.Format(time.RFC3339)
			r.OldestPending = &s
		}
		r.Status = "pending"
		out = append(out, r)
	}
	utils.Success(c, http.StatusOK, "Pending payouts fetched", out)
}

// AdminGetPaidPayouts - GET /admin/payouts/paid?search=&from=&to=
// Only actual completed settlements (lawyer_payouts.status='paid').
func AdminGetPaidPayouts(c *gin.Context) {
	search := c.Query("search")
	from, to := c.Query("from"), c.Query("to")
	page := ParsePagination(c)

	query := `
		SELECT lp.id, u.name, u.email, lp.net_amount, lp.transaction_count,
		       lp.payout_date, lp.payment_method, lp.reference
		FROM lawyer_payouts lp
		JOIN users u ON u.id = lp.lawyer_id
		WHERE lp.status = 'paid'`
	args := []interface{}{}
	if search != "" {
		args = append(args, "%"+search+"%")
		query += fmt.Sprintf(` AND (u.name ILIKE $%d OR u.email ILIKE $%d OR lp.reference ILIKE $%d OR lp.id::text ILIKE $%d)`,
			len(args), len(args), len(args), len(args))
	}
	query += payoutDateFilter("lp.payout_date", from, to, &args)
	query += ` ORDER BY lp.payout_date DESC`
	args = append(args, page.Limit, page.Offset)
	query += fmt.Sprintf(` LIMIT $%d OFFSET $%d`, len(args)-1, len(args))

	rows, err := config.DB.Query(query, args...)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch paid payouts", err.Error())
		return
	}
	defer rows.Close()

	type Row struct {
		SettlementID     string  `json:"settlement_id"`
		LawyerName       string  `json:"lawyer_name"`
		LawyerEmail      string  `json:"lawyer_email"`
		PayoutAmount     float64 `json:"payout_amount"`
		TransactionCount int     `json:"transaction_count"`
		PayoutDate       *string `json:"payout_date"`
		PaymentMethod    string  `json:"payment_method"`
		Reference        string  `json:"reference"`
		Status           string  `json:"status"`
	}
	out := []Row{}
	for rows.Next() {
		var r Row
		var payoutDate sql.NullTime
		var method, ref sql.NullString
		if err := rows.Scan(&r.SettlementID, &r.LawyerName, &r.LawyerEmail, &r.PayoutAmount,
			&r.TransactionCount, &payoutDate, &method, &ref); err != nil {
			continue
		}
		if payoutDate.Valid {
			s := payoutDate.Time.Format(time.RFC3339)
			r.PayoutDate = &s
		}
		if method.Valid && method.String != "" {
			r.PaymentMethod = method.String
		} else {
			r.PaymentMethod = "N/A"
		}
		if ref.Valid && ref.String != "" {
			r.Reference = ref.String
		} else {
			r.Reference = "N/A"
		}
		r.Status = "paid"
		out = append(out, r)
	}
	utils.SuccessWithMeta(c, http.StatusOK, "Paid payouts fetched", out, page.Meta(len(out)))
}

// AdminGetSettlements - GET /admin/payouts/settlements?lawyer=&status=&search=&from=&to=&page=
func AdminGetSettlements(c *gin.Context) {
	lawyer := c.Query("lawyer")
	status := c.Query("status")
	search := c.Query("search")
	from, to := c.Query("from"), c.Query("to")
	page := ParsePagination(c)

	query := `
		SELECT lp.id, u.name, u.id, lp.net_amount, lp.gross_amount, lp.platform_commission,
		       lp.gst_amount, lp.transaction_count, lp.created_at, lp.payout_date,
		       lp.payment_method, lp.reference, lp.status
		FROM lawyer_payouts lp
		JOIN users u ON u.id = lp.lawyer_id
		WHERE 1=1`
	args := []interface{}{}
	if lawyer != "" && isUUID(lawyer) {
		args = append(args, lawyer)
		query += fmt.Sprintf(` AND lp.lawyer_id = $%d`, len(args))
	}
	if status != "" {
		args = append(args, status)
		query += fmt.Sprintf(` AND lp.status = $%d`, len(args))
	}
	if search != "" {
		args = append(args, "%"+search+"%")
		query += fmt.Sprintf(` AND (u.name ILIKE $%d OR u.email ILIKE $%d OR lp.reference ILIKE $%d OR lp.id::text ILIKE $%d)`,
			len(args), len(args), len(args), len(args))
	}
	query += payoutDateFilter("lp.created_at", from, to, &args)
	query += ` ORDER BY lp.created_at DESC`
	args = append(args, page.Limit, page.Offset)
	query += fmt.Sprintf(` LIMIT $%d OFFSET $%d`, len(args)-1, len(args))

	rows, err := config.DB.Query(query, args...)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch settlements", err.Error())
		return
	}
	defer rows.Close()

	type Row struct {
		SettlementID       string  `json:"settlement_id"`
		LawyerName         string  `json:"lawyer_name"`
		LawyerID           string  `json:"lawyer_id"`
		NetPayout          float64 `json:"net_payout"`
		GrossEarnings      float64 `json:"gross_earnings"`
		PlatformCommission float64 `json:"platform_commission"`
		GST                float64 `json:"gst"`
		TransactionCount   int     `json:"transaction_count"`
		SettlementDate     string  `json:"settlement_date"`
		PayoutDate         *string `json:"payout_date"`
		PaymentMethod      string  `json:"payment_method"`
		Reference          string  `json:"reference"`
		Status             string  `json:"status"`
	}
	out := []Row{}
	for rows.Next() {
		var r Row
		var createdAt time.Time
		var payoutDate sql.NullTime
		var method, ref sql.NullString
		if err := rows.Scan(&r.SettlementID, &r.LawyerName, &r.LawyerID, &r.NetPayout, &r.GrossEarnings,
			&r.PlatformCommission, &r.GST, &r.TransactionCount, &createdAt, &payoutDate,
			&method, &ref, &r.Status); err != nil {
			continue
		}
		r.SettlementDate = createdAt.Format(time.RFC3339)
		if payoutDate.Valid {
			s := payoutDate.Time.Format(time.RFC3339)
			r.PayoutDate = &s
		}
		if method.Valid && method.String != "" {
			r.PaymentMethod = method.String
		} else {
			r.PaymentMethod = "N/A"
		}
		if ref.Valid && ref.String != "" {
			r.Reference = ref.String
		} else {
			r.Reference = "N/A"
		}
		out = append(out, r)
	}
	utils.SuccessWithMeta(c, http.StatusOK, "Settlements fetched", out, page.Meta(len(out)))
}

// AdminGetSettlementDetail - GET /admin/payouts/settlements/:id
func AdminGetSettlementDetail(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "not a uuid")
		return
	}

	var s struct {
		SettlementID       string  `json:"settlement_id"`
		LawyerID           string  `json:"lawyer_id"`
		LawyerName         string  `json:"lawyer_name"`
		LawyerEmail        string  `json:"lawyer_email"`
		GrossEarnings      float64 `json:"gross_earnings"`
		PlatformCommission float64 `json:"platform_commission"`
		GST                float64 `json:"gst"`
		NetPayout          float64 `json:"net_payout"`
		TransactionCount   int     `json:"transaction_count"`
		SettlementDate     string  `json:"settlement_date"`
		PayoutDate         *string `json:"payout_date"`
		PaymentMethod      string  `json:"payment_method"`
		Reference          string  `json:"reference"`
		Status             string  `json:"status"`
		Notes              string  `json:"notes"`
	}
	var createdAt time.Time
	var payoutDate sql.NullTime
	var method, ref, notes sql.NullString
	err := config.DB.QueryRow(`
		SELECT lp.id, lp.lawyer_id, u.name, u.email, lp.gross_amount, lp.platform_commission,
		       lp.gst_amount, lp.net_amount, lp.transaction_count, lp.created_at, lp.payout_date,
		       lp.payment_method, lp.reference, lp.status, lp.notes
		FROM lawyer_payouts lp JOIN users u ON u.id = lp.lawyer_id
		WHERE lp.id = $1
	`, id).Scan(&s.SettlementID, &s.LawyerID, &s.LawyerName, &s.LawyerEmail, &s.GrossEarnings,
		&s.PlatformCommission, &s.GST, &s.NetPayout, &s.TransactionCount, &createdAt, &payoutDate,
		&method, &ref, &s.Status, &notes)
	if err != nil {
		utils.Error(c, http.StatusNotFound, "Settlement not found", err.Error())
		return
	}
	s.SettlementDate = createdAt.Format(time.RFC3339)
	if payoutDate.Valid {
		str := payoutDate.Time.Format(time.RFC3339)
		s.PayoutDate = &str
	}
	if method.Valid && method.String != "" {
		s.PaymentMethod = method.String
	} else {
		s.PaymentMethod = "N/A"
	}
	if ref.Valid && ref.String != "" {
		s.Reference = ref.String
	} else {
		s.Reference = "N/A"
	}
	s.Notes = notes.String

	rows, err := config.DB.Query(`
		SELECT co.id, co.consultation_type, co.consultation_date::text, COALESCE(cl.name,''),
		       lpi.amount, co.paid_at, co.razorpay_payment_id
		FROM lawyer_payout_items lpi
		JOIN consultations co ON co.id = lpi.consultation_id
		LEFT JOIN users cl ON co.client_id = cl.id
		WHERE lpi.payout_id = $1
		ORDER BY co.paid_at
	`, id)
	items := []gin.H{}
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var consultID, serviceType, date, clientName, paymentRef string
			var amount float64
			var paidAt sql.NullTime
			if err := rows.Scan(&consultID, &serviceType, &date, &clientName, &amount, &paidAt, &paymentRef); err != nil {
				continue
			}
			items = append(items, gin.H{
				"consultation_id": consultID,
				"service_type":    serviceType,
				"date":            date,
				"client_name":     clientName,
				"amount":          amount,
				"payment_reference": paymentRef,
			})
		}
	}

	utils.Success(c, http.StatusOK, "Settlement detail fetched", gin.H{
		"settlement":   s,
		"transactions": items,
	})
}

// AdminCreateSettlement - POST /admin/payouts/settlements
// Records that a Super Admin has actually paid a lawyer their currently
// pending (unsettled) amount. This is the only write path in the whole
// module — it never edits a consultation or payment record, only links the
// already-paid consultations to a new settlement row so they stop counting
// as pending.
func AdminCreateSettlement(c *gin.Context) {
	var req struct {
		LawyerID      string `json:"lawyer_id" binding:"required"`
		PaymentMethod string `json:"payment_method"`
		Reference     string `json:"reference"`
		Notes         string `json:"notes"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || !isUUID(req.LawyerID) {
		utils.Error(c, http.StatusBadRequest, "Invalid request", "lawyer_id is required and must be a uuid")
		return
	}

	tx, err := config.DB.Begin()
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to start settlement", err.Error())
		return
	}
	defer tx.Rollback()

	rows, err := tx.Query(`
		SELECT co.id, co.amount_paise
		FROM consultations co
		LEFT JOIN lawyer_payout_items lpi ON lpi.consultation_id = co.id
		WHERE co.lawyer_id = $1 AND co.payment_status = 'paid' AND lpi.id IS NULL
		FOR UPDATE OF co
	`, req.LawyerID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch pending transactions", err.Error())
		return
	}
	type pending struct {
		id          string
		amountPaise int64
	}
	var items []pending
	var totalPaise int64
	for rows.Next() {
		var p pending
		if err := rows.Scan(&p.id, &p.amountPaise); err != nil {
			rows.Close()
			utils.Error(c, http.StatusInternalServerError, "Failed to read pending transactions", err.Error())
			return
		}
		items = append(items, p)
		totalPaise += p.amountPaise
	}
	rows.Close()

	if len(items) == 0 {
		utils.Error(c, http.StatusBadRequest, "Nothing to settle", "this lawyer has no pending paid consultations")
		return
	}

	grossAmount := float64(totalPaise) / 100
	adminID := utils.UserID(c)
	var payoutID string
	err = tx.QueryRow(`
		INSERT INTO lawyer_payouts
			(lawyer_id, gross_amount, platform_commission, gst_amount, net_amount,
			 transaction_count, status, payout_date, payment_method, reference, notes, created_by)
		VALUES ($1, $2, 0, 0, $2, $3, 'paid', NOW(), NULLIF($4,''), NULLIF($5,''), NULLIF($6,''), $7)
		RETURNING id
	`, req.LawyerID, grossAmount, len(items), req.PaymentMethod, req.Reference, req.Notes, adminID).Scan(&payoutID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to create settlement", err.Error())
		return
	}

	for _, it := range items {
		if _, err := tx.Exec(`
			INSERT INTO lawyer_payout_items (payout_id, consultation_id, amount) VALUES ($1, $2, $3)
		`, payoutID, it.id, float64(it.amountPaise)/100); err != nil {
			utils.Error(c, http.StatusInternalServerError, "Failed to record settlement item", err.Error())
			return
		}
	}

	if err := tx.Commit(); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to commit settlement", err.Error())
		return
	}

	utils.LogAudit(c, utils.AuditEntry{
		Action:      "PAYOUT_MARKED_PAID",
		Module:      "payouts",
		TargetType:  "settlement",
		TargetID:    payoutID,
		Description: "Payout settled for lawyer",
		Before:      map[string]interface{}{"status": "pending"},
		After: map[string]interface{}{
			"status": "paid", "net_amount": grossAmount, "transaction_count": len(items),
			"payment_method": req.PaymentMethod, "reference": req.Reference,
		},
	})

	utils.Success(c, http.StatusCreated, "Settlement created", gin.H{
		"settlement_id":     payoutID,
		"net_payout":        grossAmount,
		"transaction_count": len(items),
	})
}

// AdminGetPayoutCommission - GET /admin/payouts/commission?from=&to=
// Platform commission does not exist as a concept for consultation earnings
// (see file header) — every figure here is a real, honest 0 rather than an
// invented percentage, using the same commission calculation (none) already
// used everywhere else in the app.
func AdminGetPayoutCommission(c *gin.Context) {
	utils.Success(c, http.StatusOK, "Commission fetched", gin.H{
		"total_platform_commission": 0,
		"by_lawyer":                 []gin.H{},
		"by_service_type":           []gin.H{},
		"daily":                     0,
		"weekly":                    0,
		"monthly":                   0,
		"yearly":                    0,
		"trend_30d":                 dailySeries(`SELECT NULL::date, 0 WHERE false`, 30),
		"note":                      "No platform commission is deducted from consultation earnings in this application.",
	})
}

// AdminGetPayoutGST - GET /admin/payouts/gst?from=&to=
// Same as commission: no GST is applied to consultation earnings anywhere
// in the app, so every figure here is a genuine 0.
func AdminGetPayoutGST(c *gin.Context) {
	utils.Success(c, http.StatusOK, "GST fetched", gin.H{
		"total_gst": 0,
		"daily":     0,
		"weekly":    0,
		"monthly":   0,
		"yearly":    0,
		"trend_30d": dailySeries(`SELECT NULL::date, 0 WHERE false`, 30),
		"note":      "No GST is applied to lawyer consultation earnings in this application.",
	})
}

// AdminGetPayoutTrends - GET /admin/payouts/trends?days=&to=
func AdminGetPayoutTrends(c *gin.Context) {
	days := 30
	if d := c.Query("days"); d != "" {
		fmt.Sscanf(d, "%d", &days)
	}
	if days <= 0 || days > 180 {
		days = 30
	}
	to := c.Query("to")

	utils.Success(c, http.StatusOK, "Payout trends fetched", gin.H{
		"lawyer_earnings": dailySeriesEnding(`SELECT paid_at::date, COALESCE(SUM(amount_paise),0)/100.0 FROM consultations WHERE payment_status='paid' AND paid_at IS NOT NULL`, days, to),
		"platform_commission": dailySeriesEnding(`SELECT NULL::date, 0 WHERE false`, days, to),
		"gst":                 dailySeriesEnding(`SELECT NULL::date, 0 WHERE false`, days, to),
		"net_lawyer_payouts":  dailySeriesEnding(`SELECT paid_at::date, COALESCE(SUM(amount_paise),0)/100.0 FROM consultations WHERE payment_status='paid' AND paid_at IS NOT NULL`, days, to),
		"paid_payouts":        dailySeriesEnding(`SELECT payout_date::date, COALESCE(SUM(net_amount),0) FROM lawyer_payouts WHERE status='paid' AND payout_date IS NOT NULL`, days, to),
	})
}

// AdminGetPayoutTransactions - GET /admin/payouts/transactions?...
// Flat, filterable list of every consultation earning transaction, used for
// CSV/PDF export and the "click any payout" detail view.
func AdminGetPayoutTransactions(c *gin.Context) {
	search := c.Query("search")
	lawyer := c.Query("lawyer")
	payoutStatus := c.Query("payout_status")
	serviceType := c.Query("service_type")
	from, to := c.Query("from"), c.Query("to")
	page := ParsePagination(c)

	query := `
		SELECT co.id, u.id, u.name, u.email, COALESCE(cl.name,''), co.consultation_type,
		       co.consultation_date::text, COALESCE(co.amount_paise,0), co.paid_at,
		       lpi.payout_id, lp.payout_date, lp.reference
		FROM consultations co
		JOIN users u ON u.id = co.lawyer_id
		LEFT JOIN users cl ON cl.id = co.client_id
		LEFT JOIN lawyer_payout_items lpi ON lpi.consultation_id = co.id
		LEFT JOIN lawyer_payouts lp ON lp.id = lpi.payout_id
		WHERE co.payment_status = 'paid'`
	args := []interface{}{}
	if search != "" {
		args = append(args, "%"+search+"%")
		query += fmt.Sprintf(` AND (u.name ILIKE $%d OR u.email ILIKE $%d OR co.id::text ILIKE $%d OR lp.id::text ILIKE $%d OR lp.reference ILIKE $%d)`,
			len(args), len(args), len(args), len(args), len(args))
	}
	if lawyer != "" && isUUID(lawyer) {
		args = append(args, lawyer)
		query += fmt.Sprintf(` AND co.lawyer_id = $%d`, len(args))
	}
	if serviceType != "" {
		args = append(args, "%"+serviceType+"%")
		query += fmt.Sprintf(` AND co.consultation_type ILIKE $%d`, len(args))
	}
	if payoutStatus == "pending" {
		query += ` AND lpi.id IS NULL`
	} else if payoutStatus == "paid" {
		query += ` AND lpi.id IS NOT NULL`
	}
	query += payoutDateFilter("co.paid_at", from, to, &args)
	query += ` ORDER BY co.paid_at DESC NULLS LAST`
	args = append(args, page.Limit, page.Offset)
	query += fmt.Sprintf(` LIMIT $%d OFFSET $%d`, len(args)-1, len(args))

	rows, err := config.DB.Query(query, args...)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch transactions", err.Error())
		return
	}
	defer rows.Close()

	type Row struct {
		TransactionID      string  `json:"transaction_id"`
		LawyerID           string  `json:"lawyer_id"`
		LawyerName         string  `json:"lawyer_name"`
		LawyerEmail        string  `json:"lawyer_email"`
		ClientName         string  `json:"client_name"`
		ServiceType        string  `json:"service_type"`
		Date               string  `json:"date"`
		GrossAmount        float64 `json:"gross_amount"`
		PlatformCommission float64 `json:"platform_commission"`
		GST                float64 `json:"gst"`
		LawyerEarning      float64 `json:"lawyer_earning"`
		PayoutStatus       string  `json:"payout_status"`
		SettlementID       string  `json:"settlement_id"`
		PayoutDate         *string `json:"payout_date"`
		PaymentReference   string  `json:"payment_reference"`
	}
	out := []Row{}
	for rows.Next() {
		var r Row
		var amountPaise int64
		var paidAt sql.NullTime
		var settlementID, ref sql.NullString
		var payoutDate sql.NullTime
		if err := rows.Scan(&r.TransactionID, &r.LawyerID, &r.LawyerName, &r.LawyerEmail, &r.ClientName,
			&r.ServiceType, &r.Date, &amountPaise, &paidAt, &settlementID, &payoutDate, &ref); err != nil {
			continue
		}
		r.GrossAmount = float64(amountPaise) / 100
		r.LawyerEarning = r.GrossAmount
		if settlementID.Valid {
			r.PayoutStatus = "paid"
			r.SettlementID = settlementID.String
			if payoutDate.Valid {
				s := payoutDate.Time.Format(time.RFC3339)
				r.PayoutDate = &s
			}
		} else {
			r.PayoutStatus = "pending"
			r.SettlementID = "N/A"
		}
		if ref.Valid && ref.String != "" {
			r.PaymentReference = ref.String
		} else {
			r.PaymentReference = "N/A"
		}
		out = append(out, r)
	}
	utils.SuccessWithMeta(c, http.StatusOK, "Payout transactions fetched", out, page.Meta(len(out)))
}
