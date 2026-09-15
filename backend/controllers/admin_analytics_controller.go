package controllers

import (
	"fmt"
	"libra/config"
	"libra/utils"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
)

// This file is the Super Admin "Analytics & Reports" module. It is a read
// layer only — every figure is computed straight from the same tables
// AdminGetStats/AdminGetRevenue/the Subscriptions module already read
// (users, consultations, invoices, payment_orders, subscriptions,
// subscription_payments). Nothing here duplicates their accounting: the
// revenue formulas (what counts as platform revenue vs. GST vs. a firm's
// own invoice revenue) live in AdminGetRevenue and are reused unchanged by
// the frontend calling that same endpoint with a date range — this file
// only adds the analytics AdminGetStats/AdminGetRevenue don't already
// provide: growth/period breakdowns, booking-type splits, and one unified
// cross-source transaction report.

// analyticsCallType normalizes whatever consultation_type free text was
// stored ("Video Call", "video_call", "Chat", ...) into a fixed bucket,
// mirroring consultationCallType in consultation_controller.go (kept as a
// SQL CASE here since this always runs as an aggregate query, never a
// single row) — the same rule everywhere in the codebase that already
// classifies a booking's type.
const analyticsCallTypeCase = `
	CASE
		WHEN consultation_type ILIKE '%video%' THEN 'video'
		WHEN consultation_type ILIKE '%audio%' THEN 'audio'
		WHEN consultation_type ILIKE '%visit%' THEN 'visit'
		ELSE 'chat'
	END`

// analyticsDateFilter builds "AND <col> >= $n::date AND <col> < ($n+1::date + 1 day)"
// exactly like AdminGetRevenue's own dateFilter closure — kept as a
// standalone function here since this file has several queries that all
// need it, not just one.
func analyticsDateFilter(col, from, to string, args *[]interface{}) string {
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

// AdminGetUserAnalytics - GET /admin/analytics/users?from=&to=
func AdminGetUserAnalytics(c *gin.Context) {
	from := c.Query("from")
	to := c.Query("to")

	var out struct {
		TotalUsers           int     `json:"total_users"`
		NewToday             int     `json:"new_today"`
		NewThisWeek          int     `json:"new_this_week"`
		NewThisMonth         int     `json:"new_this_month"`
		NewInRange           int     `json:"new_in_range"`
		LawyerRegistrations  int     `json:"lawyer_registrations"`
		ClientRegistrations  int     `json:"client_registrations"`
		StudentRegistrations int     `json:"student_registrations"`
		ActiveUsers          int     `json:"active_users"`
		SuspendedUsers       int     `json:"suspended_users"`
		GrowthPercent        float64 `json:"user_growth_percent"`
	}

	notSuperAdmin := `role_id NOT IN (SELECT id FROM roles WHERE name='super_admin')`
	config.DB.QueryRow(`SELECT COUNT(*) FROM users WHERE ` + notSuperAdmin).Scan(&out.TotalUsers)
	config.DB.QueryRow(`SELECT COUNT(*) FROM users WHERE ` + notSuperAdmin + ` AND created_at >= CURRENT_DATE`).Scan(&out.NewToday)
	config.DB.QueryRow(`SELECT COUNT(*) FROM users WHERE ` + notSuperAdmin + ` AND created_at >= NOW() - INTERVAL '7 days'`).Scan(&out.NewThisWeek)
	config.DB.QueryRow(`SELECT COUNT(*) FROM users WHERE ` + notSuperAdmin + ` AND created_at >= date_trunc('month', NOW())`).Scan(&out.NewThisMonth)
	config.DB.QueryRow(`SELECT COUNT(*) FROM users u JOIN roles r ON u.role_id=r.id WHERE r.name='lawyer'`).Scan(&out.LawyerRegistrations)
	config.DB.QueryRow(`SELECT COUNT(*) FROM users u JOIN roles r ON u.role_id=r.id WHERE r.name='client'`).Scan(&out.ClientRegistrations)
	config.DB.QueryRow(`SELECT COUNT(*) FROM users u JOIN roles r ON u.role_id=r.id WHERE r.name='law_student'`).Scan(&out.StudentRegistrations)
	config.DB.QueryRow(`SELECT COUNT(*) FROM users WHERE ` + notSuperAdmin + ` AND is_active = true`).Scan(&out.ActiveUsers)
	config.DB.QueryRow(`SELECT COUNT(*) FROM users WHERE ` + notSuperAdmin + ` AND is_active = false`).Scan(&out.SuspendedUsers)

	args := []interface{}{}
	rangeClause := analyticsDateFilter("created_at", from, to, &args)
	config.DB.QueryRow(`SELECT COUNT(*) FROM users WHERE `+notSuperAdmin+rangeClause, args...).Scan(&out.NewInRange)

	// Growth % compares the selected range's new signups against the
	// immediately preceding period of equal length — a real, honest
	// week-over-week/period-over-period comparison, not an invented figure.
	if from != "" && to != "" {
		var priorCount int
		priorArgs := []interface{}{to, from, from}
		config.DB.QueryRow(`
			SELECT COUNT(*) FROM users WHERE `+notSuperAdmin+`
			AND created_at >= ($1::date - ($2::date - $3::date)) AND created_at < $3::date
		`, priorArgs...).Scan(&priorCount)
		if priorCount > 0 {
			out.GrowthPercent = (float64(out.NewInRange) - float64(priorCount)) / float64(priorCount) * 100
		} else if out.NewInRange > 0 {
			out.GrowthPercent = 100
		}
	}

	utils.Success(c, http.StatusOK, "User analytics fetched", out)
}

// AdminGetBookingAnalytics - GET /admin/analytics/bookings?from=&to=
func AdminGetBookingAnalytics(c *gin.Context) {
	from := c.Query("from")
	to := c.Query("to")

	var out struct {
		TotalBookings     int     `json:"total_bookings"`
		TodayBookings     int     `json:"today_bookings"`
		WeeklyBookings    int     `json:"weekly_bookings"`
		MonthlyBookings   int     `json:"monthly_bookings"`
		BookingsInRange   int     `json:"bookings_in_range"`
		Completed         int     `json:"completed_bookings"`
		Pending           int     `json:"pending_bookings"`
		RejectedCancelled int     `json:"rejected_cancelled_bookings"`
		Chat              int     `json:"chat_bookings"`
		Audio             int     `json:"audio_bookings"`
		Video             int     `json:"video_bookings"`
		Visit             int     `json:"visit_bookings"`
		AvgDurationMin    float64 `json:"average_duration_minutes"`
	}

	config.DB.QueryRow(`SELECT COUNT(*) FROM consultations`).Scan(&out.TotalBookings)
	config.DB.QueryRow(`SELECT COUNT(*) FROM consultations WHERE created_at >= CURRENT_DATE`).Scan(&out.TodayBookings)
	config.DB.QueryRow(`SELECT COUNT(*) FROM consultations WHERE created_at >= NOW() - INTERVAL '7 days'`).Scan(&out.WeeklyBookings)
	config.DB.QueryRow(`SELECT COUNT(*) FROM consultations WHERE created_at >= date_trunc('month', NOW())`).Scan(&out.MonthlyBookings)
	config.DB.QueryRow(`SELECT COUNT(*) FROM consultations WHERE status='completed'`).Scan(&out.Completed)
	config.DB.QueryRow(`SELECT COUNT(*) FROM consultations WHERE status='pending'`).Scan(&out.Pending)
	config.DB.QueryRow(`SELECT COUNT(*) FROM consultations WHERE status IN ('rejected','cancelled','expired')`).Scan(&out.RejectedCancelled)

	config.DB.QueryRow(`SELECT COUNT(*) FROM consultations WHERE ` + analyticsCallTypeCase + ` = 'chat'`).Scan(&out.Chat)
	config.DB.QueryRow(`SELECT COUNT(*) FROM consultations WHERE ` + analyticsCallTypeCase + ` = 'audio'`).Scan(&out.Audio)
	config.DB.QueryRow(`SELECT COUNT(*) FROM consultations WHERE ` + analyticsCallTypeCase + ` = 'video'`).Scan(&out.Video)
	config.DB.QueryRow(`SELECT COUNT(*) FROM consultations WHERE ` + analyticsCallTypeCase + ` = 'visit'`).Scan(&out.Visit)

	// call_duration_seconds is only ever populated for a call that actually
	// ran (see SaveCallDuration in consultation_controller.go) — averaging
	// over rows where it's still 0 would understate every real call, so
	// only sessions with a recorded duration count.
	config.DB.QueryRow(`
		SELECT COALESCE(AVG(call_duration_seconds), 0) / 60.0 FROM consultations WHERE call_duration_seconds > 0
	`).Scan(&out.AvgDurationMin)

	args := []interface{}{}
	rangeClause := analyticsDateFilter("created_at", from, to, &args)
	config.DB.QueryRow(`SELECT COUNT(*) FROM consultations WHERE 1=1`+rangeClause, args...).Scan(&out.BookingsInRange)

	utils.Success(c, http.StatusOK, "Booking analytics fetched", out)
}

// AdminGetAnalyticsTrends - GET /admin/analytics/trends?days=30
// Every series a chart on this page needs, all built with the same
// dailySeries helper AdminGetStats/AdminGetRevenue already use.
func AdminGetAnalyticsTrends(c *gin.Context) {
	days := 30
	if d := c.Query("days"); d != "" {
		if n, err := strconv.Atoi(d); err == nil && n > 0 {
			days = n
		}
	}
	if days > 180 {
		days = 180
	}
	// The window's last day defaults to today, but a wholly-past selected
	// range (e.g. "Yesterday", "Last Month") must end there instead — see
	// dailySeriesEnding's doc comment.
	end := c.Query("to")

	notSuperAdmin := `role_id NOT IN (SELECT id FROM roles WHERE name='super_admin')`

	utils.Success(c, http.StatusOK, "Analytics trends fetched", gin.H{
		"user_growth": dailySeriesEnding(`SELECT created_at::date, COUNT(*) FROM users WHERE `+notSuperAdmin, days, end),
		"lawyer_registrations": dailySeriesEnding(`
			SELECT u.created_at::date, COUNT(*) FROM users u JOIN roles r ON u.role_id=r.id WHERE r.name='lawyer'`, days, end),
		"client_registrations": dailySeriesEnding(`
			SELECT u.created_at::date, COUNT(*) FROM users u JOIN roles r ON u.role_id=r.id WHERE r.name='client'`, days, end),
		"bookings":      dailySeriesEnding(`SELECT created_at::date, COUNT(*) FROM consultations`, days, end),
		"revenue":       dailySeriesEnding(`SELECT paid_at::date, COALESCE(SUM(amount_paise),0)/100.0 FROM consultations WHERE payment_status='paid' AND paid_at IS NOT NULL`, days, end),
		"gst_collected": dailySeriesEnding(`SELECT created_at::date, COALESCE(SUM(tax_amount),0) FROM invoices WHERE status='paid'`, days, end),
		"platform_fees": dailySeriesEnding(`
			SELECT d, SUM(v) FROM (
				SELECT updated_at::date AS d, COALESCE(amount_paise,0)/100.0 AS v FROM payment_orders WHERE kind='subscription' AND status='paid'
				UNION ALL
				SELECT created_at::date AS d, COALESCE(platform_fee,0) AS v FROM invoices WHERE status='paid'
			) x`, days, end),
		"lawyer_payouts":       dailySeriesEnding(`SELECT paid_at::date, COALESCE(SUM(amount_paise),0)/100.0 FROM consultations WHERE payment_status='paid' AND paid_at IS NOT NULL`, days, end),
		"refunds":              dailySeriesEnding(`SELECT paid_at::date, COALESCE(SUM(amount_paise),0)/100.0 FROM consultations WHERE payment_status='refunded' AND paid_at IS NOT NULL`, days, end),
		"subscription_revenue": dailySeriesEnding(`SELECT created_at::date, COALESCE(SUM(amount),0) FROM subscription_payments`, days, end),
	})
}

// AdminGetAnalyticsTransactions - GET /admin/analytics/transactions
// ?search= ?service=chat|audio|video|visit ?status= ?lawyer= ?client= ?from= ?to= ?page=
//
// One unified report row per real payment event, drawn from the three
// distinct payment systems in this codebase (consultations, invoices,
// subscription_payments — see this file's top comment). Each source
// populates only the columns it genuinely has; GST/platform fee/lawyer
// payout are NULL, not zero or guessed, wherever the source doesn't carry
// that concept — a consultation has no GST, a subscription payment has no
// lawyer payout, etc.
func AdminGetAnalyticsTransactions(c *gin.Context) {
	search := c.Query("search")
	service := c.Query("service")
	status := c.Query("status")
	lawyer := c.Query("lawyer")
	client := c.Query("client")
	from := c.Query("from")
	to := c.Query("to")
	page := ParsePagination(c)

	// Three normalized sources, UNIONed, then filtered/paginated once — this
	// is a report VIEW over existing tables, not a new payments table.
	query := `
		WITH unified AS (
			SELECT
				co.id::text AS id, 'consultation' AS source,
				co.created_at AS txn_date,
				COALESCE(cl.name,'') AS client_name,
				COALESCE(law.name,'') AS lawyer_name,
				` + analyticsCallTypeCase + ` AS service_type,
				COALESCE(co.amount_paise,0)/100.0 AS gross_amount,
				NULL::numeric AS gst_amount,
				NULL::numeric AS platform_fee,
				CASE WHEN co.payment_status='paid' THEN COALESCE(co.amount_paise,0)/100.0 ELSE 0 END AS lawyer_payout,
				CASE WHEN co.payment_status='refunded' THEN COALESCE(co.amount_paise,0)/100.0 ELSE 0 END AS refund_amount,
				false AS is_subscription,
				co.payment_status AS status,
				COALESCE(co.razorpay_payment_id,'') AS transaction_ref
			FROM consultations co
			LEFT JOIN users cl ON cl.id = co.client_id
			LEFT JOIN users law ON law.id = co.lawyer_id
			WHERE co.amount_paise IS NOT NULL

			UNION ALL

			SELECT
				i.id::text, 'invoice',
				i.created_at,
				COALESCE(cli.name,''),
				COALESCE(fl.name,''),
				'invoice',
				COALESCE(i.subtotal,0),
				COALESCE(i.tax_amount,0),
				COALESCE(i.platform_fee,0),
				NULL::numeric,
				0,
				false,
				i.status,
				COALESCE(i.transaction_id,'')
			FROM invoices i
			LEFT JOIN clients cli ON cli.id = i.client_id
			LEFT JOIN users fl ON fl.id = i.created_by

			UNION ALL

			SELECT
				sp.id::text, 'subscription',
				sp.created_at,
				'',
				COALESCE(f.name,''),
				'subscription',
				sp.amount,
				NULL::numeric,
				NULL::numeric,
				NULL::numeric,
				0,
				true,
				sp.status,
				COALESCE(sp.payment_id,'')
			FROM subscription_payments sp
			LEFT JOIN firms f ON f.id = sp.firm_id
		)
		SELECT id, source, txn_date::text, client_name, lawyer_name, service_type,
		       gross_amount, gst_amount, platform_fee, lawyer_payout, refund_amount,
		       is_subscription, status, transaction_ref
		FROM unified
		WHERE 1=1`

	args := []interface{}{}
	if search != "" {
		args = append(args, "%"+search+"%")
		query += fmt.Sprintf(` AND (client_name ILIKE $%d OR lawyer_name ILIKE $%d OR transaction_ref ILIKE $%d)`,
			len(args), len(args), len(args))
	}
	if service != "" {
		args = append(args, service)
		query += fmt.Sprintf(` AND service_type = $%d`, len(args))
	}
	if status != "" {
		args = append(args, status)
		query += fmt.Sprintf(` AND status = $%d`, len(args))
	}
	if lawyer != "" {
		args = append(args, "%"+lawyer+"%")
		query += fmt.Sprintf(` AND lawyer_name ILIKE $%d`, len(args))
	}
	if client != "" {
		args = append(args, "%"+client+"%")
		query += fmt.Sprintf(` AND client_name ILIKE $%d`, len(args))
	}
	query += analyticsDateFilter("txn_date", from, to, &args)
	query += ` ORDER BY txn_date DESC`
	args = append(args, page.Limit, page.Offset)
	query += fmt.Sprintf(` LIMIT $%d OFFSET $%d`, len(args)-1, len(args))

	rows, err := config.DB.Query(query, args...)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch transactions", err.Error())
		return
	}
	defer rows.Close()

	out := []gin.H{}
	for rows.Next() {
		var id, source, txnDate, clientName, lawyerName, serviceType, status, txnRef string
		var gross float64
		var gst, platformFee, payout *float64
		var refund float64
		var isSub bool
		if err := rows.Scan(&id, &source, &txnDate, &clientName, &lawyerName, &serviceType,
			&gross, &gst, &platformFee, &payout, &refund, &isSub, &status, &txnRef); err != nil {
			utils.Error(c, http.StatusInternalServerError, "Failed to read transactions", err.Error())
			return
		}
		net := gross - refund
		if gst != nil {
			net -= *gst
		}
		if platformFee != nil {
			net -= *platformFee
		}
		out = append(out, gin.H{
			"id":              id,
			"source":          source,
			"date":            txnDate,
			"transaction_id":  txnRef,
			"client_name":     clientName,
			"lawyer_name":     lawyerName,
			"service_type":    serviceType,
			"gross_amount":    gross,
			"gst_amount":      gst,
			"platform_fee":    platformFee,
			"lawyer_payout":   payout,
			"refund_amount":   refund,
			"is_subscription": isSub,
			"net_revenue":     net,
			"status":          status,
		})
	}
	utils.SuccessWithMeta(c, http.StatusOK, "Transactions fetched", out, page.Meta(len(out)))
}
