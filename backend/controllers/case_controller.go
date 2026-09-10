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

func GetCases(c *gin.Context) {
	firmID, ok := utils.RequireFirm(c)
	if !ok {
		return
	}
	// The previous version had a fallback: if the firm-scoped query errored for
	// any reason it re-ran without a WHERE clause and returned the 100 most
	// recent cases across every firm on the platform. A transient database
	// error was enough to leak other firms' case lists.
	//
	// It was also unbounded — a firm with 5,000 matters got all 5,000 rows in
	// one response on every visit to the case list.
	page := ParsePagination(c)

	// Optional filters, applied in SQL rather than by shipping everything to
	// the device and filtering there.
	status := c.Query("status")
	search := c.Query("q")
	clientID := c.Query("client_id")

	rows, err := config.DB.Query(`
		SELECT c.id, COALESCE(c.case_number,''), c.case_title,
		       COALESCE(c.case_type,''), COALESCE(c.court_name,''),
		       COALESCE(c.status,'active'), COALESCE(c.priority,'normal'),
		       COALESCE(cl.name,''), COALESCE(u.name,''), c.created_at
		FROM cases c
		LEFT JOIN clients cl ON c.client_id = cl.id
		LEFT JOIN users u ON c.assigned_lawyer_id = u.id
		WHERE c.firm_id = $1::uuid
		  AND ($2 = '' OR c.status = $2)
		  AND ($3 = '' OR c.case_title ILIKE '%' || $3 || '%'
		               OR c.case_number ILIKE '%' || $3 || '%')
		  AND ($6 = '' OR c.client_id = $6::uuid)
		ORDER BY c.created_at DESC
		LIMIT $4 OFFSET $5
	`, firmID, status, search, page.Limit, page.Offset, clientID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch cases", err.Error())
		return
	}
	defer rows.Close()

	type Case struct {
		ID         string    `json:"id"`
		CaseNumber string    `json:"case_number"`
		CaseTitle  string    `json:"case_title"`
		CaseType   string    `json:"case_type"`
		CourtName  string    `json:"court_name"`
		Status     string    `json:"status"`
		Priority   string    `json:"priority"`
		ClientName string    `json:"client_name"`
		LawyerName string    `json:"lawyer_name"`
		CreatedAt  time.Time `json:"created_at"`
	}

	cases := []Case{}
	for rows.Next() {
		var cs Case
		rows.Scan(&cs.ID, &cs.CaseNumber, &cs.CaseTitle, &cs.CaseType,
			&cs.CourtName, &cs.Status, &cs.Priority,
			&cs.ClientName, &cs.LawyerName, &cs.CreatedAt)
		cases = append(cases, cs)
	}
	utils.SuccessWithMeta(c, http.StatusOK, "Cases fetched", cases, page.Meta(len(cases)))
}

func CreateCase(c *gin.Context) {
	firmID, ok := utils.RequireFirm(c)
	if !ok {
		return
	}
	userID := utils.UserID(c)

	// The plan's max_cases was stored and displayed but never checked.
	if !enforcePlanLimit(c, firmID, limitCases) {
		return
	}

	var req struct {
		ClientID         string `json:"client_id"`
		AssignedLawyerID string `json:"assigned_lawyer_id"`
		CaseNumber       string `json:"case_number"`
		CaseTitle        string `json:"case_title" binding:"required"`
		CaseType         string `json:"case_type"`
		CourtName        string `json:"court_name"`
		CourtLocation    string `json:"court_location"`
		JudgeName        string `json:"judge_name"`
		OppositeParty    string `json:"opposite_party"`
		OppLawyer        string `json:"opposite_lawyer"`
		Priority         string `json:"priority"`
		Description      string `json:"description"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}

	fID := firmID
	uID := userID

	// A caller could previously attach any client id or assign any lawyer id,
	// including rows owned by a different firm, because neither was checked
	// against the caller's tenant.
	if !belongsToFirm(tblClients, req.ClientID, fID) {
		utils.Error(c, http.StatusBadRequest, "Unknown client", "client not in caller's firm")
		return
	}
	if !userInFirm(req.AssignedLawyerID, fID) {
		utils.Error(c, http.StatusBadRequest, "Unknown lawyer", "lawyer not in caller's firm")
		return
	}

	id := uuid.New().String()
	_, err := config.DB.Exec(`
		INSERT INTO cases (id, firm_id, client_id, assigned_lawyer_id, case_number,
		case_title, case_type, court_name, court_location, judge_name,
		opposite_party, opposite_lawyer, priority, description, created_by)
		VALUES ($1, $2::uuid, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15::uuid)
	`, id, fID,
		nullIfEmpty(req.ClientID),
		nullIfEmpty(req.AssignedLawyerID),
		req.CaseNumber, req.CaseTitle, req.CaseType,
		req.CourtName, req.CourtLocation, req.JudgeName,
		req.OppositeParty, req.OppLawyer, req.Priority,
		req.Description, uID)

	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to create case", err.Error())
		return
	}

	// Notify client
	if req.ClientID != "" {
		var clientUserID string
		config.DB.QueryRow(`
			SELECT id FROM users WHERE email=(
				SELECT email FROM clients WHERE id=$1::uuid LIMIT 1
			) AND is_active=true LIMIT 1
		`, req.ClientID).Scan(&clientUserID)

		if clientUserID != "" {
			utils.NotifyWithRef(clientUserID, fID,
				"New Case Filed",
				"Your case '"+req.CaseTitle+"' has been filed. Case No: "+req.CaseNumber,
				"case_update", id, "case")
		}

		timelineID := uuid.New().String()
		config.DB.Exec(`
			INSERT INTO case_timeline (id, case_id, event_type, event_date, title, description, created_by)
			VALUES ($1, $2::uuid, 'case_filed', NOW(), 'Case Filed', $3, $4::uuid)
		`, timelineID, id, "Case '"+req.CaseTitle+"' filed in "+req.CourtName, uID)
	}

	utils.Success(c, http.StatusCreated, "Case created", gin.H{"id": id})
}

func nullableUUID(ns sql.NullString) interface{} {
	if !ns.Valid || ns.String == "" {
		return nil
	}
	return ns.String
}

func GetCase(c *gin.Context) {
	id := c.Param("id")
	firmID, ok := requireFirmResource(c, tblCases, id)
	if !ok {
		return
	}
	var cs struct {
		ID            string    `json:"id"`
		CaseNumber    string    `json:"case_number"`
		CaseTitle     string    `json:"case_title"`
		CaseType      string    `json:"case_type"`
		CourtName     string    `json:"court_name"`
		CourtLocation string    `json:"court_location"`
		JudgeName     string    `json:"judge_name"`
		OppositeParty string    `json:"opposite_party"`
		OppLawyer     string    `json:"opposite_lawyer"`
		Status        string    `json:"status"`
		Priority      string    `json:"priority"`
		Description   string    `json:"description"`
		ClientName    string    `json:"client_name"`
		LawyerName    string    `json:"lawyer_name"`
		WonFeedback   string    `json:"won_feedback"`
		LostReason    string    `json:"lost_reason"`
		ClosedReason  string    `json:"closed_reason"`
		CreatedAt     time.Time `json:"created_at"`
	}
	err := config.DB.QueryRow(`
		SELECT c.id, COALESCE(c.case_number,''), c.case_title,
		       COALESCE(c.case_type,''), COALESCE(c.court_name,''),
		       COALESCE(c.court_location,''), COALESCE(c.judge_name,''),
		       COALESCE(c.opposite_party,''), COALESCE(c.opposite_lawyer,''),
		       COALESCE(c.status,'active'), COALESCE(c.priority,'normal'),
		       COALESCE(c.description,''), COALESCE(cl.name,''),
		       COALESCE(u.name,''),
		       COALESCE(c.won_feedback,''), COALESCE(c.lost_reason,''),
		       COALESCE(c.closed_reason,''), c.created_at
		FROM cases c
		LEFT JOIN clients cl ON c.client_id = cl.id
		LEFT JOIN users u ON c.assigned_lawyer_id = u.id
		WHERE c.id = $1::uuid AND c.firm_id = $2::uuid
	`, id, firmID).Scan(
		&cs.ID, &cs.CaseNumber, &cs.CaseTitle, &cs.CaseType,
		&cs.CourtName, &cs.CourtLocation, &cs.JudgeName,
		&cs.OppositeParty, &cs.OppLawyer,
		&cs.Status, &cs.Priority, &cs.Description,
		&cs.ClientName, &cs.LawyerName,
		&cs.WonFeedback, &cs.LostReason, &cs.ClosedReason,
		&cs.CreatedAt)

	if err == sql.ErrNoRows {
		utils.Error(c, http.StatusNotFound, "Case not found", "")
		return
	}
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Database error", err.Error())
		return
	}
	utils.Success(c, http.StatusOK, "Case fetched", cs)
}

// ✅ FIXED UpdateCase - properly saves status
func UpdateCase(c *gin.Context) {
	id := c.Param("id")
	firmID, ok := requireFirmResource(c, tblCases, id)
	if !ok {
		return
	}

	// A case marked Won is read-only — no further edits to its details and no
	// further status changes. Enforced here, not just by hiding the Edit
	// button in the app, so a direct API call can't bypass it either.
	var currentStatus string
	config.DB.QueryRow(`SELECT status FROM cases WHERE id=$1::uuid AND firm_id=$2::uuid`,
		id, firmID).Scan(&currentStatus)
	if currentStatus == "won" {
		utils.Error(c, http.StatusForbidden,
			"This case is marked Won and is read-only", "cannot edit or change the status of a won case")
		return
	}

	var req struct {
		Status       string `json:"status"`
		WonFeedback  string `json:"won_feedback"`
		LostReason   string `json:"lost_reason"`
		ClosedReason string `json:"closed_reason"`
		CaseTitle    string `json:"case_title"`
		CaseType     string `json:"case_type"`
		CourtName    string `json:"court_name"`
		Priority     string `json:"priority"`
		Description  string `json:"description"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}

	// Reject unknown statuses instead of writing whatever string arrives; the
	// dashboard's counts and the client-facing notification copy both switch on
	// this value.
	if req.Status != "" && !validCaseStatus(req.Status) {
		utils.Error(c, http.StatusBadRequest,
			"Invalid status", "expected one of: active, pending, closed, won, lost, settled")
		return
	}

	var err error

	// Every $N below is explicitly cast to ::text. Postgres has to deduce
	// each parameter's type before it ever sees an argument value, and a
	// placeholder referenced twice in different-looking contexts within one
	// query — $1 as a plain column assignment AND inside a CASE/IN check
	// below, or the same $N used for both the CASE WHEN test and its THEN
	// result in the second query — sometimes gets two different inferred
	// types where an explicit cast would have made it unambiguous. That
	// showed up in production as "inconsistent types deduced for parameter"
	// (42P08), which failed every case edit outright.
	if req.Status != "" {
		_, err = config.DB.Exec(`
			UPDATE cases SET
			status = $1::text,
			won_feedback = CASE WHEN $2::text != '' THEN $2::text ELSE COALESCE(won_feedback,'') END,
			lost_reason = CASE WHEN $3::text != '' THEN $3::text ELSE COALESCE(lost_reason,'') END,
			closed_reason = CASE WHEN $4::text != '' THEN $4::text ELSE COALESCE(closed_reason,'') END,
			closed_at = CASE WHEN $1::text IN ('closed','won','lost','settled')
			                 THEN COALESCE(closed_at, NOW()) ELSE NULL END,
			last_activity_at = NOW(),
			updated_at = NOW()
			WHERE id = $5::uuid AND firm_id = $6::uuid
		`, req.Status, req.WonFeedback, req.LostReason, req.ClosedReason, id, firmID)
	} else {
		_, err = config.DB.Exec(`
			UPDATE cases SET
			case_title = CASE WHEN $1::text != '' THEN $1::text ELSE case_title END,
			case_type = CASE WHEN $2::text != '' THEN $2::text ELSE case_type END,
			court_name = CASE WHEN $3::text != '' THEN $3::text ELSE court_name END,
			priority = CASE WHEN $4::text != '' THEN $4::text ELSE priority END,
			description = CASE WHEN $5::text != '' THEN $5::text ELSE description END,
			last_activity_at = NOW(),
			updated_at = NOW()
			WHERE id = $6::uuid AND firm_id = $7::uuid
		`, req.CaseTitle, req.CaseType, req.CourtName,
			req.Priority, req.Description, id, firmID)
	}

	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to update case", err.Error())
		return
	}

	// ✅ Send notification to client when status changes
	if req.Status != "" {
		var clientID, firmID string
		config.DB.QueryRow(`
			SELECT COALESCE(client_id::text,''), COALESCE(firm_id::text,'')
			FROM cases WHERE id=$1::uuid
		`, id).Scan(&clientID, &firmID)

		if clientID != "" {
			var clientUserID string
			config.DB.QueryRow(`
				SELECT u.id FROM users u
				JOIN clients cl ON lower(u.email) = lower(cl.email)
				WHERE cl.id = $1::uuid AND u.is_active=true LIMIT 1
			`, clientID).Scan(&clientUserID)

			if clientUserID != "" {
				var caseTitle string
				config.DB.QueryRow(
					"SELECT case_title FROM cases WHERE id=$1::uuid", id,
				).Scan(&caseTitle)

				message := ""
				title := "Case Status Updated"
				switch req.Status {
				case "won":
					title = "🏆 Case Won!"
					message = "Great news! Your case '" + caseTitle + "' has been WON!"
					if req.WonFeedback != "" {
						message += "\n\nLawyer's note: " + req.WonFeedback
					}
				case "lost":
					title = "Case Update"
					message = "Your case '" + caseTitle + "' - " + req.LostReason
				case "closed":
					title = "Case Closed"
					message = "Your case '" + caseTitle + "' has been closed."
				case "pending":
					title = "Case Pending"
					message = "Your case '" + caseTitle + "' is now pending."
				case "active":
					title = "Case Active"
					message = "Your case '" + caseTitle + "' is now active."
				}

				if message != "" {
					utils.Notify(clientUserID, firmID, title, message, "case_update")
				}
			}
		}
	}

	utils.Success(c, http.StatusOK, "Case updated successfully", gin.H{
		"status": req.Status,
	})
}

func DeleteCase(c *gin.Context) {
	id := c.Param("id")
	firmID, ok := requireFirmResource(c, tblCases, id)
	if !ok {
		return
	}

	// Same read-only rule as UpdateCase: a Won case cannot be closed/deleted
	// either.
	var currentStatus string
	config.DB.QueryRow(`SELECT status FROM cases WHERE id=$1::uuid AND firm_id=$2::uuid`,
		id, firmID).Scan(&currentStatus)
	if currentStatus == "won" {
		utils.Error(c, http.StatusForbidden,
			"This case is marked Won and is read-only", "cannot delete a won case")
		return
	}

	_, err := config.DB.Exec(`
		UPDATE cases SET status='closed', closed_at=COALESCE(closed_at, NOW()),
		updated_at=NOW()
		WHERE id=$1::uuid AND firm_id=$2::uuid
	`, id, firmID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to close case", err.Error())
		return
	}
	utils.Success(c, http.StatusOK, "Case closed", nil)
}

// validCaseStatus mirrors the values documented on the cases table.
func validCaseStatus(s string) bool {
	switch s {
	case "active", "pending", "closed", "won", "lost", "settled":
		return true
	}
	return false
}

func GetCaseTimeline(c *gin.Context) {
	caseID := c.Param("id")
	if _, ok := requireFirmResource(c, tblCases, caseID); !ok {
		return
	}
	rows, err := config.DB.Query(`
		SELECT id, event_type, event_date, title, COALESCE(description,''), created_at
		FROM case_timeline WHERE case_id=$1::uuid ORDER BY event_date DESC
	`, caseID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch timeline", err.Error())
		return
	}
	defer rows.Close()

	type Event struct {
		ID          string    `json:"id"`
		EventType   string    `json:"event_type"`
		EventDate   time.Time `json:"event_date"`
		Title       string    `json:"title"`
		Description string    `json:"description"`
		CreatedAt   time.Time `json:"created_at"`
	}
	events := []Event{}
	for rows.Next() {
		var e Event
		rows.Scan(&e.ID, &e.EventType, &e.EventDate,
			&e.Title, &e.Description, &e.CreatedAt)
		events = append(events, e)
	}
	utils.Success(c, http.StatusOK, "Timeline fetched", events)
}

func GetCaseHearings(c *gin.Context) {
	caseID := c.Param("id")
	if _, ok := requireFirmResource(c, tblCases, caseID); !ok {
		return
	}
	// next_date/order_summary/remarks/hearing_time are included so the case's
	// Hearings tab can render the same previous-hearing/next-hearing timeline
	// as the hearing details screen, instead of a thinner shape that forced
	// it to guess "next" from raw dates alone.
	rows, err := config.DB.Query(`
		SELECT id, hearing_date::text, COALESCE(hearing_time::text,''),
		COALESCE(court_name,''), COALESCE(purpose,''), status,
		COALESCE(next_date::text,''), COALESCE(order_summary,''), COALESCE(remarks,'')
		FROM hearings WHERE case_id=$1::uuid ORDER BY hearing_date DESC
	`, caseID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch hearings", err.Error())
		return
	}
	defer rows.Close()

	type H struct {
		ID           string `json:"id"`
		HearingDate  string `json:"hearing_date"`
		HearingTime  string `json:"hearing_time"`
		CourtName    string `json:"court_name"`
		Purpose      string `json:"purpose"`
		Status       string `json:"status"`
		NextDate     string `json:"next_date"`
		OrderSummary string `json:"order_summary"`
		Remarks      string `json:"remarks"`
	}
	hearings := []H{}
	for rows.Next() {
		var h H
		if err := rows.Scan(&h.ID, &h.HearingDate, &h.HearingTime, &h.CourtName,
			&h.Purpose, &h.Status, &h.NextDate, &h.OrderSummary, &h.Remarks); err != nil {
			utils.Error(c, http.StatusInternalServerError, "Failed to read hearings", err.Error())
			return
		}
		hearings = append(hearings, h)
	}
	utils.Success(c, http.StatusOK, "Hearings fetched", hearings)
}

func GetCaseNotes(c *gin.Context) {
	caseID := c.Param("id")
	if _, ok := requireFirmResource(c, tblCases, caseID); !ok {
		return
	}

	// Private notes are a lawyer's own working notes. Anyone else on the firm
	// — and in particular a client reading through the portal — must not see
	// them; the previous query returned every note regardless of the flag.
	userID := utils.UserID(c)
	rows, err := config.DB.Query(`
		SELECT cn.id, cn.note, cn.is_private, COALESCE(u.name,''), cn.created_at
		FROM case_notes cn
		LEFT JOIN users u ON cn.created_by = u.id
		WHERE cn.case_id=$1::uuid
		  AND (cn.is_private = false OR cn.created_by = $2::uuid)
		ORDER BY cn.created_at DESC
	`, caseID, userID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch notes", err.Error())
		return
	}
	defer rows.Close()

	type Note struct {
		ID        string    `json:"id"`
		Note      string    `json:"note"`
		IsPrivate bool      `json:"is_private"`
		CreatedBy string    `json:"created_by"`
		CreatedAt time.Time `json:"created_at"`
	}
	notes := []Note{}
	for rows.Next() {
		var n Note
		rows.Scan(&n.ID, &n.Note, &n.IsPrivate, &n.CreatedBy, &n.CreatedAt)
		notes = append(notes, n)
	}
	utils.Success(c, http.StatusOK, "Notes fetched", notes)
}

func AddCaseNote(c *gin.Context) {
	caseID := c.Param("id")
	if _, ok := requireFirmResource(c, tblCases, caseID); !ok {
		return
	}
	userID := utils.UserID(c)
	var req struct {
		Note      string `json:"note" binding:"required"`
		IsPrivate bool   `json:"is_private"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}
	id := uuid.New().String()
	_, err := config.DB.Exec(`
		INSERT INTO case_notes (id, case_id, note, is_private, created_by)
		VALUES ($1, $2::uuid, $3, $4, $5::uuid)
	`, id, caseID, req.Note, req.IsPrivate, userID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to add note", err.Error())
		return
	}
	utils.Success(c, http.StatusCreated, "Note added", gin.H{"id": id})
}
