package controllers

import (
	"database/sql"
	"fmt"
	"libra/config"
	"libra/utils"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/lib/pq"
)

// ─── NOTIFICATIONS CENTER (Super Admin only) ────────────────────────────
//
// Reuses the existing notifications table (every user's real in-app inbox)
// and utils.SendPushToUserTracked (utils/push.go) — the same Firebase Admin
// SDK client every other push in this app uses. notification_batches
// (migration 031) is the one new thing: a record of one Super Admin send/
// schedule action, with notifications.batch_id linking back to it so a
// batch's real per-recipient outcome is always derivable from rows that
// already exist for an entirely different reason (the user's own inbox).

// notificationAudienceRole maps a batch's target_type to the real stored
// role name — never "admin"; "everyone"/"selected" have no single role.
func notificationAudienceRole(targetType string) string {
	switch targetType {
	case "client":
		return "client"
	case "lawyer":
		return "lawyer"
	case "student":
		return "law_student"
	default:
		return ""
	}
}

// resolveRecipients returns the real user ids (and whether push is enabled
// for each) a batch's target_type/target_user_ids actually match — the
// server always re-derives this itself rather than trusting a frontend-
// picked list beyond which uuids were selected for 'selected'.
func resolveRecipients(targetType string, selectedIDs []string) ([]struct{ ID string }, error) {
	var rows *sql.Rows
	var err error
	switch targetType {
	case "everyone":
		rows, err = config.DB.Query(`
			SELECT u.id FROM users u JOIN roles r ON u.role_id = r.id
			WHERE r.name IN ('client','lawyer','law_student') AND u.is_active = true
		`)
	case "client", "lawyer", "student":
		rows, err = config.DB.Query(`
			SELECT u.id FROM users u JOIN roles r ON u.role_id = r.id
			WHERE r.name = $1 AND u.is_active = true
		`, notificationAudienceRole(targetType))
	case "selected":
		if len(selectedIDs) == 0 {
			return nil, nil
		}
		rows, err = config.DB.Query(`
			SELECT u.id FROM users u JOIN roles r ON u.role_id = r.id
			WHERE u.id = ANY($1) AND r.name != 'super_admin' AND u.is_active = true
		`, pq.Array(selectedIDs))
	default:
		return nil, fmt.Errorf("invalid target_type")
	}
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []struct{ ID string }
	for rows.Next() {
		var id string
		if rows.Scan(&id) == nil {
			out = append(out, struct{ ID string }{ID: id})
		}
	}
	return out, nil
}

// AdminEstimateNotificationRecipients - GET /admin/notifications-center/estimate?target_type=&user_ids=a,b,c
func AdminEstimateNotificationRecipients(c *gin.Context) {
	targetType := c.Query("target_type")
	var selected []string
	if raw := c.Query("user_ids"); raw != "" {
		selected = splitCommaUUIDs(raw)
	}
	recipients, err := resolveRecipients(targetType, selected)
	if err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid target audience", err.Error())
		return
	}
	utils.Success(c, http.StatusOK, "Estimate calculated", gin.H{"estimated_recipients": len(recipients)})
}

func splitCommaUUIDs(raw string) []string {
	var out []string
	start := 0
	for i := 0; i <= len(raw); i++ {
		if i == len(raw) || raw[i] == ',' {
			if i > start {
				s := raw[start:i]
				if isUUID(s) {
					out = append(out, s)
				}
			}
			start = i + 1
		}
	}
	return out
}

// AdminGetNotificationCenterStats - GET /admin/notifications-center/stats
func AdminGetNotificationCenterStats(c *gin.Context) {
	var out struct {
		Total     int `json:"total_notifications"`
		SentToday int `json:"sent_today"`
		Scheduled int `json:"scheduled"`
		Delivered int `json:"delivered"`
		Failed    int `json:"failed"`
	}
	config.DB.QueryRow(`SELECT COUNT(*) FROM notification_batches`).Scan(&out.Total)
	config.DB.QueryRow(`
		SELECT COUNT(*) FROM notification_batches WHERE sent_at >= CURRENT_DATE
	`).Scan(&out.SentToday)
	config.DB.QueryRow(`SELECT COUNT(*) FROM notification_batches WHERE status='scheduled'`).Scan(&out.Scheduled)
	// "Delivered" here means "push accepted by FCM" (see push_status='sent')
	// — the Admin SDK gives no true on-device delivery receipt, so this is
	// the most honest real number available rather than a fabricated one.
	config.DB.QueryRow(`SELECT COALESCE(SUM(sent_count),0) FROM notification_batches`).Scan(&out.Delivered)
	config.DB.QueryRow(`SELECT COALESCE(SUM(failed_count),0) FROM notification_batches`).Scan(&out.Failed)
	utils.Success(c, http.StatusOK, "Notification stats fetched", out)
}

// AdminGetNotificationBatches - GET /admin/notifications-center/batches
// ?search=&audience=&status=&from=&to=&sort=&order=&page=&limit=
func AdminGetNotificationBatches(c *gin.Context) {
	search := c.Query("search")
	audience := c.Query("audience")
	status := c.Query("status")
	from, to := c.Query("from"), c.Query("to")
	sortCol := map[string]string{
		"created_at": "nb.created_at",
		"sent_at":    "nb.sent_at",
		"status":     "nb.status",
	}[c.DefaultQuery("sort", "created_at")]
	if sortCol == "" {
		sortCol = "nb.created_at"
	}
	order := "DESC"
	if c.Query("order") == "asc" {
		order = "ASC"
	}
	page := ParsePagination(c)

	query := `
		SELECT nb.id, nb.title, nb.message, nb.target_type, nb.status,
		       nb.recipient_count, nb.sent_count, nb.failed_count,
		       COALESCE(creator.name,''), nb.scheduled_at, nb.sent_at, nb.created_at
		FROM notification_batches nb
		LEFT JOIN users creator ON nb.created_by = creator.id
		WHERE 1=1`
	args := []interface{}{}
	if search != "" {
		args = append(args, "%"+search+"%")
		n := len(args)
		query += fmt.Sprintf(` AND (nb.title ILIKE $%d OR nb.message ILIKE $%d OR nb.id::text ILIKE $%d OR COALESCE(creator.name,'') ILIKE $%d)`, n, n, n, n)
	}
	if audience != "" {
		args = append(args, audience)
		query += fmt.Sprintf(` AND nb.target_type = $%d`, len(args))
	}
	if status != "" {
		args = append(args, status)
		query += fmt.Sprintf(` AND nb.status = $%d`, len(args))
	}
	query += contentDateFilter("nb.created_at", from, to, &args)
	query += fmt.Sprintf(` ORDER BY %s %s`, sortCol, order)
	args = append(args, page.Limit, page.Offset)
	query += fmt.Sprintf(` LIMIT $%d OFFSET $%d`, len(args)-1, len(args))

	rows, err := config.DB.Query(query, args...)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch notifications", err.Error())
		return
	}
	defer rows.Close()

	type Row struct {
		ID             string  `json:"id"`
		Title          string  `json:"title"`
		Message        string  `json:"message"`
		TargetType     string  `json:"target_type"`
		Status         string  `json:"status"`
		RecipientCount int     `json:"recipient_count"`
		SentCount      int     `json:"sent_count"`
		FailedCount    int     `json:"failed_count"`
		CreatedByName  string  `json:"created_by_name"`
		ScheduledAt    *string `json:"scheduled_at"`
		SentAt         *string `json:"sent_at"`
		CreatedAt      string  `json:"created_at"`
	}
	out := []Row{}
	for rows.Next() {
		var r Row
		var scheduledAt, sentAt sql.NullTime
		var createdAt time.Time
		if err := rows.Scan(&r.ID, &r.Title, &r.Message, &r.TargetType, &r.Status,
			&r.RecipientCount, &r.SentCount, &r.FailedCount, &r.CreatedByName,
			&scheduledAt, &sentAt, &createdAt); err != nil {
			continue
		}
		if scheduledAt.Valid {
			s := scheduledAt.Time.Format(time.RFC3339)
			r.ScheduledAt = &s
		}
		if sentAt.Valid {
			s := sentAt.Time.Format(time.RFC3339)
			r.SentAt = &s
		}
		r.CreatedAt = createdAt.Format(time.RFC3339)
		out = append(out, r)
	}
	utils.SuccessWithMeta(c, http.StatusOK, "Notifications fetched", out, page.Meta(len(out)))
}

// AdminGetNotificationBatchDetail - GET /admin/notifications-center/batches/:id
func AdminGetNotificationBatchDetail(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "")
		return
	}
	var d struct {
		ID              string  `json:"id"`
		Title           string  `json:"title"`
		Message         string  `json:"message"`
		ImageURL        *string `json:"image_url"`
		DeepLink        *string `json:"deep_link"`
		TargetType      string  `json:"target_type"`
		TargetUserCount int     `json:"target_user_count"`
		Status          string  `json:"status"`
		RecipientCount  int     `json:"recipient_count"`
		SentCount       int     `json:"sent_count"`
		FailedCount     int     `json:"failed_count"`
		CreatedByName   string  `json:"created_by_name"`
		ScheduledAt     *string `json:"scheduled_at"`
		SentAt          *string `json:"sent_at"`
		CreatedAt       string  `json:"created_at"`
	}
	var imageURL, deepLink sql.NullString
	var targetUserIDs pq.StringArray
	var scheduledAt, sentAt sql.NullTime
	var createdAt time.Time
	err := config.DB.QueryRow(`
		SELECT nb.id, nb.title, nb.message, nb.image_url, nb.deep_link, nb.target_type,
		       COALESCE(nb.target_user_ids, '{}'), nb.status,
		       nb.recipient_count, nb.sent_count, nb.failed_count,
		       COALESCE(creator.name,''), nb.scheduled_at, nb.sent_at, nb.created_at
		FROM notification_batches nb
		LEFT JOIN users creator ON nb.created_by = creator.id
		WHERE nb.id = $1::uuid
	`, id).Scan(&d.ID, &d.Title, &d.Message, &imageURL, &deepLink, &d.TargetType,
		&targetUserIDs, &d.Status, &d.RecipientCount, &d.SentCount, &d.FailedCount,
		&d.CreatedByName, &scheduledAt, &sentAt, &createdAt)
	if err != nil {
		utils.Error(c, http.StatusNotFound, "Notification not found", err.Error())
		return
	}
	if imageURL.Valid {
		d.ImageURL = &imageURL.String
	}
	if deepLink.Valid {
		d.DeepLink = &deepLink.String
	}
	d.TargetUserCount = len(targetUserIDs)
	if scheduledAt.Valid {
		s := scheduledAt.Time.Format(time.RFC3339)
		d.ScheduledAt = &s
	}
	if sentAt.Valid {
		s := sentAt.Time.Format(time.RFC3339)
		d.SentAt = &s
	}
	d.CreatedAt = createdAt.Format(time.RFC3339)
	utils.Success(c, http.StatusOK, "Notification detail fetched", d)
}

type createNotificationRequest struct {
	Title          string   `json:"title" binding:"required"`
	Message        string   `json:"message" binding:"required"`
	ImageURL       string   `json:"image_url"`
	DeepLink       string   `json:"deep_link"`
	TargetType     string   `json:"target_type" binding:"required,oneof=everyone client lawyer student selected"`
	TargetUserIDs  []string `json:"target_user_ids"`
	ScheduledAt    string   `json:"scheduled_at"` // RFC3339, empty = send now
	IdempotencyKey string   `json:"idempotency_key" binding:"required"`
}

// AdminCreateNotification - POST /admin/notifications-center/batches
// Immediate sends are dispatched in the background so a large "Everyone"
// audience doesn't hold the HTTP request open; the batch starts as
// 'processing' and the client polls history/detail for the final status.
func AdminCreateNotification(c *gin.Context) {
	var req createNotificationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}
	if req.TargetType == "selected" && len(req.TargetUserIDs) == 0 {
		utils.Error(c, http.StatusBadRequest, "Select at least one user", "")
		return
	}

	// Idempotency: a retried/double-clicked request with the same key
	// returns the existing batch instead of creating a second one.
	var existingID string
	if config.DB.QueryRow(`SELECT id FROM notification_batches WHERE idempotency_key = $1`, req.IdempotencyKey).Scan(&existingID) == nil {
		utils.Success(c, http.StatusOK, "Notification already recorded", gin.H{"id": existingID})
		return
	}

	isScheduled := req.ScheduledAt != ""
	status := "processing"
	if isScheduled {
		status = "scheduled"
	}
	actorID := utils.UserID(c)

	var batchID string
	err := config.DB.QueryRow(`
		INSERT INTO notification_batches
			(id, title, message, image_url, deep_link, target_type, target_user_ids,
			 status, created_by, scheduled_at, idempotency_key)
		VALUES (gen_random_uuid(), $1, $2, NULLIF($3,''), NULLIF($4,''), $5, $6,
			$7, $8::uuid, NULLIF($9,'')::timestamptz, $10)
		RETURNING id
	`, req.Title, req.Message, req.ImageURL, req.DeepLink, req.TargetType, pq.Array(req.TargetUserIDs),
		status, actorID, req.ScheduledAt, req.IdempotencyKey).Scan(&batchID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to create notification", err.Error())
		return
	}

	auditAction := "NOTIFICATION_CREATED"
	if isScheduled {
		auditAction = "NOTIFICATION_SCHEDULED"
	}
	utils.LogAudit(c, utils.AuditEntry{
		Action: auditAction, Module: "notifications", TargetType: "notification_batch", TargetID: batchID,
		Description: "Notification \"" + req.Title + "\" " + status,
		After:       map[string]string{"status": status, "target_type": req.TargetType},
	})

	if !isScheduled {
		go ProcessNotificationBatch(batchID)
	}
	utils.Success(c, http.StatusCreated, "Notification recorded", gin.H{"id": batchID, "status": status})
}

// ProcessNotificationBatch resolves recipients, writes each one's in-app
// notification row, attempts a real Firebase push via SendPushToUserTracked,
// and finalizes the batch's aggregate status. Shared by the immediate-send
// path above and the scheduler below.
func ProcessNotificationBatch(batchID string) {
	var title, message, targetType string
	var imageURL, deepLink sql.NullString
	var targetUserIDs pq.StringArray
	err := config.DB.QueryRow(`
		SELECT title, message, image_url, deep_link, target_type, COALESCE(target_user_ids, '{}')
		FROM notification_batches WHERE id = $1::uuid
	`, batchID).Scan(&title, &message, &imageURL, &deepLink, &targetType, &targetUserIDs)
	if err != nil {
		return
	}

	recipients, err := resolveRecipients(targetType, []string(targetUserIDs))
	if err != nil {
		config.DB.Exec(`UPDATE notification_batches SET status='failed', updated_at=NOW() WHERE id=$1::uuid`, batchID)
		return
	}

	sentCount, failedCount := 0, 0
	for _, r := range recipients {
		var firmID string
		config.DB.QueryRow(`SELECT COALESCE(firm_id::text,'') FROM users WHERE id=$1::uuid`, r.ID).Scan(&firmID)

		result := utils.SendPushToUserTracked(r.ID, title, message, "admin_broadcast", batchID, "notification_batch")
		var notifID string
		config.DB.QueryRow(`
			INSERT INTO notifications (id, user_id, firm_id, title, message, type, reference_id, reference_type, batch_id, push_status, push_error)
			VALUES (gen_random_uuid(), $1::uuid, NULLIF($2,'')::uuid, $3, $4, 'admin_broadcast', $5::uuid, 'notification_batch', $5::uuid, $6, NULLIF($7,''))
			RETURNING id
		`, r.ID, firmID, title, message, batchID, result.Status, result.Error).Scan(&notifID)

		if result.Status == "failed" {
			failedCount++
		} else {
			sentCount++
		}
	}

	finalStatus := "sent"
	if len(recipients) == 0 {
		finalStatus = "failed"
	} else if failedCount > 0 && sentCount > 0 {
		finalStatus = "partially_sent"
	} else if failedCount > 0 && sentCount == 0 {
		finalStatus = "failed"
	}
	config.DB.Exec(`
		UPDATE notification_batches
		SET status=$1, recipient_count=$2, sent_count=$3, failed_count=$4, sent_at=NOW(), updated_at=NOW()
		WHERE id=$5::uuid
	`, finalStatus, len(recipients), sentCount, failedCount, batchID)
}

// AdminUpdateScheduledNotification - PUT /admin/notifications-center/batches/:id
// Only permitted while status='scheduled'.
func AdminUpdateScheduledNotification(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "")
		return
	}
	var status string
	config.DB.QueryRow(`SELECT status FROM notification_batches WHERE id=$1::uuid`, id).Scan(&status)
	if status != "scheduled" {
		utils.Error(c, http.StatusBadRequest, "Only a scheduled notification can be edited", "")
		return
	}
	var req struct {
		Title       string `json:"title" binding:"required"`
		Message     string `json:"message" binding:"required"`
		ImageURL    string `json:"image_url"`
		DeepLink    string `json:"deep_link"`
		ScheduledAt string `json:"scheduled_at" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}
	if _, err := config.DB.Exec(`
		UPDATE notification_batches SET title=$1, message=$2, image_url=NULLIF($3,''),
		  deep_link=NULLIF($4,''), scheduled_at=$5::timestamptz, updated_at=NOW()
		WHERE id=$6::uuid
	`, req.Title, req.Message, req.ImageURL, req.DeepLink, req.ScheduledAt, id); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to update notification", err.Error())
		return
	}
	utils.LogAudit(c, utils.AuditEntry{
		Action: "NOTIFICATION_UPDATED", Module: "notifications", TargetType: "notification_batch", TargetID: id,
		Description: "Scheduled notification updated",
		After:       map[string]string{"title": req.Title, "scheduled_at": req.ScheduledAt},
	})
	utils.Success(c, http.StatusOK, "Notification updated", nil)
}

// AdminCancelScheduledNotification - PUT /admin/notifications-center/batches/:id/cancel
func AdminCancelScheduledNotification(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "")
		return
	}
	var status string
	config.DB.QueryRow(`SELECT status FROM notification_batches WHERE id=$1::uuid`, id).Scan(&status)
	if status != "scheduled" {
		utils.Error(c, http.StatusBadRequest, "Only a scheduled notification can be cancelled", "")
		return
	}
	if _, err := config.DB.Exec(`UPDATE notification_batches SET status='cancelled', updated_at=NOW() WHERE id=$1::uuid`, id); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to cancel notification", err.Error())
		return
	}
	utils.LogAudit(c, utils.AuditEntry{
		Action: "NOTIFICATION_CANCELLED", Module: "notifications", TargetType: "notification_batch", TargetID: id,
		Description: "Scheduled notification cancelled",
		Before:      map[string]string{"status": "scheduled"}, After: map[string]string{"status": "cancelled"},
	})
	utils.Success(c, http.StatusOK, "Notification cancelled", nil)
}
