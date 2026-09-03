package controllers

import (
	"database/sql"
	"libra/config"
	"libra/utils"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

func GetHearings(c *gin.Context) {
	firmID, ok := utils.RequireFirm(c)
	if !ok {
		return
	}

	// The unscoped fallback query is gone — see GetCases for why — and the
	// result set is bounded. A firm accumulates hearings faster than anything
	// else in the schema, so this was the list most likely to grow unusable.
	page := ParsePagination(c)
	status := c.Query("status")
	clientID := c.Query("client_id")

	// Hearings only carry a case_id, not a client_id directly — the join
	// through cases is what lets a client's Details screen show its own
	// hearing history without pulling and filtering every hearing client-side.
	// case_number/client_name are joined in too so the list can identify a
	// hearing without a second round-trip per row.
	rows, err := config.DB.Query(`
		SELECT h.id, h.hearing_date::text, COALESCE(h.hearing_time::text,''),
		       COALESCE(h.court_name,''), COALESCE(h.purpose,''),
		       h.status, COALESCE(cs.case_title,''), COALESCE(cs.case_number,''),
		       COALESCE(cl.name,''), COALESCE(h.next_date::text,'')
		FROM hearings h
		LEFT JOIN cases cs ON h.case_id = cs.id
		LEFT JOIN clients cl ON cs.client_id = cl.id
		WHERE h.firm_id = $1::uuid
		  AND ($2 = '' OR h.status = $2)
		  AND ($5 = '' OR cs.client_id = $5::uuid)
		ORDER BY h.hearing_date DESC
		LIMIT $3 OFFSET $4
	`, firmID, status, page.Limit, page.Offset, clientID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch hearings", err.Error())
		return
	}
	defer rows.Close()

	type Hearing struct {
		ID          string `json:"id"`
		HearingDate string `json:"hearing_date"`
		HearingTime string `json:"hearing_time"`
		CourtName   string `json:"court_name"`
		Purpose     string `json:"purpose"`
		Status      string `json:"status"`
		CaseTitle   string `json:"case_title"`
		CaseNumber  string `json:"case_number"`
		ClientName  string `json:"client_name"`
		NextDate    string `json:"next_date"`
	}
	hearings := []Hearing{}
	for rows.Next() {
		var h Hearing
		if err := rows.Scan(&h.ID, &h.HearingDate, &h.HearingTime,
			&h.CourtName, &h.Purpose, &h.Status, &h.CaseTitle, &h.CaseNumber,
			&h.ClientName, &h.NextDate); err != nil {
			utils.Error(c, http.StatusInternalServerError, "Failed to read hearings", err.Error())
			return
		}
		hearings = append(hearings, h)
	}
	utils.SuccessWithMeta(c, http.StatusOK, "Hearings fetched", hearings, page.Meta(len(hearings)))
}

func GetTodayHearings(c *gin.Context) {
	firmID, ok := utils.RequireFirm(c)
	if !ok {
		return
	}

	// The filter used to read `(h.firm_id = $2::uuid OR true)`. The trailing
	// `OR true` makes the whole condition unconditionally true, so this
	// endpoint returned every firm's hearings for today to any logged-in user.
	today := time.Now().Format("2006-01-02")
	rows, err := config.DB.Query(`
		SELECT h.id, h.hearing_date::text, COALESCE(h.court_name,''),
		       COALESCE(h.purpose,''), h.status, COALESCE(cs.case_title,''),
		       COALESCE(cs.case_number,''), COALESCE(cl.name,''),
		       COALESCE(h.hearing_time::text,'')
		FROM hearings h
		LEFT JOIN cases cs ON h.case_id = cs.id
		LEFT JOIN clients cl ON cs.client_id = cl.id
		WHERE h.hearing_date = $1 AND h.firm_id = $2::uuid
		ORDER BY h.hearing_time NULLS LAST, h.hearing_date
	`, today, firmID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch today hearings", err.Error())
		return
	}
	defer rows.Close()

	type Hearing struct {
		ID          string `json:"id"`
		HearingDate string `json:"hearing_date"`
		CourtName   string `json:"court_name"`
		Purpose     string `json:"purpose"`
		Status      string `json:"status"`
		CaseTitle   string `json:"case_title"`
		CaseNumber  string `json:"case_number"`
		ClientName  string `json:"client_name"`
		HearingTime string `json:"hearing_time"`
	}
	hearings := []Hearing{}
	for rows.Next() {
		var h Hearing
		if err := rows.Scan(&h.ID, &h.HearingDate, &h.CourtName,
			&h.Purpose, &h.Status, &h.CaseTitle, &h.CaseNumber, &h.ClientName,
			&h.HearingTime); err != nil {
			utils.Error(c, http.StatusInternalServerError, "Failed to read hearings", err.Error())
			return
		}
		hearings = append(hearings, h)
	}
	utils.Success(c, http.StatusOK, "Today hearings fetched", hearings)
}

func CreateHearing(c *gin.Context) {
	firmID, ok := utils.RequireFirm(c)
	if !ok {
		return
	}
	uID := utils.UserID(c)

	var req struct {
		CaseID      string `json:"case_id"`
		HearingDate string `json:"hearing_date" binding:"required"`
		HearingTime string `json:"hearing_time"`
		CourtName   string `json:"court_name"`
		CourtRoom   string `json:"court_room"`
		JudgeName   string `json:"judge_name"`
		Purpose     string `json:"purpose"`
		Notes       string `json:"notes"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}

	// A hearing could previously be attached to another firm's case.
	if !belongsToFirm(tblCases, req.CaseID, firmID) {
		utils.Error(c, http.StatusBadRequest, "Unknown case", "case not in caller's firm")
		return
	}

	id := uuid.New().String()
	_, err := config.DB.Exec(`
		INSERT INTO hearings (id, case_id, firm_id, hearing_date, hearing_time,
		court_name, court_room, judge_name, purpose, notes, created_by)
		VALUES ($1, $2, $3::uuid, $4, $5, $6, $7, $8, $9, $10, $11::uuid)
	`, id, nullIfEmpty(req.CaseID), firmID, req.HearingDate, nullIfEmpty(req.HearingTime),
		req.CourtName, req.CourtRoom, req.JudgeName,
		req.Purpose, req.Notes, uID)

	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to create hearing", err.Error())
		return
	}
	utils.Success(c, http.StatusCreated, "Hearing created", gin.H{"id": id})
}

func GetHearing(c *gin.Context) {
	id := c.Param("id")
	firmID, ok := requireFirmResource(c, tblHearings, id)
	if !ok {
		return
	}

	var h struct {
		ID           string `json:"id"`
		CaseID       string `json:"case_id"`
		CaseTitle    string `json:"case_title"`
		CaseNumber   string `json:"case_number"`
		ClientName   string `json:"client_name"`
		HearingDate  string `json:"hearing_date"`
		HearingTime  string `json:"hearing_time"`
		CourtName    string `json:"court_name"`
		CourtRoom    string `json:"court_room"`
		JudgeName    string `json:"judge_name"`
		Purpose      string `json:"purpose"`
		Notes        string `json:"notes"`
		Status       string `json:"status"`
		NextDate     string `json:"next_date"`
		OrderSummary string `json:"order_summary"`
		Remarks      string `json:"remarks"`
	}
	// order_summary/remarks were previously left out here even though the
	// "Update After Hearing" sheet collects them — a saved value would never
	// come back on refresh. case_title/case_number/client_name let the
	// details screen identify the matter without a second round-trip.
	err := config.DB.QueryRow(`
		SELECT h.id, COALESCE(h.case_id::text,''), COALESCE(cs.case_title,''),
		       COALESCE(cs.case_number,''), COALESCE(cl.name,''),
		       h.hearing_date::text, COALESCE(h.hearing_time::text,''),
		       COALESCE(h.court_name,''), COALESCE(h.court_room,''),
		       COALESCE(h.judge_name,''), COALESCE(h.purpose,''),
		       COALESCE(h.notes,''), h.status, COALESCE(h.next_date::text,''),
		       COALESCE(h.order_summary,''), COALESCE(h.remarks,'')
		FROM hearings h
		LEFT JOIN cases cs ON h.case_id = cs.id
		LEFT JOIN clients cl ON cs.client_id = cl.id
		WHERE h.id=$1::uuid AND h.firm_id=$2::uuid
	`, id, firmID).Scan(&h.ID, &h.CaseID, &h.CaseTitle, &h.CaseNumber, &h.ClientName,
		&h.HearingDate, &h.HearingTime,
		&h.CourtName, &h.CourtRoom, &h.JudgeName,
		&h.Purpose, &h.Notes, &h.Status, &h.NextDate,
		&h.OrderSummary, &h.Remarks)

	if err == sql.ErrNoRows {
		utils.Error(c, http.StatusNotFound, "Hearing not found", "")
		return
	}
	// A non-ErrNoRows failure used to fall through and return a zero-valued
	// hearing with a 200.
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Database error", err.Error())
		return
	}
	utils.Success(c, http.StatusOK, "Hearing fetched", h)
}

func UpdateHearing(c *gin.Context) {
	id := c.Param("id")
	firmID, ok := requireFirmResource(c, tblHearings, id)
	if !ok {
		return
	}

	var req struct {
		Status       string `json:"status"`
		Notes        string `json:"notes"`
		NextDate     string `json:"next_date"`
		Purpose      string `json:"purpose"`
		OrderSummary string `json:"order_summary"`
		Remarks      string `json:"remarks"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}
	if req.Status != "" && !validHearingStatus[req.Status] {
		utils.Error(c, http.StatusBadRequest, "Invalid status",
			"expected one of: scheduled, completed, adjourned, cancelled")
		return
	}

	// Same partial-update problem as clients: omitted fields used to be
	// overwritten with empty strings, wiping a hearing's notes whenever the
	// app sent only a status change. order_summary/remarks were previously
	// dropped entirely — the "Update After Hearing" sheet has always sent
	// them, but nothing here read them off the request, so they never
	// reached the database.
	_, err := config.DB.Exec(`
		UPDATE hearings SET
		  status        = CASE WHEN $1 != '' THEN $1 ELSE status END,
		  notes         = CASE WHEN $2 != '' THEN $2 ELSE notes END,
		  next_date     = COALESCE($3::date, next_date),
		  purpose       = CASE WHEN $4 != '' THEN $4 ELSE purpose END,
		  order_summary = CASE WHEN $5 != '' THEN $5 ELSE order_summary END,
		  remarks       = CASE WHEN $6 != '' THEN $6 ELSE remarks END,
		  updated_at    = NOW()
		WHERE id=$7::uuid AND firm_id=$8::uuid
	`, req.Status, req.Notes, nullIfEmpty(req.NextDate), req.Purpose,
		req.OrderSummary, req.Remarks, id, firmID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to update hearing", err.Error())
		return
	}
	utils.Success(c, http.StatusOK, "Hearing updated", nil)
}

var validHearingStatus = map[string]bool{
	"scheduled": true, "completed": true, "adjourned": true, "cancelled": true,
}

func DeleteHearing(c *gin.Context) {
	id := c.Param("id")
	firmID, ok := requireFirmResource(c, tblHearings, id)
	if !ok {
		return
	}
	_, err := config.DB.Exec(
		"UPDATE hearings SET status='cancelled', updated_at=NOW() WHERE id=$1::uuid AND firm_id=$2::uuid",
		id, firmID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to cancel hearing", err.Error())
		return
	}
	utils.Success(c, http.StatusOK, "Hearing cancelled", nil)
}
