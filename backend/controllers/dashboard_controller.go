package controllers

import (
	"libra/config"
	"libra/utils"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

// GET /dashboard — unified stats for lawyer panel
func GetDashboard(c *gin.Context) {
	// The unchecked `.(string)` assertions here panicked — and returned a 500
	// for the whole dashboard — whenever a user without a firm (a client or a
	// law student) opened the app.
	fID, ok := utils.RequireFirm(c)
	if !ok {
		return
	}
	uID := utils.UserID(c)
	today := time.Now().Format("2006-01-02")

	// Every count below used to carry either `OR created_by=$2` or a literal
	// `OR true`, both of which pull in other firms' rows. `OR true` in
	// particular made the hearing counts a platform-wide total.
	var totalClients, activeCases, totalCases, pendingInvoices, todayHearings int
	var pendingCases, wonCases, lostCases int
	var pendingAmount, totalRevenue, monthlyRevenue float64

	config.DB.QueryRow(`
		SELECT COUNT(*) FROM clients
		WHERE firm_id=$1::uuid AND is_active=true
	`, fID).Scan(&totalClients)

	// The app was deriving won/lost counts client-side by pulling the entire
	// case list; they belong in the same aggregate as the rest.
	config.DB.QueryRow(`
		SELECT COUNT(*) FILTER (WHERE status='active'),
		       COUNT(*) FILTER (WHERE status='pending'),
		       COUNT(*) FILTER (WHERE status='won'),
		       COUNT(*) FILTER (WHERE status='lost'),
		       COUNT(*)
		FROM cases WHERE firm_id=$1::uuid
	`, fID).Scan(&activeCases, &pendingCases, &wonCases, &lostCases, &totalCases)

	config.DB.QueryRow(`
		SELECT COUNT(*), COALESCE(SUM(total_amount - COALESCE(paid_amount,0)), 0)
		FROM invoices
		WHERE firm_id=$1::uuid
		  AND status IN ('unpaid','partial','overdue','pending_verification')
	`, fID).Scan(&pendingInvoices, &pendingAmount)

	config.DB.QueryRow(`
		SELECT COUNT(*) FROM hearings h
		WHERE h.hearing_date = $1
		  AND h.firm_id=$2::uuid
		  AND h.status != 'cancelled'
	`, today, fID).Scan(&todayHearings)

	config.DB.QueryRow(`
		SELECT COALESCE(SUM(paid_amount), 0) FROM invoices
		WHERE firm_id=$1::uuid
	`, fID).Scan(&totalRevenue)

	config.DB.QueryRow(`
		SELECT COALESCE(SUM(amount), 0) FROM payments
		WHERE firm_id=$1::uuid
		  AND DATE_TRUNC('month', payment_date) = DATE_TRUNC('month', CURRENT_DATE)
	`, fID).Scan(&monthlyRevenue)

	// ── today hearings list ───────────────────
	type HearingRow struct {
		ID          string `json:"id"`
		HearingDate string `json:"hearing_date"`
		CourtName   string `json:"court_name"`
		Purpose     string `json:"purpose"`
		Status      string `json:"status"`
		CaseTitle   string `json:"case_title"`
	}
	todayRows, _ := config.DB.Query(`
		SELECT h.id, h.hearing_date::text,
		       COALESCE(h.court_name,''), COALESCE(h.purpose,''),
		       h.status, COALESCE(cs.case_title,'')
		FROM hearings h
		LEFT JOIN cases cs ON h.case_id = cs.id
		WHERE h.hearing_date = $1 AND h.firm_id=$2::uuid
		  AND h.status != 'cancelled'
		ORDER BY h.hearing_time NULLS LAST
	`, today, fID)

	todayHearingsList := []HearingRow{}
	if todayRows != nil {
		defer todayRows.Close()
		for todayRows.Next() {
			var h HearingRow
			todayRows.Scan(&h.ID, &h.HearingDate, &h.CourtName,
				&h.Purpose, &h.Status, &h.CaseTitle)
			todayHearingsList = append(todayHearingsList, h)
		}
	}

	// ── upcoming hearings (next 7 days) ───────
	type UpcomingRow struct {
		ID          string `json:"id"`
		HearingDate string `json:"hearing_date"`
		CourtName   string `json:"court_name"`
		CaseTitle   string `json:"case_title"`
		Status      string `json:"status"`
	}
	nextWeek := time.Now().AddDate(0, 0, 7).Format("2006-01-02")
	upcomingRows, _ := config.DB.Query(`
		SELECT h.id, h.hearing_date::text,
		       COALESCE(h.court_name,''), COALESCE(cs.case_title,''), h.status
		FROM hearings h
		LEFT JOIN cases cs ON h.case_id = cs.id
		WHERE h.hearing_date BETWEEN $1 AND $2
		  AND h.firm_id=$3::uuid
		  AND h.status='scheduled'
		ORDER BY h.hearing_date ASC LIMIT 10
	`, today, nextWeek, fID)

	upcomingList := []UpcomingRow{}
	if upcomingRows != nil {
		defer upcomingRows.Close()
		for upcomingRows.Next() {
			var u UpcomingRow
			upcomingRows.Scan(&u.ID, &u.HearingDate,
				&u.CourtName, &u.CaseTitle, &u.Status)
			upcomingList = append(upcomingList, u)
		}
	}

	// ── recent cases ─────────────────────────
	type CaseRow struct {
		ID         string    `json:"id"`
		CaseNumber string    `json:"case_number"`
		CaseTitle  string    `json:"case_title"`
		Status     string    `json:"status"`
		Priority   string    `json:"priority"`
		ClientName string    `json:"client_name"`
		CreatedAt  time.Time `json:"created_at"`
	}
	caseRows, _ := config.DB.Query(`
		SELECT c.id, COALESCE(c.case_number,''), c.case_title,
		       COALESCE(c.status,'active'), COALESCE(c.priority,'normal'),
		       COALESCE(cl.name,''), c.created_at
		FROM cases c
		LEFT JOIN clients cl ON c.client_id = cl.id
		WHERE c.firm_id=$1::uuid
		ORDER BY c.created_at DESC LIMIT 5
	`, fID)

	recentCases := []CaseRow{}
	if caseRows != nil {
		defer caseRows.Close()
		for caseRows.Next() {
			var cr CaseRow
			caseRows.Scan(&cr.ID, &cr.CaseNumber, &cr.CaseTitle,
				&cr.Status, &cr.Priority, &cr.ClientName, &cr.CreatedAt)
			recentCases = append(recentCases, cr)
		}
	}

	// ── recent activities (notifications) ────
	type Activity struct {
		ID        string    `json:"id"`
		Title     string    `json:"title"`
		Message   string    `json:"message"`
		Type      string    `json:"type"`
		CreatedAt time.Time `json:"created_at"`
	}
	actRows, _ := config.DB.Query(`
		SELECT id, title, COALESCE(message,''), COALESCE(type,'general'), created_at
		FROM notifications
		WHERE user_id=$1::uuid
		ORDER BY created_at DESC LIMIT 10
	`, uID)

	activities := []Activity{}
	if actRows != nil {
		defer actRows.Close()
		for actRows.Next() {
			var a Activity
			actRows.Scan(&a.ID, &a.Title, &a.Message, &a.Type, &a.CreatedAt)
			activities = append(activities, a)
		}
	}

	// ── monthly revenue chart (last 6 months) ─
	type MonthlyData struct {
		Month   string  `json:"month"`
		Revenue float64 `json:"revenue"`
	}
	monthRows, _ := config.DB.Query(`
		SELECT TO_CHAR(DATE_TRUNC('month', payment_date), 'Mon YYYY') AS month,
		       COALESCE(SUM(amount), 0)
		FROM payments
		WHERE firm_id=$1::uuid
		  AND payment_date >= CURRENT_DATE - INTERVAL '6 months'
		GROUP BY DATE_TRUNC('month', payment_date)
		ORDER BY DATE_TRUNC('month', payment_date) ASC
	`, fID)

	monthlyChart := []MonthlyData{}
	if monthRows != nil {
		defer monthRows.Close()
		for monthRows.Next() {
			var m MonthlyData
			monthRows.Scan(&m.Month, &m.Revenue)
			monthlyChart = append(monthlyChart, m)
		}
	}

	utils.Success(c, http.StatusOK, "Dashboard fetched", gin.H{
		"stats": gin.H{
			"total_clients":    totalClients,
			"active_cases":     activeCases,
			"pending_cases":    pendingCases,
			"won_cases":        wonCases,
			"lost_cases":       lostCases,
			"total_cases":      totalCases,
			"today_hearings":   todayHearings,
			"pending_invoices": pendingInvoices,
			"pending_amount":   pendingAmount,
			"total_revenue":    totalRevenue,
			"monthly_revenue":  monthlyRevenue,
		},
		"today_hearings":    todayHearingsList,
		"upcoming_hearings": upcomingList,
		"recent_cases":      recentCases,
		"recent_activities": activities,
		"monthly_chart":     monthlyChart,
	})
}
