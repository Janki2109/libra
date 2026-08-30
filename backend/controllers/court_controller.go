package controllers

import (
	"database/sql"
	"encoding/json"
	"errors"
	"libra/config"
	"libra/services"
	"libra/utils"
	"log"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

// courtCacheTTL is how long a fetched case status stays authoritative.
//
// Court records change at most once per hearing, and the free upstreams are
// rate limited, so re-fetching on every screen open would burn the quota
// within a day of real use.
const courtCacheTTL = 6 * time.Hour

// ─── CASE STATUS BY CNR ──────────────────────
// GET /court/case-status?cnr=MHAU010012342024
//
// This is the endpoint the app needs to answer "what happened in my case".
// There was no such handler before: GetCauseList returned a hardcoded empty
// list plus a message telling the user to go and visit ecourtsClient().gov.in
// themselves.
func GetCaseStatus(c *gin.Context) {
	if _, ok := utils.RequireFirm(c); !ok {
		return
	}

	cnr := services.NormalizeCNR(c.Query("cnr"))
	if cnr == "" {
		utils.Error(c, http.StatusBadRequest, "cnr is required",
			"pass the 16-character CNR printed on the case record")
		return
	}
	if err := services.ValidateCNR(cnr); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid CNR", err.Error())
		return
	}

	// Serve a recent cached copy before going upstream.
	if c.Query("refresh") != "true" {
		if cached, ok := readCachedCaseStatus(cnr); ok {
			utils.Success(c, http.StatusOK, "Case status fetched", cached)
			return
		}
	}

	if !ecourtsClient().Configured() {
		utils.Error(c, http.StatusServiceUnavailable,
			"Court data source is not configured",
			"set ECOURTS_API_BASE (see docs/court-data.md)")
		return
	}

	status, err := ecourtsClient().CaseStatusByCNR(c.Request.Context(), cnr)
	if err != nil {
		// Fall back to a stale cached copy rather than showing nothing — a
		// lawyer checking a hearing date is better served by last week's
		// record, clearly labelled, than by an error page.
		if cached, ok := readAnyCachedCaseStatus(cnr); ok {
			cached.AttributionNote += " (upstream unavailable; showing last known record)"
			utils.Success(c, http.StatusOK, "Case status fetched from cache", cached)
			return
		}
		switch {
		case errors.Is(err, services.ErrNotFound):
			utils.Error(c, http.StatusNotFound, "No court record found for that CNR", "")
		case errors.Is(err, services.ErrCourtDataUnavailable):
			utils.Error(c, http.StatusServiceUnavailable,
				"Court data source is not configured", err.Error())
		default:
			utils.Error(c, http.StatusBadGateway,
				"Could not reach the court data source", err.Error())
		}
		return
	}

	cacheCaseStatus(cnr, status)
	utils.Success(c, http.StatusOK, "Case status fetched", status)
}

// ─── SYNC A TRACKED CASE ─────────────────────
// POST /court/cases/:id/sync
//
// Pulls the latest record for a case the firm already tracks and writes the
// next listed date back onto it.
func SyncCaseFromCourt(c *gin.Context) {
	caseID := c.Param("id")
	firmID, ok := requireFirmResource(c, tblCases, caseID)
	if !ok {
		return
	}

	var cnr sql.NullString
	if err := config.DB.QueryRow(
		`SELECT cnr_number FROM cases WHERE id=$1::uuid AND firm_id=$2::uuid`,
		caseID, firmID,
	).Scan(&cnr); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to read case", err.Error())
		return
	}
	if !cnr.Valid || cnr.String == "" {
		utils.Error(c, http.StatusBadRequest, "This case has no CNR number",
			"add the CNR to the case before syncing")
		return
	}

	if !ecourtsClient().Configured() {
		utils.Error(c, http.StatusServiceUnavailable,
			"Court data source is not configured",
			"set ECOURTS_API_BASE (see docs/court-data.md)")
		return
	}

	status, err := ecourtsClient().CaseStatusByCNR(c.Request.Context(), cnr.String)
	if err != nil {
		utils.Error(c, http.StatusBadGateway,
			"Could not reach the court data source", err.Error())
		return
	}

	cacheCaseStatus(services.NormalizeCNR(cnr.String), status)

	// Only fill fields the firm has left blank — a lawyer's own entry beats a
	// fetched one.
	_, err = config.DB.Exec(`
		UPDATE cases SET
		  court_name = CASE WHEN COALESCE(court_name,'') = '' THEN $1 ELSE court_name END,
		  judge_name = CASE WHEN COALESCE(judge_name,'') = '' THEN $2 ELSE judge_name END,
		  last_activity_at = NOW(),
		  updated_at = NOW()
		WHERE id=$3::uuid AND firm_id=$4::uuid
	`, status.CourtName, status.JudgeName, caseID, firmID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to update case", err.Error())
		return
	}

	// Record the next listed date as a hearing if it is not already there.
	if status.NextHearing != "" {
		if _, err := config.DB.Exec(`
			INSERT INTO hearings (id, case_id, firm_id, hearing_date, court_name,
			judge_name, purpose, status)
			SELECT gen_random_uuid(), $1::uuid, $2::uuid, $3::date, $4, $5, $6, 'scheduled'
			WHERE NOT EXISTS (
				SELECT 1 FROM hearings
				WHERE case_id=$1::uuid AND hearing_date=$3::date
			)
		`, caseID, firmID, status.NextHearing, status.CourtName,
			status.JudgeName, status.Stage); err != nil {
			log.Printf("[court] could not record synced hearing: %v", err)
		}
	}

	utils.Success(c, http.StatusOK, "Case synced from court records", status)
}

// ─── CAUSE LIST ──────────────────────────────
// GET /court/cause-list?state=&district=&court_complex=&date=
func GetCauseList(c *gin.Context) {
	if _, ok := utils.RequireFirm(c); !ok {
		return
	}

	date := c.Query("date")
	if date == "" {
		date = time.Now().Format("2006-01-02")
	}
	if _, err := time.Parse("2006-01-02", date); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid date", "expected YYYY-MM-DD")
		return
	}

	state := c.Query("state")
	district := c.Query("district")
	complexName := c.Query("court_complex")

	if !ecourtsClient().Configured() {
		utils.Error(c, http.StatusServiceUnavailable,
			"Court data source is not configured",
			"set ECOURTS_API_BASE (see docs/court-data.md)")
		return
	}
	if state == "" || district == "" {
		utils.Error(c, http.StatusBadRequest, "state and district are required", "")
		return
	}

	entries, err := ecourtsClient().CauseList(c.Request.Context(), state, district, complexName, date)
	if err != nil {
		utils.Error(c, http.StatusBadGateway, "Could not fetch the cause list", err.Error())
		return
	}

	utils.Success(c, http.StatusOK, "Cause list fetched", gin.H{
		"date":          date,
		"state":         state,
		"district":      district,
		"court_complex": complexName,
		"count":         len(entries),
		"cases":         entries,
		"source":        "eCourts / NJDG, Department of Justice, Government of India",
	})
}

// ─── COURT HOLIDAYS ──────────────────────────
func GetCourtHolidays(c *gin.Context) {
	year := time.Now().Year()

	// Holidays are notified per High Court and change every year, so they are
	// data rather than code. The previous handler hardcoded a single year's
	// list and re-inserted all eleven rows into court_data on every call —
	// its `ON CONFLICT DO NOTHING` had no unique constraint to conflict on,
	// so the table grew by eleven rows per request.
	rows, err := config.DB.Query(`
		SELECT record_date::text, COALESCE(court_name,''), COALESCE(case_status,'')
		FROM court_data
		WHERE record_type = 'holiday'
		  AND EXTRACT(YEAR FROM record_date) = $1
		ORDER BY record_date
	`, year)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch holidays", err.Error())
		return
	}
	defer rows.Close()

	type Holiday struct {
		Date  string `json:"date"`
		Court string `json:"court"`
		Name  string `json:"name"`
	}
	holidays := []Holiday{}
	for rows.Next() {
		var h Holiday
		if err := rows.Scan(&h.Date, &h.Court, &h.Name); err != nil {
			utils.Error(c, http.StatusInternalServerError, "Failed to read holidays", err.Error())
			return
		}
		holidays = append(holidays, h)
	}

	utils.Success(c, http.StatusOK, "Court holidays fetched", gin.H{
		"year":     year,
		"holidays": holidays,
		"note": "Holiday lists are notified separately by each High Court. " +
			"Load your jurisdiction's list via POST /court/holidays.",
	})
}

// UpsertCourtHolidays loads a year's holiday list. Firm admins maintain the
// list for the court they practise in.
// POST /court/holidays
func UpsertCourtHolidays(c *gin.Context) {
	if _, ok := utils.RequireFirm(c); !ok {
		return
	}
	if !utils.IsAdmin(c) {
		utils.Error(c, http.StatusForbidden, "Only a firm admin can load holidays", "")
		return
	}

	var req struct {
		Court    string `json:"court" binding:"required"`
		Holidays []struct {
			Date string `json:"date" binding:"required"`
			Name string `json:"name" binding:"required"`
		} `json:"holidays" binding:"required,min=1,dive"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}

	tx, err := config.DB.Begin()
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to save holidays", err.Error())
		return
	}
	defer tx.Rollback()

	for _, h := range req.Holidays {
		if _, err := time.Parse("2006-01-02", h.Date); err != nil {
			utils.Error(c, http.StatusBadRequest,
				"Invalid holiday date "+h.Date, "expected YYYY-MM-DD")
			return
		}
		if _, err := tx.Exec(`
			INSERT INTO court_data (id, record_type, record_date, court_name, case_status, source, fetched_at)
			VALUES (gen_random_uuid(), 'holiday', $1::date, $2, $3, 'manual', NOW())
			ON CONFLICT (record_type, record_date) WHERE record_type = 'holiday'
			DO UPDATE SET court_name  = EXCLUDED.court_name,
			              case_status = EXCLUDED.case_status,
			              fetched_at  = NOW()
		`, h.Date, req.Court, h.Name); err != nil {
			utils.Error(c, http.StatusInternalServerError, "Failed to save holidays", err.Error())
			return
		}
	}

	if err := tx.Commit(); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to save holidays", err.Error())
		return
	}

	utils.Success(c, http.StatusOK, "Court holidays saved", gin.H{"count": len(req.Holidays)})
}

// ─── CACHE ───────────────────────────────────

func cacheCaseStatus(cnr string, status *services.CaseStatus) {
	payload, err := json.Marshal(status)
	if err != nil {
		log.Printf("[court] could not encode case status for cache: %v", err)
		return
	}

	var nextHearing interface{}
	if status.NextHearing != "" {
		nextHearing = status.NextHearing
	}

	if _, err := config.DB.Exec(`
		INSERT INTO court_data (id, record_type, cnr_number, court_case_number,
		court_name, case_status, next_hearing_date, payload, source, fetched_at)
		VALUES (gen_random_uuid(), 'case_status', $1, $2, $3, $4, $5::date, $6, $7, NOW())
		ON CONFLICT (cnr_number) WHERE cnr_number IS NOT NULL AND record_type = 'case_status'
		DO UPDATE SET court_case_number = EXCLUDED.court_case_number,
		              court_name        = EXCLUDED.court_name,
		              case_status       = EXCLUDED.case_status,
		              next_hearing_date = EXCLUDED.next_hearing_date,
		              payload           = EXCLUDED.payload,
		              fetched_at        = NOW()
	`, cnr, status.CaseNumber, status.CourtName, status.Status,
		nextHearing, payload, status.Source); err != nil {
		log.Printf("[court] could not cache case status: %v", err)
	}
}

// readCachedCaseStatus returns a copy fetched within courtCacheTTL.
func readCachedCaseStatus(cnr string) (*services.CaseStatus, bool) {
	return readCachedCaseStatusSince(cnr, time.Now().Add(-courtCacheTTL))
}

// readAnyCachedCaseStatus returns the cached copy regardless of age. Used only
// when the upstream is unreachable.
func readAnyCachedCaseStatus(cnr string) (*services.CaseStatus, bool) {
	return readCachedCaseStatusSince(cnr, time.Time{})
}

func readCachedCaseStatusSince(cnr string, notBefore time.Time) (*services.CaseStatus, bool) {
	var payload []byte
	var fetchedAt time.Time
	err := config.DB.QueryRow(`
		SELECT payload, fetched_at FROM court_data
		WHERE record_type='case_status' AND cnr_number=$1 AND payload IS NOT NULL
	`, cnr).Scan(&payload, &fetchedAt)
	if err != nil || len(payload) == 0 {
		return nil, false
	}
	if !notBefore.IsZero() && fetchedAt.Before(notBefore) {
		return nil, false
	}

	var status services.CaseStatus
	if err := json.Unmarshal(payload, &status); err != nil {
		return nil, false
	}
	status.FromCache = true
	status.FetchedAt = fetchedAt
	return &status, true
}
