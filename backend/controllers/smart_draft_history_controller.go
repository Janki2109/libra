package controllers

import (
	"database/sql"
	"net/http"

	"libra/config"
	"libra/utils"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

// Smart Draft had no persistence at all before this: every research query,
// AI Tools result and file analysis lived only in Flutter State and was
// lost on navigating away (confirmed by reading ai_drafting_screen.dart in
// full -- no DioClient call anywhere in it writes to any save endpoint).
// Every handler below scopes strictly to utils.UserID(c), the authenticated
// JWT identity -- never a frontend-supplied id -- matching this feature's
// own "never trust a frontend-provided user_id for authorization" rule.

type smartDraftHistoryItem struct {
	ID           string `json:"id"`
	ThreadID     string `json:"thread_id"`
	Version      int    `json:"version"`
	ActivityType string `json:"activity_type"`
	Title        string `json:"title"`
	CaseID       string `json:"case_id"`
	CaseTitle    string `json:"case_title,omitempty"`
	InputText    string `json:"input_text"`
	OutputText   string `json:"output_text"`
	FileName     string `json:"file_name"`
	MimeType     string `json:"mime_type"`
	HasFile      bool   `json:"has_file"`
	Status       string `json:"status"`
	CreatedAt    string `json:"created_at"`
	UpdatedAt    string `json:"updated_at"`
}

// CreateSmartDraftHistory is called automatically by the frontend right
// after a Smart Draft activity (template draft, AI Tool result, or file
// analysis) succeeds -- never from a manual "Save" button, and never for a
// failed/empty result (the frontend only calls this on a non-empty success
// response; nothing here second-guesses that, but there is also no
// separate "mark as failed" path that would let a failed generation become
// a history row some other way).
func CreateSmartDraftHistory(c *gin.Context) {
	userID := utils.UserID(c)
	firmID := utils.FirmID(c)

	var req struct {
		ActivityType string `json:"activity_type" binding:"required"`
		Title        string `json:"title" binding:"required"`
		CaseID       string `json:"case_id"`
		InputText    string `json:"input_text"`
		OutputText   string `json:"output_text" binding:"required"`
		FileName     string `json:"file_name"`
		FileContent  string `json:"file_content"`
		MimeType     string `json:"mime_type"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}
	switch req.ActivityType {
	case "draft", "tool", "file_analysis", "research":
	default:
		utils.Error(c, http.StatusBadRequest, "Invalid activity_type", "")
		return
	}
	if len(req.FileContent) > maxInlineDocumentBytes {
		utils.Error(c, http.StatusRequestEntityTooLarge, "File too large", "")
		return
	}
	// A case_id is only trusted if it actually belongs to the caller's own
	// firm -- the same rule UploadDocument already enforces for case
	// attachments.
	caseID := req.CaseID
	if caseID != "" && !belongsToFirm(tblCases, caseID, firmID) {
		caseID = ""
	}

	id := uuid.New().String()
	threadID := uuid.New().String() // a brand-new activity starts its own version thread
	_, err := config.DB.Exec(`
		INSERT INTO smart_draft_history
			(id, thread_id, version, user_id, firm_id, activity_type, title,
			 case_id, input_text, output_text, file_name, file_content, mime_type)
		VALUES ($1::uuid, $2::uuid, 1, $3::uuid, $4::uuid, $5, $6, $7, $8, $9, $10, $11, $12)
	`, id, threadID, userID, nullIfEmpty(firmID), req.ActivityType, req.Title,
		nullIfEmpty(caseID), req.InputText, req.OutputText, req.FileName,
		req.FileContent, req.MimeType)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to save history", err.Error())
		return
	}
	utils.Success(c, http.StatusCreated, "Saved to history", gin.H{"id": id, "thread_id": threadID})
}

// GetSmartDraftHistory lists the authenticated lawyer's own activities --
// and only theirs, matching "no history belonging to another Lawyer may be
// visible" -- newest first, one row per thread (its latest version), with
// optional type/search/date filters.
func GetSmartDraftHistory(c *gin.Context) {
	userID := utils.UserID(c)
	activityType := c.Query("type")
	q := c.Query("q")
	from := c.Query("from")
	to := c.Query("to")

	rows, err := config.DB.Query(`
		SELECT DISTINCT ON (h.thread_id)
			h.id, h.thread_id, h.version, h.activity_type, h.title,
			COALESCE(h.case_id::text,''), COALESCE(ca.case_title,''),
			LEFT(h.input_text, 500), LEFT(h.output_text, 500),
			h.file_name, h.mime_type, (h.file_content <> ''),
			h.status, h.created_at::text, h.updated_at::text
		FROM smart_draft_history h
		LEFT JOIN cases ca ON h.case_id = ca.id
		WHERE h.user_id = $1::uuid
		  AND ($2 = '' OR h.activity_type = $2)
		  AND ($3 = '' OR h.title ILIKE '%' || $3 || '%'
		            OR h.input_text ILIKE '%' || $3 || '%'
		            OR h.output_text ILIKE '%' || $3 || '%')
		  AND ($4 = '' OR h.created_at >= $4::date)
		  AND ($5 = '' OR h.created_at < ($5::date + INTERVAL '1 day'))
		ORDER BY h.thread_id, h.version DESC
	`, userID, activityType, q, from, to)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to load history", err.Error())
		return
	}
	defer rows.Close()

	items := []smartDraftHistoryItem{}
	for rows.Next() {
		var it smartDraftHistoryItem
		if err := rows.Scan(&it.ID, &it.ThreadID, &it.Version, &it.ActivityType,
			&it.Title, &it.CaseID, &it.CaseTitle, &it.InputText, &it.OutputText,
			&it.FileName, &it.MimeType, &it.HasFile, &it.Status, &it.CreatedAt,
			&it.UpdatedAt); err != nil {
			utils.Error(c, http.StatusInternalServerError, "Failed to read history", err.Error())
			return
		}
		items = append(items, it)
	}
	// Newest-updated thread first -- DISTINCT ON required ordering by
	// thread_id first, so the final user-facing order is applied here.
	sortHistoryByUpdatedDesc(items)
	utils.Success(c, http.StatusOK, "History fetched", items)
}

func sortHistoryByUpdatedDesc(items []smartDraftHistoryItem) {
	for i := 1; i < len(items); i++ {
		j := i
		for j > 0 && items[j-1].UpdatedAt < items[j].UpdatedAt {
			items[j-1], items[j] = items[j], items[j-1]
			j--
		}
	}
}

// GetSmartDraftHistoryItem returns one version's full (untruncated)
// content, ownership-checked against the authenticated caller.
func GetSmartDraftHistoryItem(c *gin.Context) {
	userID := utils.UserID(c)
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "")
		return
	}
	var it smartDraftHistoryItem
	var fileContent string
	err := config.DB.QueryRow(`
		SELECT h.id, h.thread_id, h.version, h.activity_type, h.title,
		       COALESCE(h.case_id::text,''), COALESCE(ca.case_title,''),
		       h.input_text, h.output_text, h.file_name, h.mime_type,
		       h.file_content, h.status, h.created_at::text, h.updated_at::text
		FROM smart_draft_history h
		LEFT JOIN cases ca ON h.case_id = ca.id
		WHERE h.id = $1::uuid AND h.user_id = $2::uuid
	`, id, userID).Scan(&it.ID, &it.ThreadID, &it.Version, &it.ActivityType,
		&it.Title, &it.CaseID, &it.CaseTitle, &it.InputText, &it.OutputText,
		&it.FileName, &it.MimeType, &fileContent, &it.Status, &it.CreatedAt, &it.UpdatedAt)
	if err == sql.ErrNoRows {
		utils.Error(c, http.StatusNotFound, "History item not found", "")
		return
	}
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to load history item", err.Error())
		return
	}
	it.HasFile = fileContent != ""
	utils.Success(c, http.StatusOK, "History item", gin.H{
		"id": it.ID, "thread_id": it.ThreadID, "version": it.Version,
		"activity_type": it.ActivityType, "title": it.Title,
		"case_id": it.CaseID, "case_title": it.CaseTitle,
		"input_text": it.InputText, "output_text": it.OutputText,
		"file_name": it.FileName, "mime_type": it.MimeType,
		"file_content": fileContent, "status": it.Status,
		"created_at": it.CreatedAt, "updated_at": it.UpdatedAt,
	})
}

// GetSmartDraftHistoryVersions lists every version in one thread, oldest
// first, so the Lawyer can see and open an earlier version -- ownership is
// checked against the caller owning at least the requested version id
// itself; the thread_id it belongs to is then trusted for the rest of the
// listing (every row in a thread is always written with the same user_id
// at creation time, so this can't cross into another lawyer's thread).
func GetSmartDraftHistoryVersions(c *gin.Context) {
	userID := utils.UserID(c)
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "")
		return
	}
	var threadID string
	if err := config.DB.QueryRow(`
		SELECT thread_id::text FROM smart_draft_history WHERE id=$1::uuid AND user_id=$2::uuid
	`, id, userID).Scan(&threadID); err != nil {
		utils.Error(c, http.StatusNotFound, "History item not found", "")
		return
	}
	rows, err := config.DB.Query(`
		SELECT id, version, created_at::text, updated_at::text, LEFT(output_text, 200)
		FROM smart_draft_history
		WHERE thread_id = $1::uuid AND user_id = $2::uuid
		ORDER BY version ASC
	`, threadID, userID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to load versions", err.Error())
		return
	}
	defer rows.Close()
	type v struct {
		ID        string `json:"id"`
		Version   int    `json:"version"`
		CreatedAt string `json:"created_at"`
		UpdatedAt string `json:"updated_at"`
		Preview   string `json:"preview"`
	}
	versions := []v{}
	for rows.Next() {
		var row v
		if err := rows.Scan(&row.ID, &row.Version, &row.CreatedAt, &row.UpdatedAt, &row.Preview); err != nil {
			utils.Error(c, http.StatusInternalServerError, "Failed to read versions", err.Error())
			return
		}
		versions = append(versions, row)
	}
	utils.Success(c, http.StatusOK, "Versions", versions)
}

// UpdateSmartDraftHistory implements "continue editing": rather than
// overwriting the existing row, it inserts a new row in the same
// thread_id with version+1, so the previous content is never destroyed and
// stays reachable via GetSmartDraftHistoryVersions.
func UpdateSmartDraftHistory(c *gin.Context) {
	userID := utils.UserID(c)
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "")
		return
	}
	var req struct {
		OutputText string `json:"output_text" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}

	var threadID, activityType, title, caseID, inputText, fileName, fileContent, mimeType string
	var firmID sql.NullString
	var version int
	err := config.DB.QueryRow(`
		SELECT thread_id::text, version, activity_type, title, COALESCE(case_id::text,''),
		       input_text, file_name, file_content, mime_type, firm_id::text
		FROM smart_draft_history WHERE id=$1::uuid AND user_id=$2::uuid
	`, id, userID).Scan(&threadID, &version, &activityType, &title, &caseID,
		&inputText, &fileName, &fileContent, &mimeType, &firmID)
	if err == sql.ErrNoRows {
		utils.Error(c, http.StatusNotFound, "History item not found", "")
		return
	}
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to update history", err.Error())
		return
	}

	newID := uuid.New().String()
	_, err = config.DB.Exec(`
		INSERT INTO smart_draft_history
			(id, thread_id, version, user_id, firm_id, activity_type, title,
			 case_id, input_text, output_text, file_name, file_content, mime_type)
		VALUES ($1::uuid, $2::uuid, $3, $4::uuid, $5::uuid, $6, $7, $8, $9, $10, $11, $12, $13)
	`, newID, threadID, version+1, userID, nullIfEmptySQL(firmID), activityType, title,
		nullIfEmpty(caseID), inputText, req.OutputText, fileName, fileContent, mimeType)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to update history", err.Error())
		return
	}
	utils.Success(c, http.StatusOK, "New version saved", gin.H{"id": newID, "version": version + 1})
}

// RenameSmartDraftHistory renames every version in the thread (so the
// title stays consistent across "continue editing"), ownership-checked.
func RenameSmartDraftHistory(c *gin.Context) {
	userID := utils.UserID(c)
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "")
		return
	}
	var req struct {
		Title string `json:"title" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}
	var threadID string
	if err := config.DB.QueryRow(`
		SELECT thread_id::text FROM smart_draft_history WHERE id=$1::uuid AND user_id=$2::uuid
	`, id, userID).Scan(&threadID); err != nil {
		utils.Error(c, http.StatusNotFound, "History item not found", "")
		return
	}
	if _, err := config.DB.Exec(`
		UPDATE smart_draft_history SET title=$1, updated_at=now()
		WHERE thread_id=$2::uuid AND user_id=$3::uuid
	`, req.Title, threadID, userID); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to rename", err.Error())
		return
	}
	utils.Success(c, http.StatusOK, "Renamed", nil)
}

// DeleteSmartDraftHistory deletes an entire thread (every version of one
// draft/research/tool activity) in one go -- a lawyer deleting "this
// history item" expects it gone, not just its latest version with older
// versions lingering as orphaned, unreachable rows.
func DeleteSmartDraftHistory(c *gin.Context) {
	userID := utils.UserID(c)
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "")
		return
	}
	var threadID string
	if err := config.DB.QueryRow(`
		SELECT thread_id::text FROM smart_draft_history WHERE id=$1::uuid AND user_id=$2::uuid
	`, id, userID).Scan(&threadID); err != nil {
		utils.Error(c, http.StatusNotFound, "History item not found", "")
		return
	}
	if _, err := config.DB.Exec(`
		DELETE FROM smart_draft_history WHERE thread_id=$1::uuid AND user_id=$2::uuid
	`, threadID, userID); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to delete", err.Error())
		return
	}
	utils.Success(c, http.StatusOK, "Deleted", nil)
}

func nullIfEmptySQL(s sql.NullString) interface{} {
	if !s.Valid || s.String == "" {
		return nil
	}
	return s.String
}
