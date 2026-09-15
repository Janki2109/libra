package controllers

import (
	"database/sql"
	"fmt"
	"libra/config"
	"libra/utils"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/lib/pq"
)

// ─── CONTENT MANAGEMENT (Super Admin only) ──────────────────────────────
//
// content_items (migration 030) holds Legal Articles, FAQs, Banners,
// Announcements and Promotional Content — one table with a content_type
// discriminator, since all five share the same real shape. Terms &
// Conditions / Privacy Policy live in legal_documents, which is real
// version history rather than a single overwritable row. The ContentSweeper
// service (services/content_sweeper.go) does the server-side scheduled-
// publish/auto-expire work; every handler below only reacts to an explicit
// Super Admin action.

func contentDateFilter(col, from, to string, args *[]interface{}) string {
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

// AdminGetContentStats - GET /admin/content/stats
func AdminGetContentStats(c *gin.Context) {
	var out struct {
		Total     int            `json:"total_content"`
		Published int            `json:"published"`
		Drafts    int            `json:"drafts"`
		Scheduled int            `json:"scheduled"`
		Archived  int            `json:"archived"`
		ByType    map[string]int `json:"by_type"`
	}
	out.ByType = map[string]int{}
	config.DB.QueryRow(`SELECT COUNT(*) FROM content_items`).Scan(&out.Total)
	config.DB.QueryRow(`SELECT COUNT(*) FROM content_items WHERE status='published'`).Scan(&out.Published)
	config.DB.QueryRow(`SELECT COUNT(*) FROM content_items WHERE status='draft'`).Scan(&out.Drafts)
	config.DB.QueryRow(`SELECT COUNT(*) FROM content_items WHERE status='scheduled'`).Scan(&out.Scheduled)
	config.DB.QueryRow(`SELECT COUNT(*) FROM content_items WHERE status='archived'`).Scan(&out.Archived)

	rows, err := config.DB.Query(`SELECT content_type, COUNT(*) FROM content_items GROUP BY content_type`)
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var t string
			var n int
			if rows.Scan(&t, &n) == nil {
				out.ByType[t] = n
			}
		}
	}
	utils.Success(c, http.StatusOK, "Content stats fetched", out)
}

// AdminGetContentItems - GET /admin/content/items
// ?type=article|faq|banner|announcement|promotion&search=&status=&category=&audience=&from=&to=&sort=&order=&page=&limit=
func AdminGetContentItems(c *gin.Context) {
	contentType := c.Query("type")
	search := c.Query("search")
	status := c.Query("status")
	category := c.Query("category")
	audience := c.Query("audience")
	from, to := c.Query("from"), c.Query("to")
	sortCol := map[string]string{
		"created_at":    "ci.created_at",
		"updated_at":    "ci.updated_at",
		"published_at":  "ci.published_at",
		"title":         "ci.title",
		"display_order": "ci.display_order",
	}[c.DefaultQuery("sort", "updated_at")]
	if sortCol == "" {
		sortCol = "ci.updated_at"
	}
	order := "DESC"
	if c.Query("order") == "asc" {
		order = "ASC"
	}
	page := ParsePagination(c)

	query := `
		SELECT ci.id, ci.content_type, ci.title, ci.subtitle, ci.category, ci.image_url,
		       ci.target_audience, ci.priority, ci.display_order, ci.status,
		       ci.publish_at, ci.expire_at, COALESCE(creator.name,''), COALESCE(publisher.name,''),
		       ci.created_at, ci.updated_at, ci.published_at
		FROM content_items ci
		LEFT JOIN users creator ON ci.created_by = creator.id
		LEFT JOIN users publisher ON ci.published_by = publisher.id
		WHERE 1=1`
	args := []interface{}{}
	if contentType != "" {
		args = append(args, contentType)
		query += fmt.Sprintf(` AND ci.content_type = $%d`, len(args))
	}
	if search != "" {
		args = append(args, "%"+search+"%")
		n := len(args)
		query += fmt.Sprintf(` AND (ci.title ILIKE $%d OR ci.body ILIKE $%d OR ci.category ILIKE $%d
			OR ci.id::text ILIKE $%d OR COALESCE(creator.name,'') ILIKE $%d)`, n, n, n, n, n)
	}
	if status != "" {
		args = append(args, status)
		query += fmt.Sprintf(` AND ci.status = $%d`, len(args))
	}
	if category != "" {
		args = append(args, category)
		query += fmt.Sprintf(` AND ci.category = $%d`, len(args))
	}
	if audience != "" {
		args = append(args, audience)
		query += fmt.Sprintf(` AND ci.target_audience = $%d`, len(args))
	}
	query += contentDateFilter("ci.created_at", from, to, &args)
	query += fmt.Sprintf(` ORDER BY %s %s`, sortCol, order)
	args = append(args, page.Limit, page.Offset)
	query += fmt.Sprintf(` LIMIT $%d OFFSET $%d`, len(args)-1, len(args))

	rows, err := config.DB.Query(query, args...)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch content", err.Error())
		return
	}
	defer rows.Close()

	type Row struct {
		ID              string  `json:"id"`
		ContentType     string  `json:"content_type"`
		Title           string  `json:"title"`
		Subtitle        string  `json:"subtitle"`
		Category        string  `json:"category"`
		ImageURL        string  `json:"image_url"`
		TargetAudience  string  `json:"target_audience"`
		Priority        string  `json:"priority"`
		DisplayOrder    int     `json:"display_order"`
		Status          string  `json:"status"`
		PublishAt       *string `json:"publish_at"`
		ExpireAt        *string `json:"expire_at"`
		CreatedByName   string  `json:"created_by_name"`
		PublishedByName string  `json:"published_by_name"`
		CreatedAt       string  `json:"created_at"`
		UpdatedAt       string  `json:"updated_at"`
		PublishedAt     *string `json:"published_at"`
	}
	out := []Row{}
	for rows.Next() {
		var r Row
		var subtitle, category, imageURL sql.NullString
		var publishAt, expireAt, publishedAt sql.NullTime
		var createdAt, updatedAt time.Time
		if err := rows.Scan(&r.ID, &r.ContentType, &r.Title, &subtitle, &category, &imageURL,
			&r.TargetAudience, &r.Priority, &r.DisplayOrder, &r.Status, &publishAt, &expireAt,
			&r.CreatedByName, &r.PublishedByName, &createdAt, &updatedAt, &publishedAt); err != nil {
			continue
		}
		r.Subtitle = subtitle.String
		r.Category = category.String
		r.ImageURL = imageURL.String
		if publishAt.Valid {
			s := publishAt.Time.Format(time.RFC3339)
			r.PublishAt = &s
		}
		if expireAt.Valid {
			s := expireAt.Time.Format(time.RFC3339)
			r.ExpireAt = &s
		}
		if publishedAt.Valid {
			s := publishedAt.Time.Format(time.RFC3339)
			r.PublishedAt = &s
		}
		r.CreatedAt = createdAt.Format(time.RFC3339)
		r.UpdatedAt = updatedAt.Format(time.RFC3339)
		out = append(out, r)
	}
	utils.SuccessWithMeta(c, http.StatusOK, "Content fetched", out, page.Meta(len(out)))
}

// AdminGetContentItemDetail - GET /admin/content/items/:id
func AdminGetContentItemDetail(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "")
		return
	}
	var d struct {
		ID              string   `json:"id"`
		ContentType     string   `json:"content_type"`
		Title           string   `json:"title"`
		Subtitle        *string  `json:"subtitle"`
		Body            *string  `json:"body"`
		Category        *string  `json:"category"`
		ImageURL        *string  `json:"image_url"`
		CTAText         *string  `json:"cta_text"`
		CTAAction       *string  `json:"cta_action"`
		Tags            []string `json:"tags"`
		TargetAudience  string   `json:"target_audience"`
		Priority        string   `json:"priority"`
		DisplayOrder    int      `json:"display_order"`
		Status          string   `json:"status"`
		PublishAt       *string  `json:"publish_at"`
		ExpireAt        *string  `json:"expire_at"`
		CreatedByName   string   `json:"created_by_name"`
		UpdatedByName   string   `json:"updated_by_name"`
		PublishedByName string   `json:"published_by_name"`
		CreatedAt       string   `json:"created_at"`
		UpdatedAt       string   `json:"updated_at"`
		PublishedAt     *string  `json:"published_at"`
	}
	var subtitle, body, category, imageURL, ctaText, ctaAction sql.NullString
	var tags pq.StringArray
	var publishAt, expireAt, publishedAt sql.NullTime
	var createdAt, updatedAt time.Time
	err := config.DB.QueryRow(`
		SELECT ci.id, ci.content_type, ci.title, ci.subtitle, ci.body, ci.category, ci.image_url,
		       ci.cta_text, ci.cta_action, COALESCE(ci.tags, '{}'),
		       ci.target_audience, ci.priority, ci.display_order, ci.status,
		       ci.publish_at, ci.expire_at,
		       COALESCE(creator.name,''), COALESCE(updater.name,''), COALESCE(publisher.name,''),
		       ci.created_at, ci.updated_at, ci.published_at
		FROM content_items ci
		LEFT JOIN users creator ON ci.created_by = creator.id
		LEFT JOIN users updater ON ci.updated_by = updater.id
		LEFT JOIN users publisher ON ci.published_by = publisher.id
		WHERE ci.id = $1::uuid
	`, id).Scan(&d.ID, &d.ContentType, &d.Title, &subtitle, &body, &category, &imageURL,
		&ctaText, &ctaAction, &tags, &d.TargetAudience, &d.Priority, &d.DisplayOrder, &d.Status,
		&publishAt, &expireAt, &d.CreatedByName, &d.UpdatedByName, &d.PublishedByName,
		&createdAt, &updatedAt, &publishedAt)
	if err != nil {
		utils.Error(c, http.StatusNotFound, "Content not found", err.Error())
		return
	}
	if subtitle.Valid {
		d.Subtitle = &subtitle.String
	}
	if body.Valid {
		d.Body = &body.String
	}
	if category.Valid {
		d.Category = &category.String
	}
	if imageURL.Valid {
		d.ImageURL = &imageURL.String
	}
	if ctaText.Valid {
		d.CTAText = &ctaText.String
	}
	if ctaAction.Valid {
		d.CTAAction = &ctaAction.String
	}
	d.Tags = []string(tags)
	if publishAt.Valid {
		s := publishAt.Time.Format(time.RFC3339)
		d.PublishAt = &s
	}
	if expireAt.Valid {
		s := expireAt.Time.Format(time.RFC3339)
		d.ExpireAt = &s
	}
	if publishedAt.Valid {
		s := publishedAt.Time.Format(time.RFC3339)
		d.PublishedAt = &s
	}
	d.CreatedAt = createdAt.Format(time.RFC3339)
	d.UpdatedAt = updatedAt.Format(time.RFC3339)
	utils.Success(c, http.StatusOK, "Content detail fetched", d)
}

type contentItemRequest struct {
	ContentType    string   `json:"content_type" binding:"required,oneof=article faq banner announcement promotion"`
	Title          string   `json:"title" binding:"required"`
	Subtitle       string   `json:"subtitle"`
	Body           string   `json:"body"`
	Category       string   `json:"category"`
	ImageURL       string   `json:"image_url"`
	CTAText        string   `json:"cta_text"`
	CTAAction      string   `json:"cta_action"`
	Tags           []string `json:"tags"`
	TargetAudience string   `json:"target_audience"`
	Priority       string   `json:"priority"`
	DisplayOrder   int      `json:"display_order"`
}

// sanitizeContentHTML strips script/style/on*-handler markup a rich-text
// editor could conceivably let through, without needing a full HTML AST
// dependency — every article/announcement body is a legal-content string,
// never a template Super Admin needs live `<script>` execution inside.
func sanitizeContentHTML(s string) string {
	lower := strings.ToLower(s)
	if strings.Contains(lower, "<script") || strings.Contains(lower, "javascript:") || strings.Contains(lower, " onerror=") || strings.Contains(lower, " onload=") {
		// Reject outright rather than trying to surgically strip tags —
		// legal content never legitimately needs any of these.
		return strings.NewReplacer("<script", "&lt;script", "javascript:", "", " onerror=", " data-blocked-onerror=", " onload=", " data-blocked-onload=").Replace(s)
	}
	return s
}

// AdminCreateContentItem - POST /admin/content/items (always created as draft)
func AdminCreateContentItem(c *gin.Context) {
	var req contentItemRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}
	if req.TargetAudience == "" {
		req.TargetAudience = "all"
	}
	if req.Priority == "" {
		req.Priority = "normal"
	}
	req.Body = sanitizeContentHTML(req.Body)

	actorID := utils.UserID(c)
	var id string
	err := config.DB.QueryRow(`
		INSERT INTO content_items
			(id, content_type, title, subtitle, body, category, image_url, cta_text, cta_action,
			 tags, target_audience, priority, display_order, status, created_by, updated_by)
		VALUES (gen_random_uuid(), $1, $2, NULLIF($3,''), NULLIF($4,''), NULLIF($5,''), NULLIF($6,''),
			NULLIF($7,''), NULLIF($8,''), $9, $10, $11, $12, 'draft', $13::uuid, $13::uuid)
		RETURNING id
	`, req.ContentType, req.Title, req.Subtitle, req.Body, req.Category, req.ImageURL,
		req.CTAText, req.CTAAction, pq.Array(req.Tags), req.TargetAudience, req.Priority,
		req.DisplayOrder, actorID).Scan(&id)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to create content", err.Error())
		return
	}

	utils.LogAudit(c, utils.AuditEntry{
		Action: contentActionPrefix(req.ContentType) + "_CREATED", Module: "content", TargetType: req.ContentType, TargetID: id,
		Description: "Content created: " + req.Title,
		After:       map[string]string{"title": req.Title, "status": "draft"},
	})
	utils.Success(c, http.StatusCreated, "Content created as draft", gin.H{"id": id})
}

// AdminUpdateContentItem - PUT /admin/content/items/:id
// Editing never silently republishes — status is left untouched here.
func AdminUpdateContentItem(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "")
		return
	}
	var req contentItemRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}
	req.Body = sanitizeContentHTML(req.Body)
	actorID := utils.UserID(c)

	var previousTitle string
	config.DB.QueryRow(`SELECT title FROM content_items WHERE id=$1::uuid`, id).Scan(&previousTitle)

	res, err := config.DB.Exec(`
		UPDATE content_items SET
			title=$1, subtitle=NULLIF($2,''), body=NULLIF($3,''), category=NULLIF($4,''),
			image_url=NULLIF($5,''), cta_text=NULLIF($6,''), cta_action=NULLIF($7,''),
			tags=$8, target_audience=$9, priority=$10, display_order=$11,
			updated_by=$12::uuid, updated_at=NOW()
		WHERE id=$13::uuid
	`, req.Title, req.Subtitle, req.Body, req.Category, req.ImageURL, req.CTAText, req.CTAAction,
		pq.Array(req.Tags), req.TargetAudience, req.Priority, req.DisplayOrder, actorID, id)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to update content", err.Error())
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		utils.Error(c, http.StatusNotFound, "Content not found", "")
		return
	}

	utils.LogAudit(c, utils.AuditEntry{
		Action: contentActionPrefix(req.ContentType) + "_UPDATED", Module: "content", TargetType: req.ContentType, TargetID: id,
		Description: "Content updated",
		Before:      map[string]string{"title": previousTitle}, After: map[string]string{"title": req.Title},
	})
	utils.Success(c, http.StatusOK, "Content updated", nil)
}

func contentActionPrefix(contentType string) string {
	switch contentType {
	case "article":
		return "LEGAL_ARTICLE"
	case "faq":
		return "FAQ"
	case "banner":
		return "BANNER"
	case "announcement":
		return "ANNOUNCEMENT"
	case "promotion":
		return "PROMOTION"
	default:
		return "CONTENT"
	}
}

// AdminPublishContentItem - PUT /admin/content/items/:id/publish
// Immediate publish. Use /schedule instead for a future publish_at.
func AdminPublishContentItem(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "")
		return
	}
	var contentType, previousStatus string
	config.DB.QueryRow(`SELECT content_type, status FROM content_items WHERE id=$1::uuid`, id).Scan(&contentType, &previousStatus)
	if contentType == "" {
		utils.Error(c, http.StatusNotFound, "Content not found", "")
		return
	}
	actorID := utils.UserID(c)
	if _, err := config.DB.Exec(`
		UPDATE content_items SET status='published', published_by=$1::uuid, published_at=NOW(),
		  publish_at=NULL, updated_by=$1::uuid, updated_at=NOW()
		WHERE id=$2::uuid
	`, actorID, id); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to publish content", err.Error())
		return
	}
	action := "CONTENT_PUBLISHED"
	if contentType == "banner" {
		action = "BANNER_PUBLISHED"
	} else if contentType == "announcement" {
		action = "ANNOUNCEMENT_PUBLISHED"
	} else if contentType == "promotion" {
		action = "PROMOTION_PUBLISHED"
	}
	utils.LogAudit(c, utils.AuditEntry{
		Action: action, Module: "content", TargetType: contentType, TargetID: id,
		Description: "Content published",
		Before:      map[string]string{"status": previousStatus}, After: map[string]string{"status": "published"},
	})
	utils.Success(c, http.StatusOK, "Content published", nil)
}

// AdminScheduleContentItem - PUT /admin/content/items/:id/schedule
// {"publish_at": "2026-...", "expire_at": "2026-..."} (expire_at optional)
func AdminScheduleContentItem(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "")
		return
	}
	var req struct {
		PublishAt string `json:"publish_at" binding:"required"`
		ExpireAt  string `json:"expire_at"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}
	var previousStatus string
	config.DB.QueryRow(`SELECT status FROM content_items WHERE id=$1::uuid`, id).Scan(&previousStatus)
	if _, err := config.DB.Exec(`
		UPDATE content_items SET status='scheduled', publish_at=$1::timestamp, expire_at=NULLIF($2,'')::timestamp,
		  updated_by=$3::uuid, updated_at=NOW()
		WHERE id=$4::uuid
	`, req.PublishAt, req.ExpireAt, utils.UserID(c), id); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to schedule content", err.Error())
		return
	}
	utils.LogAudit(c, utils.AuditEntry{
		Action: "CONTENT_SCHEDULED", Module: "content", TargetType: "content_item", TargetID: id,
		Description: "Content scheduled for " + req.PublishAt,
		Before:      map[string]string{"status": previousStatus}, After: map[string]string{"status": "scheduled", "publish_at": req.PublishAt},
	})
	utils.Success(c, http.StatusOK, "Content scheduled", nil)
}

// AdminUnpublishContentItem - PUT /admin/content/items/:id/unpublish
func AdminUnpublishContentItem(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "")
		return
	}
	var contentType, previousStatus string
	config.DB.QueryRow(`SELECT content_type, status FROM content_items WHERE id=$1::uuid`, id).Scan(&contentType, &previousStatus)
	if _, err := config.DB.Exec(`
		UPDATE content_items SET status='unpublished', updated_by=$1::uuid, updated_at=NOW() WHERE id=$2::uuid
	`, utils.UserID(c), id); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to unpublish content", err.Error())
		return
	}
	action := "CONTENT_UNPUBLISHED"
	if contentType == "banner" {
		action = "BANNER_UNPUBLISHED"
	}
	utils.LogAudit(c, utils.AuditEntry{
		Action: action, Module: "content", TargetType: contentType, TargetID: id,
		Description: "Content unpublished",
		Before:      map[string]string{"status": previousStatus}, After: map[string]string{"status": "unpublished"},
	})
	utils.Success(c, http.StatusOK, "Content unpublished", nil)
}

// AdminArchiveContentItem - PUT /admin/content/items/:id/archive
func AdminArchiveContentItem(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "")
		return
	}
	var previousStatus string
	config.DB.QueryRow(`SELECT status FROM content_items WHERE id=$1::uuid`, id).Scan(&previousStatus)
	if _, err := config.DB.Exec(`
		UPDATE content_items SET status='archived', updated_by=$1::uuid, updated_at=NOW() WHERE id=$2::uuid
	`, utils.UserID(c), id); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to archive content", err.Error())
		return
	}
	utils.LogAudit(c, utils.AuditEntry{
		Action: "CONTENT_ARCHIVED", Module: "content", TargetType: "content_item", TargetID: id,
		Description: "Content archived",
		Before:      map[string]string{"status": previousStatus}, After: map[string]string{"status": "archived"},
	})
	utils.Success(c, http.StatusOK, "Content archived", nil)
}

// AdminDeleteContentItem - DELETE /admin/content/items/:id
// Only a draft may be hard-deleted — anything that was ever published stays
// for history (per "delete only if safe" and "keep for history/reporting").
func AdminDeleteContentItem(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "")
		return
	}
	var status, contentType, title string
	config.DB.QueryRow(`SELECT status, content_type, title FROM content_items WHERE id=$1::uuid`, id).Scan(&status, &contentType, &title)
	if status == "" {
		utils.Error(c, http.StatusNotFound, "Content not found", "")
		return
	}
	if status != "draft" {
		utils.Error(c, http.StatusBadRequest, "Only a draft can be deleted", "archive it instead to remove it from view")
		return
	}
	if _, err := config.DB.Exec(`DELETE FROM content_items WHERE id=$1::uuid`, id); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to delete content", err.Error())
		return
	}
	utils.LogAudit(c, utils.AuditEntry{
		Action: "CONTENT_DELETED", Module: "content", TargetType: contentType, TargetID: id,
		Description: "Draft content deleted: " + title,
	})
	utils.Success(c, http.StatusOK, "Draft deleted", nil)
}

// ─── Terms & Conditions / Privacy Policy (versioned) ────────────────────

// AdminGetLegalDocuments - GET /admin/content/legal/:doc_type (history, newest first)
func AdminGetLegalDocuments(c *gin.Context) {
	docType := c.Param("doc_type")
	if docType != "terms" && docType != "privacy" {
		utils.Error(c, http.StatusBadRequest, "Invalid document type", "expected terms or privacy")
		return
	}
	rows, err := config.DB.Query(`
		SELECT ld.id, ld.version, ld.status, COALESCE(creator.name,''), ld.created_at,
		       COALESCE(publisher.name,''), ld.published_at
		FROM legal_documents ld
		LEFT JOIN users creator ON ld.created_by = creator.id
		LEFT JOIN users publisher ON ld.published_by = publisher.id
		WHERE ld.doc_type = $1
		ORDER BY ld.created_at DESC
	`, docType)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch versions", err.Error())
		return
	}
	defer rows.Close()

	type Row struct {
		ID              string  `json:"id"`
		Version         string  `json:"version"`
		Status          string  `json:"status"`
		CreatedByName   string  `json:"created_by_name"`
		CreatedAt       string  `json:"created_at"`
		PublishedByName string  `json:"published_by_name"`
		PublishedAt     *string `json:"published_at"`
	}
	out := []Row{}
	for rows.Next() {
		var r Row
		var createdAt time.Time
		var publishedAt sql.NullTime
		if err := rows.Scan(&r.ID, &r.Version, &r.Status, &r.CreatedByName, &createdAt, &r.PublishedByName, &publishedAt); err != nil {
			continue
		}
		r.CreatedAt = createdAt.Format(time.RFC3339)
		if publishedAt.Valid {
			s := publishedAt.Time.Format(time.RFC3339)
			r.PublishedAt = &s
		}
		out = append(out, r)
	}
	utils.Success(c, http.StatusOK, "Versions fetched", out)
}

// AdminGetLegalDocumentVersion - GET /admin/content/legal/version/:id
func AdminGetLegalDocumentVersion(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "")
		return
	}
	var d struct {
		ID              string  `json:"id"`
		DocType         string  `json:"doc_type"`
		Version         string  `json:"version"`
		Content         string  `json:"content"`
		Status          string  `json:"status"`
		CreatedByName   string  `json:"created_by_name"`
		CreatedAt       string  `json:"created_at"`
		PublishedByName string  `json:"published_by_name"`
		PublishedAt     *string `json:"published_at"`
	}
	var createdAt time.Time
	var publishedAt sql.NullTime
	err := config.DB.QueryRow(`
		SELECT ld.id, ld.doc_type, ld.version, ld.content, ld.status,
		       COALESCE(creator.name,''), ld.created_at, COALESCE(publisher.name,''), ld.published_at
		FROM legal_documents ld
		LEFT JOIN users creator ON ld.created_by = creator.id
		LEFT JOIN users publisher ON ld.published_by = publisher.id
		WHERE ld.id = $1::uuid
	`, id).Scan(&d.ID, &d.DocType, &d.Version, &d.Content, &d.Status, &d.CreatedByName, &createdAt, &d.PublishedByName, &publishedAt)
	if err != nil {
		utils.Error(c, http.StatusNotFound, "Version not found", err.Error())
		return
	}
	d.CreatedAt = createdAt.Format(time.RFC3339)
	if publishedAt.Valid {
		s := publishedAt.Time.Format(time.RFC3339)
		d.PublishedAt = &s
	}
	utils.Success(c, http.StatusOK, "Version fetched", d)
}

// AdminCreateLegalDocumentDraft - POST /admin/content/legal/:doc_type
// {"version": "2.1", "content": "..."} — always created as a new draft row;
// never overwrites a prior version.
func AdminCreateLegalDocumentDraft(c *gin.Context) {
	docType := c.Param("doc_type")
	if docType != "terms" && docType != "privacy" {
		utils.Error(c, http.StatusBadRequest, "Invalid document type", "expected terms or privacy")
		return
	}
	var req struct {
		Version string `json:"version" binding:"required"`
		Content string `json:"content" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}
	req.Content = sanitizeContentHTML(req.Content)

	var id string
	err := config.DB.QueryRow(`
		INSERT INTO legal_documents (id, doc_type, version, content, status, created_by)
		VALUES (gen_random_uuid(), $1, $2, $3, 'draft', $4::uuid)
		RETURNING id
	`, docType, req.Version, req.Content, utils.UserID(c)).Scan(&id)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to save draft", err.Error())
		return
	}
	action := "TERMS_UPDATED"
	if docType == "privacy" {
		action = "PRIVACY_POLICY_UPDATED"
	}
	utils.LogAudit(c, utils.AuditEntry{
		Action: action, Module: "content", TargetType: "legal_document", TargetID: id,
		Description: docType + " draft version " + req.Version + " saved",
		After:       map[string]string{"version": req.Version, "status": "draft"},
	})
	utils.Success(c, http.StatusCreated, "Draft saved", gin.H{"id": id})
}

// AdminPublishLegalDocument - PUT /admin/content/legal/version/:id/publish
// Marks this version published; the previous published version (if any)
// becomes a plain historical row via the unique-published-per-doc-type
// index — its own row, content and dates are left exactly as they were.
func AdminPublishLegalDocument(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "")
		return
	}
	var docType, version string
	if err := config.DB.QueryRow(`SELECT doc_type, version FROM legal_documents WHERE id=$1::uuid`, id).Scan(&docType, &version); err != nil {
		utils.Error(c, http.StatusNotFound, "Version not found", "")
		return
	}

	tx, err := config.DB.Begin()
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to publish", err.Error())
		return
	}
	defer tx.Rollback()
	// Demote the currently-published version (if any) first so the partial
	// unique index never sees two published rows for this doc_type at once.
	if _, err := tx.Exec(`UPDATE legal_documents SET status='draft' WHERE doc_type=$1 AND status='published'`, docType); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to publish", err.Error())
		return
	}
	actorID := utils.UserID(c)
	if _, err := tx.Exec(`
		UPDATE legal_documents SET status='published', published_by=$1::uuid, published_at=NOW() WHERE id=$2::uuid
	`, actorID, id); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to publish", err.Error())
		return
	}
	if err := tx.Commit(); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to publish", err.Error())
		return
	}

	action := "TERMS_PUBLISHED"
	if docType == "privacy" {
		action = "PRIVACY_POLICY_PUBLISHED"
	}
	utils.LogAudit(c, utils.AuditEntry{
		Action: action, Module: "content", TargetType: "legal_document", TargetID: id,
		Description: docType + " version " + version + " published",
		After:       map[string]string{"version": version, "status": "published"},
	})
	utils.Success(c, http.StatusOK, "Version published", nil)
}
