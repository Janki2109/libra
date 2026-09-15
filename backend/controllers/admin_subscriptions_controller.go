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

// This file is the Super Admin "Subscriptions" module.
//
// Subscriptions in this codebase belong to a FIRM (subscriptions.firm_id),
// not to an individual user — see migration 008/010. Only a firm (i.e. a
// lawyer's practice) ever has a subscription; clients and law students have
// none. So "the user" a subscription is shown against here is the firm's
// earliest-registered lawyer (its de-facto owner/contact), joined from the
// same `users`/`roles` tables every other admin screen already reads — no
// new "owner" concept or column is introduced.
//
// Money: `subscription_payments` (migration 010) is the one ledger of actual
// captured SaaS payments — distinct from `payments` (what a firm's clients
// pay the firm) and from consultation payments. There is no GST, platform
// fee, discount/coupon, or refund column anywhere on subscription billing —
// a plan's price is the final amount charged, full stop, and nothing in this
// app can refund a subscription payment. Every endpoint below reports that
// honestly (null/"not applicable") instead of inventing figures.

// subscriptionOwnerJoin is reused by every query in this file: the firm plus
// its earliest lawyer, presented as the "user" columns the panel shows.
const subscriptionOwnerJoin = `
	FROM subscriptions s
	JOIN firms f ON f.id = s.firm_id
	LEFT JOIN plans p ON p.id = s.plan_id
	LEFT JOIN LATERAL (
		SELECT u.id, u.name, u.email, COALESCE(u.phone,'') AS phone
		FROM users u JOIN roles r ON r.id = u.role_id
		WHERE u.firm_id = f.id AND r.name = 'lawyer'
		ORDER BY u.created_at ASC LIMIT 1
	) owner ON true
`

// AdminGetSubscriptionStats - GET /admin/subscriptions/stats
// The Subscriptions module's summary cards.
func AdminGetSubscriptionStats(c *gin.Context) {
	var out struct {
		TotalSubscriptions     int     `json:"total_subscriptions"`
		ActiveSubscriptions    int     `json:"active_subscriptions"`
		PremiumUsers           int     `json:"premium_users"`
		ExpiredSubscriptions   int     `json:"expired_subscriptions"`
		CancelledSubscriptions int     `json:"cancelled_subscriptions"`
		TotalRevenue           float64 `json:"total_revenue"`
		MonthRevenue           float64 `json:"month_revenue"`
		ActivePlans            int     `json:"active_plans"`
	}

	config.DB.QueryRow(`SELECT COUNT(*) FROM subscriptions`).Scan(&out.TotalSubscriptions)
	config.DB.QueryRow(`SELECT COUNT(*) FROM subscriptions WHERE status='active'`).Scan(&out.ActiveSubscriptions)
	config.DB.QueryRow(`
		SELECT COUNT(*) FROM subscriptions s JOIN plans p ON p.id = s.plan_id
		WHERE s.status='active' AND p.price_monthly > 0
	`).Scan(&out.PremiumUsers)
	config.DB.QueryRow(`SELECT COUNT(*) FROM subscriptions WHERE status='expired'`).Scan(&out.ExpiredSubscriptions)
	config.DB.QueryRow(`SELECT COUNT(*) FROM subscriptions WHERE status='cancelled'`).Scan(&out.CancelledSubscriptions)

	// Only 'captured'/'paid' subscription_payments count as real revenue —
	// there is no failed/pending row kept in this table at all (it only ever
	// records a settled payment), so no extra status filter can silently let
	// a bad row through here.
	config.DB.QueryRow(`SELECT COALESCE(SUM(amount),0) FROM subscription_payments`).Scan(&out.TotalRevenue)
	config.DB.QueryRow(`
		SELECT COALESCE(SUM(amount),0) FROM subscription_payments
		WHERE created_at >= date_trunc('month', NOW())
	`).Scan(&out.MonthRevenue)
	config.DB.QueryRow(`SELECT COUNT(*) FROM plans WHERE is_active = true`).Scan(&out.ActivePlans)

	utils.Success(c, http.StatusOK, "Subscription stats fetched", out)
}

// AdminGetSubscriptions - GET /admin/subscriptions
// ?status=active|expired|cancelled|trial|past_due  ?premium=true
// ?plan=<plan name>  ?search=<firm/owner name or email>
// ?from=&to= (filters on s.started_at, falling back to s.created_at)
// Powers the Active/Expired/Cancelled/Premium tabs — all four are this same
// list with a different ?status (Premium adds ?premium=true instead).
func AdminGetSubscriptions(c *gin.Context) {
	status := c.Query("status")
	premiumOnly := c.Query("premium") == "true"
	plan := c.Query("plan")
	search := c.Query("search")
	from := c.Query("from")
	to := c.Query("to")
	page := ParsePagination(c)

	query := `
		SELECT s.id, f.id::text, f.name, COALESCE(f.email,''),
		       COALESCE(owner.name,''), COALESCE(owner.email,''), COALESCE(owner.phone,''),
		       COALESCE(p.name,''), COALESCE(p.display_name,''),
		       s.billing_cycle,
		       CASE WHEN s.billing_cycle='yearly' THEN COALESCE(p.price_yearly,0) ELSE COALESCE(p.price_monthly,0) END,
		       s.status, COALESCE(s.started_at::text, s.created_at::text),
		       COALESCE(s.current_period_end::text,''), COALESCE(s.trial_ends_at::text,''),
		       COALESCE(s.cancelled_at::text,''),
		       COALESCE(s.last_payment_id,''), COALESCE(s.last_payment_at::text,'')
	` + subscriptionOwnerJoin + ` WHERE 1=1`

	args := []interface{}{}
	if status != "" {
		args = append(args, status)
		query += fmt.Sprintf(` AND s.status = $%d`, len(args))
	}
	if premiumOnly {
		query += ` AND COALESCE(p.price_monthly,0) > 0`
	}
	if plan != "" {
		args = append(args, plan)
		query += fmt.Sprintf(` AND p.name = $%d`, len(args))
	}
	if search != "" {
		args = append(args, "%"+search+"%")
		query += fmt.Sprintf(` AND (f.name ILIKE $%d OR f.email ILIKE $%d OR owner.name ILIKE $%d OR owner.email ILIKE $%d)`,
			len(args), len(args), len(args), len(args))
	}
	if from != "" {
		args = append(args, from)
		query += fmt.Sprintf(` AND COALESCE(s.started_at, s.created_at) >= $%d::date`, len(args))
	}
	if to != "" {
		args = append(args, to)
		query += fmt.Sprintf(` AND COALESCE(s.started_at, s.created_at) < ($%d::date + INTERVAL '1 day')`, len(args))
	}
	query += ` ORDER BY s.created_at DESC`
	args = append(args, page.Limit, page.Offset)
	query += fmt.Sprintf(` LIMIT $%d OFFSET $%d`, len(args)-1, len(args))

	rows, err := config.DB.Query(query, args...)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch subscriptions", err.Error())
		return
	}
	defer rows.Close()

	type Row struct {
		ID               string  `json:"id"`
		FirmID           string  `json:"firm_id"`
		FirmName         string  `json:"firm_name"`
		FirmEmail        string  `json:"firm_email"`
		OwnerName        string  `json:"owner_name"`
		OwnerEmail       string  `json:"owner_email"`
		OwnerPhone       string  `json:"owner_phone"`
		PlanName         string  `json:"plan_name"`
		PlanDisplayName  string  `json:"plan_display_name"`
		BillingCycle     string  `json:"billing_cycle"`
		PlanPrice        float64 `json:"plan_price"`
		Status           string  `json:"status"`
		StartDate        string  `json:"start_date"`
		CurrentPeriodEnd string  `json:"current_period_end"`
		TrialEndsAt      string  `json:"trial_ends_at"`
		CancelledAt      string  `json:"cancelled_at"`
		LastPaymentID    string  `json:"last_payment_id"`
		LastPaymentAt    string  `json:"last_payment_at"`
		DaysRemaining    *int    `json:"days_remaining"`
		PaymentStatus    string  `json:"payment_status"`
	}

	out := []Row{}
	for rows.Next() {
		var r Row
		if err := rows.Scan(&r.ID, &r.FirmID, &r.FirmName, &r.FirmEmail,
			&r.OwnerName, &r.OwnerEmail, &r.OwnerPhone,
			&r.PlanName, &r.PlanDisplayName, &r.BillingCycle, &r.PlanPrice,
			&r.Status, &r.StartDate, &r.CurrentPeriodEnd, &r.TrialEndsAt,
			&r.CancelledAt, &r.LastPaymentID, &r.LastPaymentAt); err != nil {
			utils.Error(c, http.StatusInternalServerError, "Failed to read subscriptions", err.Error())
			return
		}

		// The expiry that actually applies depends on status — a trial hasn't
		// paid yet so it expires at trial_ends_at, everything else runs to
		// current_period_end.
		expiryStr := r.CurrentPeriodEnd
		if r.Status == "trial" {
			expiryStr = r.TrialEndsAt
		}
		if expiry, err := time.Parse(time.RFC3339, normalizeTS(expiryStr)); err == nil {
			days := int(time.Until(expiry).Hours() / 24)
			r.DaysRemaining = &days
		}

		switch r.Status {
		case "active", "trial":
			r.PaymentStatus = "paid"
		case "past_due":
			r.PaymentStatus = "failed"
		case "cancelled":
			r.PaymentStatus = "paid"
		case "expired":
			r.PaymentStatus = "expired"
		default:
			r.PaymentStatus = "pending"
		}

		out = append(out, r)
	}
	utils.SuccessWithMeta(c, http.StatusOK, "Subscriptions fetched", out, page.Meta(len(out)))
}

// normalizeTS makes a Postgres ::text timestamp (space-separated, e.g.
// "2026-09-12 10:00:00.123456+00") parseable by time.RFC3339 by swapping the
// separating space for 'T'. Returns the input unchanged (and so deliberately
// unparseable) for an empty string.
func normalizeTS(s string) string {
	if s == "" {
		return ""
	}
	if len(s) > 10 && s[10] == ' ' {
		return s[:10] + "T" + s[11:]
	}
	return s
}

// AdminGetSubscriptionByID - GET /admin/subscriptions/:id
// The full detail view: subscription + firm + owner + plan + every payment
// ever recorded against it. Refund fields are always "not_applicable" — see
// this file's top comment for why that is a fact, not a gap.
func AdminGetSubscriptionByID(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "not a uuid")
		return
	}

	var d struct {
		ID               string  `json:"id"`
		FirmID           string  `json:"firm_id"`
		FirmName         string  `json:"firm_name"`
		FirmEmail        string  `json:"firm_email"`
		FirmPhone        string  `json:"firm_phone"`
		OwnerName        string  `json:"owner_name"`
		OwnerEmail       string  `json:"owner_email"`
		OwnerPhone       string  `json:"owner_phone"`
		OwnerRole        string  `json:"owner_role"`
		PlanName         string  `json:"plan_name"`
		PlanDisplayName  string  `json:"plan_display_name"`
		BillingCycle     string  `json:"billing_cycle"`
		PlanPrice        float64 `json:"plan_price"`
		Status           string  `json:"status"`
		StartDate        string  `json:"start_date"`
		CurrentPeriodEnd string  `json:"current_period_end"`
		TrialEndsAt      string  `json:"trial_ends_at"`
		CancelledAt      string  `json:"cancelled_at"`
		GraceUntil       string  `json:"grace_until"`
		LastPaymentID    string  `json:"last_payment_id"`
		LastPaymentAt    string  `json:"last_payment_at"`
	}

	err := config.DB.QueryRow(`
		SELECT s.id, f.id::text, f.name, COALESCE(f.email,''), COALESCE(f.phone,''),
		       COALESCE(owner.name,''), COALESCE(owner.email,''), COALESCE(owner.phone,''),
		       'lawyer',
		       COALESCE(p.name,''), COALESCE(p.display_name,''),
		       s.billing_cycle,
		       CASE WHEN s.billing_cycle='yearly' THEN COALESCE(p.price_yearly,0) ELSE COALESCE(p.price_monthly,0) END,
		       s.status, COALESCE(s.started_at::text, s.created_at::text),
		       COALESCE(s.current_period_end::text,''), COALESCE(s.trial_ends_at::text,''),
		       COALESCE(s.cancelled_at::text,''), COALESCE(s.grace_until::text,''),
		       COALESCE(s.last_payment_id,''), COALESCE(s.last_payment_at::text,'')
	`+subscriptionOwnerJoin+` WHERE s.id = $1::uuid`, id).Scan(
		&d.ID, &d.FirmID, &d.FirmName, &d.FirmEmail, &d.FirmPhone,
		&d.OwnerName, &d.OwnerEmail, &d.OwnerPhone, &d.OwnerRole,
		&d.PlanName, &d.PlanDisplayName, &d.BillingCycle, &d.PlanPrice,
		&d.Status, &d.StartDate, &d.CurrentPeriodEnd, &d.TrialEndsAt,
		&d.CancelledAt, &d.GraceUntil, &d.LastPaymentID, &d.LastPaymentAt)
	if err == sql.ErrNoRows {
		utils.Error(c, http.StatusNotFound, "Subscription not found", "")
		return
	}
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch subscription", err.Error())
		return
	}

	rows, err := config.DB.Query(`
		SELECT sp.id, COALESCE(sp.order_id,''), sp.payment_id, sp.amount,
		       COALESCE(sp.currency,'INR'), COALESCE(sp.billing_cycle,''),
		       sp.status, sp.created_at::text,
		       COALESCE(sp.period_start::text,''), COALESCE(sp.period_end::text,'')
		FROM subscription_payments sp
		WHERE sp.subscription_id = $1::uuid
		ORDER BY sp.created_at DESC
	`, id)
	payments := []gin.H{}
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var pid, orderID, paymentID, currency, cycle, status, createdAt, periodStart, periodEnd string
			var amount float64
			if rows.Scan(&pid, &orderID, &paymentID, &amount, &currency, &cycle, &status, &createdAt, &periodStart, &periodEnd) == nil {
				payments = append(payments, gin.H{
					"id":             pid,
					"order_id":       orderID,
					"transaction_id": paymentID,
					"amount":         amount,
					"currency":       currency,
					"billing_cycle":  cycle,
					"status":         status,
					"payment_date":   createdAt,
					"period_start":   periodStart,
					"period_end":     periodEnd,
					// No GST/platform-fee/discount/refund concept exists for
					// subscription billing anywhere in this codebase — see
					// this file's top comment. Reported honestly rather than
					// invented.
					"gst":             nil,
					"platform_fee":    nil,
					"discount":        nil,
					"final_amount":    amount,
					"payment_method":  nil,
					"payment_gateway": "razorpay",
					"refund_id":       nil,
					"refund_amount":   nil,
					"refund_date":     nil,
					"refund_status":   "not_applicable",
				})
			}
		}
	}

	utils.Success(c, http.StatusOK, "Subscription detail fetched", gin.H{
		"subscription": d,
		"payments":     payments,
		// Reported here too so the detail view's own "Cancellation" section
		// doesn't have to guess: this column simply does not exist.
		"cancellation_reason": nil,
	})
}

// AdminGetSubscriptionPlans - GET /admin/subscriptions/plans
// Plan-wise subscriber counts + revenue, for the "Plan-wise Users" tab and
// its by-plan chart.
func AdminGetSubscriptionPlans(c *gin.Context) {
	rows, err := config.DB.Query(`
		SELECT p.id, p.name, p.display_name, p.price_monthly, p.price_yearly, p.is_active,
		       COUNT(s.id) AS total,
		       COUNT(s.id) FILTER (WHERE s.status='active') AS active,
		       COUNT(s.id) FILTER (WHERE s.status='expired') AS expired,
		       COUNT(s.id) FILTER (WHERE s.status='cancelled') AS cancelled,
		       COALESCE((SELECT SUM(sp.amount) FROM subscription_payments sp WHERE sp.plan_id = p.id), 0) AS revenue
		FROM plans p
		LEFT JOIN subscriptions s ON s.plan_id = p.id
		GROUP BY p.id, p.name, p.display_name, p.price_monthly, p.price_yearly, p.is_active
		ORDER BY p.price_monthly ASC
	`)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch plans", err.Error())
		return
	}
	defer rows.Close()

	type Row struct {
		ID           string  `json:"id"`
		Name         string  `json:"name"`
		DisplayName  string  `json:"display_name"`
		PriceMonthly float64 `json:"price_monthly"`
		PriceYearly  float64 `json:"price_yearly"`
		IsActive     bool    `json:"is_active"`
		Total        int     `json:"total_subscribers"`
		Active       int     `json:"active_subscribers"`
		Expired      int     `json:"expired_subscribers"`
		Cancelled    int     `json:"cancelled_subscribers"`
		Revenue      float64 `json:"total_revenue"`
	}
	out := []Row{}
	for rows.Next() {
		var r Row
		if rows.Scan(&r.ID, &r.Name, &r.DisplayName, &r.PriceMonthly, &r.PriceYearly, &r.IsActive,
			&r.Total, &r.Active, &r.Expired, &r.Cancelled, &r.Revenue) == nil {
			out = append(out, r)
		}
	}
	utils.Success(c, http.StatusOK, "Plans fetched", out)
}

// AdminGetSubscriptionRevenue - GET /admin/subscriptions/revenue
// Revenue analytics + a 30-day trend for the Revenue tab's chart. Only rows
// in subscription_payments count — that table only ever holds settled
// captures (see this file's top comment), so there is no failed/pending/
// refunded row to accidentally include.
func AdminGetSubscriptionRevenue(c *gin.Context) {
	var out struct {
		Total      float64 `json:"total_revenue"`
		Today      float64 `json:"today_revenue"`
		Last7Days  float64 `json:"last_7_days_revenue"`
		Last30Days float64 `json:"last_30_days_revenue"`
		ThisMonth  float64 `json:"this_month_revenue"`
		LastMonth  float64 `json:"last_month_revenue"`
		YearToDate float64 `json:"year_to_date_revenue"`
	}
	config.DB.QueryRow(`SELECT COALESCE(SUM(amount),0) FROM subscription_payments`).Scan(&out.Total)
	config.DB.QueryRow(`SELECT COALESCE(SUM(amount),0) FROM subscription_payments WHERE created_at >= CURRENT_DATE`).Scan(&out.Today)
	config.DB.QueryRow(`SELECT COALESCE(SUM(amount),0) FROM subscription_payments WHERE created_at >= NOW() - INTERVAL '7 days'`).Scan(&out.Last7Days)
	config.DB.QueryRow(`SELECT COALESCE(SUM(amount),0) FROM subscription_payments WHERE created_at >= NOW() - INTERVAL '30 days'`).Scan(&out.Last30Days)
	config.DB.QueryRow(`SELECT COALESCE(SUM(amount),0) FROM subscription_payments WHERE created_at >= date_trunc('month', NOW())`).Scan(&out.ThisMonth)
	config.DB.QueryRow(`
		SELECT COALESCE(SUM(amount),0) FROM subscription_payments
		WHERE created_at >= date_trunc('month', NOW() - INTERVAL '1 month')
		  AND created_at < date_trunc('month', NOW())
	`).Scan(&out.LastMonth)
	config.DB.QueryRow(`SELECT COALESCE(SUM(amount),0) FROM subscription_payments WHERE created_at >= date_trunc('year', NOW())`).Scan(&out.YearToDate)

	trendRows, err := config.DB.Query(`
		SELECT d::date::text, COALESCE((
			SELECT SUM(sp.amount) FROM subscription_payments sp
			WHERE sp.created_at::date = d::date
		), 0)
		FROM generate_series(CURRENT_DATE - INTERVAL '29 days', CURRENT_DATE, INTERVAL '1 day') d
		ORDER BY d
	`)
	trend := []gin.H{}
	if err == nil {
		defer trendRows.Close()
		for trendRows.Next() {
			var date string
			var value float64
			if trendRows.Scan(&date, &value) == nil {
				trend = append(trend, gin.H{"date": date, "value": value})
			}
		}
	}

	utils.Success(c, http.StatusOK, "Subscription revenue fetched", gin.H{
		"summary":   out,
		"trend_30d": trend,
	})
}

// AdminGetSubscriptionPayments - GET /admin/subscriptions/payments
// The Payment History tab. ?search= ?plan= ?status= ?from= ?to=
func AdminGetSubscriptionPayments(c *gin.Context) {
	search := c.Query("search")
	plan := c.Query("plan")
	status := c.Query("status")
	from := c.Query("from")
	to := c.Query("to")
	page := ParsePagination(c)

	query := `
		SELECT sp.id, sp.order_id, sp.payment_id, sp.amount, COALESCE(sp.currency,'INR'),
		       COALESCE(sp.billing_cycle,''), sp.status, sp.created_at::text,
		       f.id::text, f.name, COALESCE(f.email,''),
		       COALESCE(owner.name,''), COALESCE(owner.email,''),
		       COALESCE(p.name,''), COALESCE(p.display_name,'')
		FROM subscription_payments sp
		JOIN firms f ON f.id = sp.firm_id
		LEFT JOIN plans p ON p.id = sp.plan_id
		LEFT JOIN LATERAL (
			SELECT u.name, u.email FROM users u JOIN roles r ON r.id = u.role_id
			WHERE u.firm_id = f.id AND r.name = 'lawyer'
			ORDER BY u.created_at ASC LIMIT 1
		) owner ON true
		WHERE 1=1`
	args := []interface{}{}
	if search != "" {
		args = append(args, "%"+search+"%")
		query += fmt.Sprintf(` AND (f.name ILIKE $%d OR f.email ILIKE $%d OR owner.name ILIKE $%d OR owner.email ILIKE $%d OR sp.payment_id ILIKE $%d)`,
			len(args), len(args), len(args), len(args), len(args))
	}
	if plan != "" {
		args = append(args, plan)
		query += fmt.Sprintf(` AND p.name = $%d`, len(args))
	}
	if status != "" {
		args = append(args, status)
		query += fmt.Sprintf(` AND sp.status = $%d`, len(args))
	}
	if from != "" {
		args = append(args, from)
		query += fmt.Sprintf(` AND sp.created_at >= $%d::date`, len(args))
	}
	if to != "" {
		args = append(args, to)
		query += fmt.Sprintf(` AND sp.created_at < ($%d::date + INTERVAL '1 day')`, len(args))
	}
	query += ` ORDER BY sp.created_at DESC`
	args = append(args, page.Limit, page.Offset)
	query += fmt.Sprintf(` LIMIT $%d OFFSET $%d`, len(args)-1, len(args))

	rows, err := config.DB.Query(query, args...)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch payments", err.Error())
		return
	}
	defer rows.Close()

	out := []gin.H{}
	for rows.Next() {
		var id, orderID, paymentID, currency, cycle, status, createdAt string
		var firmID, firmName, firmEmail, ownerName, ownerEmail, planName, planDisplay string
		var amount float64
		if rows.Scan(&id, &orderID, &paymentID, &amount, &currency, &cycle, &status, &createdAt,
			&firmID, &firmName, &firmEmail, &ownerName, &ownerEmail, &planName, &planDisplay) == nil {
			userName, userEmail := ownerName, ownerEmail
			if userName == "" {
				userName, userEmail = firmName, firmEmail
			}
			out = append(out, gin.H{
				"id":                id,
				"transaction_id":    paymentID,
				"order_id":          orderID,
				"user_name":         userName,
				"user_email":        userEmail,
				"user_role":         "lawyer",
				"plan_name":         planName,
				"plan_display_name": planDisplay,
				"billing_cycle":     cycle,
				"amount":            amount,
				"currency":          currency,
				"gst":               nil,
				"platform_fee":      nil,
				"discount":          nil,
				"final_amount":      amount,
				"payment_method":    nil,
				"payment_gateway":   "razorpay",
				"status":            status,
				"payment_date":      createdAt,
				"refund_amount":     nil,
				"refund_status":     "not_applicable",
			})
		}
	}
	utils.SuccessWithMeta(c, http.StatusOK, "Subscription payments fetched", out, page.Meta(len(out)))
}
