package controllers

import (
	"fmt"
	"libra/config"
	"libra/utils"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

// ─── GET ALL USERS ────────────────────────────────
//
// ?role=lawyer|law_student|client|admin  ?status=active|suspended
// ?search=name/email/phone substring     ?from=&to= (registration date range)
// plus the same page/limit pagination every other admin list uses.
//
// The per-user consultation/payment aggregates are computed with a
// role-agnostic pair of correlated subqueries — "consultations where this
// user is the client" and "...where this user is the lawyer" — rather than
// two different queries per role, since a single query has to serve the
// combined Users list (all roles at once).
func AdminGetUsers(c *gin.Context) {
	role := c.Query("role")
	status := c.Query("status")
	search := strings.TrimSpace(c.Query("search"))
	from := c.Query("from")
	to := c.Query("to")
	page := ParsePagination(c)

	query := `
		SELECT u.id, u.name, u.email, COALESCE(u.phone,''),
		       COALESCE(r.name,''), u.is_active,
		       COALESCE(u.created_at::text,''),
		       COALESCE(u.last_login_at::text,''),
		       COALESCE(u.verification_status,''),
		       (SELECT COUNT(*) FROM consultations co WHERE co.client_id=u.id OR co.lawyer_id=u.id),
		       (SELECT COUNT(*) FROM consultations co WHERE (co.client_id=u.id OR co.lawyer_id=u.id) AND co.payment_status='paid'),
		       (SELECT COALESCE(SUM(co.amount_paise),0)/100.0 FROM consultations co WHERE co.client_id=u.id AND co.payment_status='paid')
		FROM users u
		LEFT JOIN roles r ON u.role_id = r.id
		WHERE r.name != 'super_admin'`
	args := []interface{}{}
	if role != "" {
		if role == "lawyer" {
			query += ` AND r.name IN ('lawyer','admin')`
		} else {
			args = append(args, role)
			query += fmt.Sprintf(` AND r.name = $%d`, len(args))
		}
	}
	if status == "active" {
		query += ` AND u.is_active = true`
	} else if status == "suspended" {
		query += ` AND u.is_active = false`
	}
	if search != "" {
		args = append(args, "%"+search+"%")
		query += fmt.Sprintf(` AND (u.name ILIKE $%d OR u.email ILIKE $%d OR u.phone ILIKE $%d)`, len(args), len(args), len(args))
	}
	if from != "" {
		args = append(args, from)
		query += fmt.Sprintf(` AND u.created_at >= $%d::date`, len(args))
	}
	if to != "" {
		args = append(args, to)
		query += fmt.Sprintf(` AND u.created_at < ($%d::date + INTERVAL '1 day')`, len(args))
	}
	query += ` ORDER BY u.created_at DESC`
	args = append(args, page.Limit, page.Offset)
	query += fmt.Sprintf(` LIMIT $%d OFFSET $%d`, len(args)-1, len(args))

	rows, err := config.DB.Query(query, args...)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch users", err.Error())
		return
	}
	defer rows.Close()

	type User struct {
		ID                 string  `json:"id"`
		Name               string  `json:"name"`
		Email              string  `json:"email"`
		Phone              string  `json:"phone"`
		RoleName           string  `json:"role_name"`
		IsActive           bool    `json:"is_active"`
		CreatedAt          string  `json:"created_at"`
		LastLoginAt        string  `json:"last_login_at"`
		VerificationStatus string  `json:"verification_status"`
		TotalConsultations int     `json:"total_consultations"`
		TotalPayments      int     `json:"total_payments"`
		TotalAmountPaid    float64 `json:"total_amount_paid"`
	}

	users := []User{}
	for rows.Next() {
		var u User
		rows.Scan(&u.ID, &u.Name, &u.Email, &u.Phone,
			&u.RoleName, &u.IsActive, &u.CreatedAt, &u.LastLoginAt,
			&u.VerificationStatus, &u.TotalConsultations, &u.TotalPayments, &u.TotalAmountPaid)
		users = append(users, u)
	}
	utils.SuccessWithMeta(c, http.StatusOK, "Users fetched", users, page.Meta(len(users)))
}

// ─── GET USER DETAIL ──────────────────────────────
//
// One endpoint for the Users/Lawyers/Students/Clients detail pages alike —
// the profile fields are the same `users` row regardless of role, and the
// activity sections (consultations both as client and as lawyer, payments,
// documents, student progress) simply come back empty for a role they don't
// apply to instead of needing four near-identical handlers.
func AdminGetUserDetail(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "not a uuid")
		return
	}

	var u struct {
		ID                 string  `json:"id"`
		Name               string  `json:"name"`
		Email              string  `json:"email"`
		Phone              string  `json:"phone"`
		RoleName           string  `json:"role_name"`
		FirmID             string  `json:"firm_id"`
		AvatarURL          string  `json:"avatar_url"`
		Designation        string  `json:"designation"`
		BarCouncilNumber   string  `json:"bar_council_number"`
		IsActive           bool    `json:"is_active"`
		VerificationStatus string  `json:"verification_status"`
		RejectionReason    string  `json:"rejection_reason"`
		CreatedAt          string  `json:"created_at"`
		LastLoginAt        string  `json:"last_login_at"`
		EarningsPaid    float64 `json:"earnings_paid"`
		// EarningsPending is the value of this lawyer's own booked
		// consultations still sitting at payment_status='pending' — not a
		// payout queue (no payout/settlement feature exists in this
		// codebase; see AdminGetBillingRevenue's doc comment).
		EarningsPending float64 `json:"earnings_pending"`
		SpentTotal      float64 `json:"spent_total"`
	}
	err := config.DB.QueryRow(`
		SELECT u.id, u.name, u.email, COALESCE(u.phone,''), COALESCE(r.name,''),
		       COALESCE(u.firm_id::text,''), COALESCE(u.avatar_url,''),
		       COALESCE(u.designation,''), COALESCE(u.bar_council_number,''),
		       u.is_active, COALESCE(u.verification_status,''), COALESCE(u.rejection_reason,''),
		       COALESCE(u.created_at::text,''), COALESCE(u.last_login_at::text,''),
		       (SELECT COALESCE(SUM(amount_paise),0)/100.0 FROM consultations WHERE lawyer_id=u.id AND payment_status='paid'),
		       (SELECT COALESCE(SUM(amount_paise),0)/100.0 FROM consultations WHERE lawyer_id=u.id AND payment_status='pending'),
		       (SELECT COALESCE(SUM(amount_paise),0)/100.0 FROM consultations WHERE client_id=u.id AND payment_status='paid')
		FROM users u
		LEFT JOIN roles r ON u.role_id = r.id
		WHERE u.id = $1::uuid
	`, id).Scan(&u.ID, &u.Name, &u.Email, &u.Phone, &u.RoleName, &u.FirmID, &u.AvatarURL,
		&u.Designation, &u.BarCouncilNumber, &u.IsActive, &u.VerificationStatus, &u.RejectionReason,
		&u.CreatedAt, &u.LastLoginAt, &u.EarningsPaid, &u.EarningsPending, &u.SpentTotal)
	if err != nil {
		utils.Error(c, http.StatusNotFound, "User not found", err.Error())
		return
	}

	asClient := adminConsultationRows(`co.client_id = $1::uuid`, id, 20)
	asLawyer := adminConsultationRows(`co.lawyer_id = $1::uuid`, id, 20)

	docsRows, _ := config.DB.Query(`
		SELECT id, file_name, COALESCE(category,''), COALESCE(created_at::text,'')
		FROM documents WHERE uploaded_by = $1::uuid ORDER BY created_at DESC LIMIT 20
	`, id)
	type Doc struct {
		ID        string `json:"id"`
		FileName  string `json:"file_name"`
		Category  string `json:"category"`
		CreatedAt string `json:"created_at"`
	}
	docs := []Doc{}
	if docsRows != nil {
		defer docsRows.Close()
		for docsRows.Next() {
			var d Doc
			docsRows.Scan(&d.ID, &d.FileName, &d.Category, &d.CreatedAt)
			docs = append(docs, d)
		}
	}

	var progress *gin.H
	if u.RoleName == "law_student" {
		// Real student_progress columns — see AdminGetStudents' comment on
		// the pre-existing xp/level column-name mismatch elsewhere in the
		// codebase.
		var score, total, completed, streak int
		if config.DB.QueryRow(`
			SELECT COALESCE(total_score,0), COALESCE(total_challenges,0), COALESCE(completed_challenges,0), COALESCE(streak_days,0)
			FROM student_progress WHERE user_id=$1::uuid
		`, id).Scan(&score, &total, &completed, &streak) == nil {
			progress = &gin.H{"total_score": score, "total_challenges": total, "completed_challenges": completed, "streak_days": streak}
		}
	}

	utils.Success(c, http.StatusOK, "User detail fetched", gin.H{
		"profile":              u,
		"consultations_client": asClient,
		"consultations_lawyer": asLawyer,
		"documents":            docs,
		"student_progress":     progress,
	})
}

// adminConsultationRows is shared between AdminGetUserDetail (both the
// client-side and lawyer-side history for one user) and AdminGetConsultations
// (the platform-wide list) so the same column set/shape is returned
// everywhere a consultation row appears in the admin panel.
func adminConsultationRows(whereClause, arg string, limit int) []gin.H {
	rows, err := config.DB.Query(fmt.Sprintf(`
		SELECT co.id, co.consultation_type, co.consultation_date::text, co.consultation_time,
		       co.status, co.payment_status, COALESCE(co.amount_paise,0),
		       COALESCE(cl.name,''), COALESCE(law.name,''), co.created_at::text
		FROM consultations co
		LEFT JOIN users cl  ON co.client_id = cl.id
		LEFT JOIN users law ON co.lawyer_id = law.id
		WHERE %s
		ORDER BY co.created_at DESC
		LIMIT %d
	`, whereClause, limit), arg)
	out := []gin.H{}
	if err != nil {
		return out
	}
	defer rows.Close()
	for rows.Next() {
		var id, ctype, cdate, ctime, status, payStatus, clientName, lawyerName, createdAt string
		var amountPaise int64
		if rows.Scan(&id, &ctype, &cdate, &ctime, &status, &payStatus, &amountPaise, &clientName, &lawyerName, &createdAt) == nil {
			out = append(out, gin.H{
				"id": id, "consultation_type": ctype, "consultation_date": cdate, "consultation_time": ctime,
				"status": status, "payment_status": payStatus, "amount_rupees": float64(amountPaise) / 100,
				"client_name": clientName, "lawyer_name": lawyerName, "created_at": createdAt,
			})
		}
	}
	return out
}

// ─── UPDATE USER (Suspend / Activate) ────────────
func AdminUpdateUser(c *gin.Context) {
	userID := c.Param("id")
	if !isUUID(userID) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "not a uuid")
		return
	}
	if userID == utils.UserID(c) {
		utils.Error(c, http.StatusBadRequest,
			"You cannot suspend your own account", "self-suspend")
		return
	}

	var req struct {
		IsActive bool `json:"is_active"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}
	// Never let one platform admin disable another.
	res, err := config.DB.Exec(`
		UPDATE users SET is_active=$1, updated_at=NOW()
		WHERE id=$2::uuid
		  AND role_id NOT IN (SELECT id FROM roles WHERE name='super_admin')
	`, req.IsActive, userID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to update user", err.Error())
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		utils.Error(c, http.StatusNotFound, "User not found", "")
		return
	}
	action := "suspended"
	if req.IsActive {
		action = "activated"
	}
	utils.Success(c, http.StatusOK, "User "+action, nil)
}

// ─── DELETE USER ──────────────────────────────────
//
// Deactivates rather than deleting. The old handler ran a hard
// `DELETE FROM users`, which in a legal practice tool destroys the authorship
// trail on cases, notes, invoices and audit logs — records a firm may be
// required to retain — and cascades through every foreign key that references
// the user.
func AdminDeleteUser(c *gin.Context) {
	userID := c.Param("id")
	if !isUUID(userID) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "not a uuid")
		return
	}
	if userID == utils.UserID(c) {
		utils.Error(c, http.StatusBadRequest,
			"You cannot delete your own account", "self-delete")
		return
	}

	_, err := config.DB.Exec(`
		UPDATE users SET is_active=false, updated_at=NOW()
		WHERE id=$1::uuid
		  AND role_id NOT IN (SELECT id FROM roles WHERE name='super_admin')
	`, userID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to delete user", err.Error())
		return
	}
	utils.Success(c, http.StatusOK, "User deleted", nil)
}

// ─── GET ADMIN STATS ──────────────────────────────
//
// The admin dashboard's single source of truth. Every number here is a live
// aggregate against the same tables the rest of the app already writes to —
// consultations, payment_orders, invoices, cases, documents, hearings —
// there is no separate "admin stats" table to keep in sync.
//
// "lawyer" here always means role IN ('lawyer','admin'): registering "as a
// lawyer" (RegisterScreen) creates a role='admin' user (the firm owner) —
// see AdminGetLawyers' own comment on the same fact. Counting only
// role='lawyer' would make every self-registered lawyer invisible.
func AdminGetStats(c *gin.Context) {
	var stats struct {
		TotalUsers    int `json:"total_users"`
		TotalLawyers  int `json:"total_lawyers"`
		TotalClients  int `json:"total_clients"`
		TotalStudents int `json:"total_students"`

		ActiveLawyers  int `json:"active_lawyers"`
		ActiveClients  int `json:"active_clients"`
		ActiveStudents int `json:"active_students"`

		PendingVerification int `json:"pending_verification"`

		TotalConsultations     int `json:"total_consultations"`
		PendingConsultations   int `json:"pending_consultations"`
		CompletedConsultations int `json:"completed_consultations"`
		CancelledConsultations int `json:"cancelled_consultations"`

		TotalPayments      int `json:"total_payments"`
		SuccessfulPayments int `json:"successful_payments"`
		FailedPayments     int `json:"failed_payments"`
		PendingPayments    int `json:"pending_payments"`

		// See AdminGetBillingRevenue's doc comment for what these mean and why
		// they are kept separate rather than blended into one "revenue" figure —
		// there is no commission/payout system in this codebase, so "platform
		// revenue" cannot honestly include a cut of consultation fees that does
		// not exist.
		TotalRevenue     float64 `json:"total_revenue"`
		MonthlyRevenue   float64 `json:"monthly_revenue"`
		LawyerEarnings   float64 `json:"lawyer_earnings"`
		PlatformRevenue  float64 `json:"platform_revenue"`
		FirmInvoiceTotal float64 `json:"firm_invoice_total"`
		// GSTCollected is tax the client paid on an invoice — it belongs to
		// the tax authorities, not the platform or the firm. Reported
		// separately so it is never mistaken for platform_revenue or
		// firm_invoice_total; see AdminGetRevenue's doc comment for the
		// full accounting rationale.
		GSTCollected float64 `json:"gst_collected"`
		RefundAmount float64 `json:"refund_amount"`

		ActiveSubscriptions int `json:"active_subscriptions"`

		TotalCases     int `json:"total_cases"`
		TotalDocuments int `json:"total_documents"`
		TotalHearings  int `json:"total_hearings"`
	}

	config.DB.QueryRow(`SELECT COUNT(*) FROM users WHERE role_id NOT IN (SELECT id FROM roles WHERE name='super_admin')`).Scan(&stats.TotalUsers)
	config.DB.QueryRow(`SELECT COUNT(*) FROM users u JOIN roles r ON u.role_id=r.id WHERE r.name IN ('lawyer','admin')`).Scan(&stats.TotalLawyers)
	config.DB.QueryRow(`SELECT COUNT(*) FROM users u JOIN roles r ON u.role_id=r.id WHERE r.name='client'`).Scan(&stats.TotalClients)
	config.DB.QueryRow(`SELECT COUNT(*) FROM users u JOIN roles r ON u.role_id=r.id WHERE r.name='law_student'`).Scan(&stats.TotalStudents)

	config.DB.QueryRow(`SELECT COUNT(*) FROM users u JOIN roles r ON u.role_id=r.id WHERE r.name IN ('lawyer','admin') AND u.is_active`).Scan(&stats.ActiveLawyers)
	config.DB.QueryRow(`SELECT COUNT(*) FROM users u JOIN roles r ON u.role_id=r.id WHERE r.name='client' AND u.is_active`).Scan(&stats.ActiveClients)
	config.DB.QueryRow(`SELECT COUNT(*) FROM users u JOIN roles r ON u.role_id=r.id WHERE r.name='law_student' AND u.is_active`).Scan(&stats.ActiveStudents)

	config.DB.QueryRow(`SELECT COUNT(*) FROM users u JOIN roles r ON u.role_id=r.id WHERE r.name IN ('lawyer','admin') AND COALESCE(u.verification_status,'verified')='pending'`).Scan(&stats.PendingVerification)

	config.DB.QueryRow(`SELECT COUNT(*) FROM consultations`).Scan(&stats.TotalConsultations)
	config.DB.QueryRow(`SELECT COUNT(*) FROM consultations WHERE status='pending'`).Scan(&stats.PendingConsultations)
	config.DB.QueryRow(`SELECT COUNT(*) FROM consultations WHERE status='completed'`).Scan(&stats.CompletedConsultations)
	config.DB.QueryRow(`SELECT COUNT(*) FROM consultations WHERE status='cancelled'`).Scan(&stats.CancelledConsultations)

	// payment_orders covers every gateway transaction attempt for
	// consultations and subscriptions (see VerifyConsultationPayment /
	// ActivateSubscription), but invoices are almost always settled through
	// the manual UPI/bank-transfer proof flow (payment_screen.dart →
	// CreatePayment/VerifyPayment), which never creates a payment_orders row
	// at all — so counting payment_orders alone would silently miss most
	// invoice payments. Both tables are added together for a true platform
	// total.
	var poTotal, poPaid, poFailed, poPending int
	config.DB.QueryRow(`SELECT COUNT(*) FROM payment_orders`).Scan(&poTotal)
	config.DB.QueryRow(`SELECT COUNT(*) FROM payment_orders WHERE status='paid'`).Scan(&poPaid)
	config.DB.QueryRow(`SELECT COUNT(*) FROM payment_orders WHERE status='failed'`).Scan(&poFailed)
	config.DB.QueryRow(`SELECT COUNT(*) FROM payment_orders WHERE status='created'`).Scan(&poPending)

	var payTotal, payVerified, payRejected, payPending int
	config.DB.QueryRow(`SELECT COUNT(*) FROM payments`).Scan(&payTotal)
	config.DB.QueryRow(`SELECT COUNT(*) FROM payments WHERE verification_status='verified'`).Scan(&payVerified)
	config.DB.QueryRow(`SELECT COUNT(*) FROM payments WHERE verification_status='rejected'`).Scan(&payRejected)
	config.DB.QueryRow(`SELECT COUNT(*) FROM payments WHERE COALESCE(verification_status,'pending')='pending'`).Scan(&payPending)

	stats.TotalPayments = poTotal + payTotal
	stats.SuccessfulPayments = poPaid + payVerified
	stats.FailedPayments = poFailed + payRejected
	stats.PendingPayments = poPending + payPending

	config.DB.QueryRow(`SELECT COALESCE(SUM(amount_paise),0)/100.0 FROM consultations WHERE payment_status='paid'`).Scan(&stats.LawyerEarnings)

	// Platform revenue is money that lands with Libra Law itself: lawyers'
	// SaaS subscription payments, plus the flat ₹100 platform fee on every
	// paid invoice. GST on an invoice is deliberately excluded — it is a
	// pass-through tax liability, never the platform's or the firm's money
	// to keep — and the invoice's own service amount (subtotal) is the
	// firm's revenue, not the platform's.
	var subRevenue, invoicePlatformFees float64
	config.DB.QueryRow(`
		SELECT COALESCE(SUM(amount_paise),0)/100.0 FROM payment_orders
		WHERE kind='subscription' AND status='paid'
	`).Scan(&subRevenue)
	config.DB.QueryRow(`SELECT COALESCE(SUM(platform_fee),0) FROM invoices WHERE status='paid'`).Scan(&invoicePlatformFees)
	stats.PlatformRevenue = subRevenue + invoicePlatformFees

	config.DB.QueryRow(`SELECT COALESCE(SUM(subtotal),0) FROM invoices WHERE status='paid'`).Scan(&stats.FirmInvoiceTotal)
	config.DB.QueryRow(`SELECT COALESCE(SUM(tax_amount),0) FROM invoices WHERE status='paid'`).Scan(&stats.GSTCollected)
	config.DB.QueryRow(`SELECT COALESCE(SUM(amount_paise),0)/100.0 FROM consultations WHERE payment_status='refunded'`).Scan(&stats.RefundAmount)
	stats.TotalRevenue = stats.LawyerEarnings + stats.PlatformRevenue + stats.FirmInvoiceTotal + stats.GSTCollected
	config.DB.QueryRow(`
		SELECT COALESCE(SUM(amount_paise),0)/100.0 FROM consultations
		WHERE payment_status='paid' AND paid_at >= date_trunc('month', NOW())
	`).Scan(&stats.MonthlyRevenue)
	var monthlySub, monthlyInvoice float64
	config.DB.QueryRow(`
		SELECT COALESCE(SUM(amount_paise),0)/100.0 FROM payment_orders
		WHERE kind='subscription' AND status='paid' AND updated_at >= date_trunc('month', NOW())
	`).Scan(&monthlySub)
	config.DB.QueryRow(`
		SELECT COALESCE(SUM(total_amount),0) FROM invoices
		WHERE status='paid' AND created_at >= date_trunc('month', NOW())
	`).Scan(&monthlyInvoice)
	stats.MonthlyRevenue += monthlySub + monthlyInvoice

	config.DB.QueryRow(`SELECT COUNT(*) FROM subscriptions WHERE status='active'`).Scan(&stats.ActiveSubscriptions)

	config.DB.QueryRow(`SELECT COUNT(*) FROM cases`).Scan(&stats.TotalCases)
	config.DB.QueryRow(`SELECT COUNT(*) FROM documents`).Scan(&stats.TotalDocuments)
	config.DB.QueryRow(`SELECT COUNT(*) FROM hearings`).Scan(&stats.TotalHearings)

	utils.Success(c, http.StatusOK, "Stats fetched", gin.H{
		"summary":           stats,
		"registrations_14d": dailySeries(`SELECT created_at::date, COUNT(*) FROM users WHERE role_id NOT IN (SELECT id FROM roles WHERE name='super_admin')`, 14),
		"consultations_14d": dailySeries(`SELECT created_at::date, COUNT(*) FROM consultations`, 14),
		"revenue_14d":       dailySeries(`SELECT paid_at::date, COALESCE(SUM(amount_paise),0)/100.0 FROM consultations WHERE payment_status='paid' AND paid_at IS NOT NULL`, 14),
		"role_distribution": gin.H{"lawyers": stats.TotalLawyers, "students": stats.TotalStudents, "clients": stats.TotalClients},
	})
}

// dailySeries takes a query of the shape `SELECT <date_col>, <agg> FROM ...
// [WHERE ...]` (no GROUP BY — added here) and left-joins its per-day result
// onto a generated date series covering the trailing `days` days, so every
// day in the window appears in the chart even when its count/sum is zero.
// One implementation of "count/sum something per day", shared by every
// trend chart on the dashboard and the revenue screen, instead of one
// hand-rolled query per chart.
func dailySeries(baseQuery string, days int) []gin.H {
	out := []gin.H{}
	rows, err := config.DB.Query(fmt.Sprintf(`
		WITH days AS (
			SELECT generate_series(CURRENT_DATE - INTERVAL '%d days', CURRENT_DATE, INTERVAL '1 day')::date AS d
		), agg AS (
			%s GROUP BY 1
		)
		SELECT days.d, COALESCE(a.value, 0)
		FROM days
		LEFT JOIN agg AS a(date_col, value) ON a.date_col = days.d
		ORDER BY days.d
	`, days-1, baseQuery))
	if err != nil {
		return out
	}
	defer rows.Close()
	for rows.Next() {
		var d time.Time
		var v float64
		if rows.Scan(&d, &v) == nil {
			out = append(out, gin.H{"date": d.Format("2006-01-02"), "value": v})
		}
	}
	return out
}

// ─── GET ALL LAWYERS ──────────────────────────────
//
// Registering "as a lawyer" (RegisterScreen / auth_controller.Register)
// actually creates a role='admin' user — the firm owner — so both 'lawyer'
// and 'admin' role users are included here; otherwise no self-registered
// lawyer would ever appear in this verification list.
// ?status=pending|verified|rejected filters by verification_status — the
// Verification nav section reuses this endpoint with ?status=pending rather
// than needing its own listing query.
func AdminGetLawyers(c *gin.Context) {
	verifyStatus := c.Query("status")

	query := `
		SELECT u.id, u.name, u.email, COALESCE(u.phone,''),
		       u.is_active, COALESCE(u.created_at::text,''),
		       COALESCE(u.bar_council_number,''), COALESCE(u.verification_status,'verified'),
		       COALESCE(u.rejection_reason,''),
		       COALESCE((SELECT d.id::text FROM documents d
		                 WHERE d.uploaded_by = u.id AND d.category = 'lawyer_verification'
		                 ORDER BY d.created_at DESC LIMIT 1), ''),
		       (SELECT COUNT(*) FROM consultations co WHERE co.lawyer_id=u.id),
		       (SELECT COUNT(*) FROM consultations co WHERE co.lawyer_id=u.id AND co.status='completed'),
		       (SELECT COUNT(*) FROM consultations co WHERE co.lawyer_id=u.id AND co.status='cancelled'),
		       (SELECT COUNT(DISTINCT co.client_id) FROM consultations co WHERE co.lawyer_id=u.id),
		       (SELECT COALESCE(SUM(co.amount_paise),0)/100.0 FROM consultations co WHERE co.lawyer_id=u.id AND co.payment_status='paid'),
		       (SELECT COALESCE(SUM(co.amount_paise),0)/100.0 FROM consultations co WHERE co.lawyer_id=u.id AND co.payment_status='pending')
		FROM users u
		JOIN roles r ON u.role_id = r.id
		WHERE r.name IN ('lawyer', 'admin')`
	args := []interface{}{}
	if verifyStatus != "" {
		args = append(args, verifyStatus)
		query += fmt.Sprintf(` AND COALESCE(u.verification_status,'verified') = $%d`, len(args))
	}
	query += ` ORDER BY u.created_at DESC`

	rows, err := config.DB.Query(query, args...)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed", err.Error())
		return
	}
	defer rows.Close()

	type Lawyer struct {
		ID                     string  `json:"id"`
		Name                   string  `json:"name"`
		Email                  string  `json:"email"`
		Phone                  string  `json:"phone"`
		IsActive               bool    `json:"is_active"`
		CreatedAt              string  `json:"created_at"`
		BarCouncilNumber       string  `json:"bar_council_number"`
		VerificationStatus     string  `json:"verification_status"`
		RejectionReason        string  `json:"rejection_reason"`
		DocumentID             string  `json:"document_id"`
		TotalConsultations     int     `json:"total_consultations"`
		CompletedConsultations int     `json:"completed_consultations"`
		CancelledConsultations int     `json:"cancelled_consultations"`
		TotalClients           int     `json:"total_clients"`
		EarningsPaid           float64 `json:"earnings_paid"`
		EarningsPending        float64 `json:"earnings_pending"`
	}

	lawyers := []Lawyer{}
	for rows.Next() {
		var l Lawyer
		rows.Scan(&l.ID, &l.Name, &l.Email, &l.Phone, &l.IsActive, &l.CreatedAt,
			&l.BarCouncilNumber, &l.VerificationStatus, &l.RejectionReason, &l.DocumentID,
			&l.TotalConsultations, &l.CompletedConsultations, &l.CancelledConsultations,
			&l.TotalClients, &l.EarningsPaid, &l.EarningsPending)
		lawyers = append(lawyers, l)
	}
	utils.Success(c, http.StatusOK, "Lawyers fetched", lawyers)
}

// ─── GET LAWYER VERIFICATION DOCUMENT ─────────────
//
// Platform-admin-only view of the document a lawyer attached at signup.
// Separate from the firm-scoped GetDocument handler because the caller here
// has no firm of their own to match against.
func AdminGetLawyerDocument(c *gin.Context) {
	userID := c.Param("id")
	if !isUUID(userID) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "not a uuid")
		return
	}
	var d struct {
		ID          string `json:"id"`
		FileName    string `json:"file_name"`
		FileContent string `json:"file_content"`
		MimeType    string `json:"mime_type"`
	}
	err := config.DB.QueryRow(`
		SELECT id, file_name, COALESCE(file_content,''), COALESCE(mime_type,'')
		FROM documents
		WHERE uploaded_by = $1::uuid AND category = 'lawyer_verification'
		ORDER BY created_at DESC LIMIT 1
	`, userID).Scan(&d.ID, &d.FileName, &d.FileContent, &d.MimeType)
	if err != nil {
		utils.Error(c, http.StatusNotFound, "Document not found", err.Error())
		return
	}
	utils.Success(c, http.StatusOK, "Document fetched", d)
}

// ─── APPROVE / REJECT LAWYER VERIFICATION ─────────
//
// Separate from AdminUpdateUser (which only ever toggles is_active) so that
// verifying a lawyer can never accidentally suspend their account, and vice
// versa. Does not touch is_active or the lawyer's ability to use the
// dashboard — verification is informational, tracked here and surfaced to
// the lawyer via the existing in-app notifications list (no separate push
// service exists in this codebase to hook into).
func AdminVerifyLawyer(c *gin.Context) {
	userID := c.Param("id")
	if !isUUID(userID) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "not a uuid")
		return
	}

	var req struct {
		Status          string `json:"verification_status" binding:"required,oneof=verified rejected"`
		RejectionReason string `json:"rejection_reason"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}

	adminID := utils.UserID(c)
	var firmID string
	res, err := config.DB.Exec(`
		UPDATE users
		SET verification_status = $1, rejection_reason = $2,
		    verified_by = $3::uuid, verified_at = NOW(), updated_at = NOW()
		WHERE id = $4::uuid
	`, req.Status, req.RejectionReason, adminID, userID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to update verification", err.Error())
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		utils.Error(c, http.StatusNotFound, "User not found", "")
		return
	}
	config.DB.QueryRow(`SELECT firm_id::text FROM users WHERE id = $1::uuid`, userID).Scan(&firmID)

	title := "Verification Approved"
	message := "Your professional/Bar Council document has been verified. Your account is fully verified."
	if req.Status == "rejected" {
		title = "Verification Rejected"
		message = "Your professional/Bar Council document was rejected."
		if req.RejectionReason != "" {
			message += " Reason: " + req.RejectionReason
		}
	}
	utils.Notify(userID, firmID, title, message, "verification")

	utils.Success(c, http.StatusOK, "Verification updated", nil)
}

// ─── GET SUBSCRIPTIONS ────────────────────────────
func AdminGetSubscriptions(c *gin.Context) {
	utils.Success(c, http.StatusOK, "Subscriptions fetched", []interface{}{})
}

// ─── GET REVENUE / BILLING ────────────────────────
//
// Three genuinely different kinds of money move through this app, and this
// endpoint reports them separately rather than blending them into one
// "revenue" figure, because there is no commission/payout system anywhere in
// this codebase to justify a blend:
//
//   - Consultation payments (payment_orders kind='consultation', mirrored on
//     consultations.amount_paise/payment_status): a client pays a flat fee
//     to consult a lawyer. Razorpay settles this into the platform's own
//     merchant account — there is no per-lawyer sub-account and no payout
//     feature — so today this is booked 100% as "lawyer earnings" (a ledger
//     figure of what the platform owes the lawyer), not money already paid
//     out to them.
//   - Subscription payments (payment_orders kind='subscription'): a lawyer
//     pays Libra Law itself for their SaaS plan. This is the only money that
//     is unambiguously the *platform's own* revenue.
//   - Firm invoices (invoices.status='paid'): a law firm billing its own
//     clients for legal work, tracked for the firm's own billing screen.
//     This is the firm's revenue, not the platform's, and was the only thing
//     the old version of this endpoint reported — kept here under its own
//     name rather than folded into "platform revenue".
//
// Refunds: consultations.payment_status supports 'refunded' (migration 015)
// so the figure is wired up, but nothing in this app can currently issue a
// refund, so it will read ₹0 until a refund path exists.
func AdminGetRevenue(c *gin.Context) {
	from := c.Query("from")
	to := c.Query("to")

	dateFilter := func(col string) (string, []interface{}) {
		clause, args := "", []interface{}{}
		if from != "" {
			args = append(args, from)
			clause += fmt.Sprintf(" AND %s >= $%d::date", col, len(args))
		}
		if to != "" {
			args = append(args, to)
			clause += fmt.Sprintf(" AND %s < ($%d::date + INTERVAL '1 day')", col, len(args))
		}
		return clause, args
	}

	var revenue struct {
		LawyerEarningsGross float64 `json:"lawyer_earnings_gross"`
		PlatformRevenue     float64 `json:"platform_revenue"`
		FirmInvoiceRevenue  float64 `json:"firm_invoice_revenue"`
		// GSTCollected is invoice tax — never platform_revenue or
		// firm_invoice_revenue, see the accounting note above.
		GSTCollected        float64 `json:"gst_collected"`
		InvoicePlatformFees float64 `json:"invoice_platform_fees"`
		RefundAmount        float64 `json:"refund_amount"`
		GrossRevenue        float64 `json:"gross_revenue"`
		NetRevenue          float64 `json:"net_revenue"`
		ConsultationCount   int     `json:"successful_consultation_payments"`
		SubscriptionCount   int     `json:"successful_subscription_payments"`
		InvoiceCount        int     `json:"successful_invoice_payments"`
	}

	clause, args := dateFilter("paid_at")
	config.DB.QueryRow(`SELECT COALESCE(SUM(amount_paise),0)/100.0, COUNT(*) FROM consultations WHERE payment_status='paid'`+clause,
		args...).Scan(&revenue.LawyerEarningsGross, &revenue.ConsultationCount)

	clause, args = dateFilter("updated_at")
	var subRevenue float64
	config.DB.QueryRow(`SELECT COALESCE(SUM(amount_paise),0)/100.0, COUNT(*) FROM payment_orders WHERE kind='subscription' AND status='paid'`+clause,
		args...).Scan(&subRevenue, &revenue.SubscriptionCount)

	// subtotal (the firm's service revenue), tax_amount (GST, a pass-through
	// liability) and platform_fee (genuine platform revenue) are summed
	// separately rather than reading total_amount, exactly as
	// AdminGetStats does — see that handler's comment for the full
	// rationale.
	clause, args = dateFilter("created_at")
	config.DB.QueryRow(`SELECT COALESCE(SUM(subtotal),0), COUNT(*) FROM invoices WHERE status='paid'`+clause,
		args...).Scan(&revenue.FirmInvoiceRevenue, &revenue.InvoiceCount)
	clause, args = dateFilter("created_at")
	config.DB.QueryRow(`SELECT COALESCE(SUM(tax_amount),0) FROM invoices WHERE status='paid'`+clause, args...).Scan(&revenue.GSTCollected)
	clause, args = dateFilter("created_at")
	config.DB.QueryRow(`SELECT COALESCE(SUM(platform_fee),0) FROM invoices WHERE status='paid'`+clause, args...).Scan(&revenue.InvoicePlatformFees)
	revenue.PlatformRevenue = subRevenue + revenue.InvoicePlatformFees

	clause, args = dateFilter("paid_at")
	config.DB.QueryRow(`SELECT COALESCE(SUM(amount_paise),0)/100.0 FROM consultations WHERE payment_status='refunded'`+clause, args...).Scan(&revenue.RefundAmount)

	revenue.GrossRevenue = revenue.LawyerEarningsGross + revenue.PlatformRevenue + revenue.FirmInvoiceRevenue + revenue.GSTCollected
	revenue.NetRevenue = revenue.GrossRevenue - revenue.RefundAmount

	buckets := gin.H{}
	for label, interval := range map[string]string{"today": "1 day", "week": "7 days", "month": "30 days", "year": "365 days"} {
		var v float64
		config.DB.QueryRow(fmt.Sprintf(`
			SELECT COALESCE(SUM(amount_paise),0)/100.0 FROM consultations
			WHERE payment_status='paid' AND paid_at >= NOW() - INTERVAL '%s'
		`, interval)).Scan(&v)
		buckets[label] = v
	}

	utils.Success(c, http.StatusOK, "Revenue fetched", gin.H{
		"summary":                              revenue,
		"consultation_revenue_period_buckets": buckets,
		"revenue_30d": dailySeries(`SELECT paid_at::date, COALESCE(SUM(amount_paise),0)/100.0 FROM consultations WHERE payment_status='paid' AND paid_at IS NOT NULL`, 30),
	})
}
