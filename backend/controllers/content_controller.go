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

// ─── CONTENT — user-facing read endpoints ───────────────────────────────
//
// Only ever returns status='published' rows — the ContentSweeper
// (services/content_sweeper.go) is what moves a row into or out of
// 'published' as its publish_at/expire_at pass, so this never needs its own
// date-window logic. audienceClause matches "all" plus the caller's own
// role, the same 4-role system used everywhere else ('law_student' is the
// actual stored role name for a Student).
func audienceClause(role string, args *[]interface{}) string {
	*args = append(*args, role)
	return fmt.Sprintf(" AND target_audience IN ('all', $%d)", len(*args))
}

// audienceRoleParam maps the JWT's role claim to the value content_items
// actually stores in target_audience — every other role name matches
// directly except the student one.
func audienceRoleParam(role string) string {
	if role == "law_student" {
		return "student"
	}
	return role
}

// GetPublishedArticles - GET /content/articles?category=&search=
func GetPublishedArticles(c *gin.Context) {
	category := c.Query("category")
	search := c.Query("search")
	role := audienceRoleParam(utils.Role(c))

	query := `
		SELECT id, title, subtitle, category, image_url, tags, created_at, published_at
		FROM content_items WHERE content_type = 'article' AND status = 'published'`
	args := []interface{}{}
	query += audienceClause(role, &args)
	if category != "" {
		args = append(args, category)
		query += fmt.Sprintf(` AND category = $%d`, len(args))
	}
	if search != "" {
		args = append(args, "%"+search+"%")
		n := len(args)
		query += fmt.Sprintf(` AND (title ILIKE $%d OR body ILIKE $%d)`, n, n)
	}
	query += ` ORDER BY published_at DESC LIMIT 100`

	rows, err := config.DB.Query(query, args...)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch articles", err.Error())
		return
	}
	defer rows.Close()

	type Row struct {
		ID          string   `json:"id"`
		Title       string   `json:"title"`
		Subtitle    *string  `json:"subtitle"`
		Category    *string  `json:"category"`
		ImageURL    *string  `json:"image_url"`
		Tags        []string `json:"tags"`
		CreatedAt   string   `json:"created_at"`
		PublishedAt *string  `json:"published_at"`
	}
	out := []Row{}
	for rows.Next() {
		var r Row
		var tags pq.StringArray
		var createdAt time.Time
		var publishedAt sql.NullTime
		if rows.Scan(&r.ID, &r.Title, &r.Subtitle, &r.Category, &r.ImageURL, &tags, &createdAt, &publishedAt) != nil {
			continue
		}
		r.Tags = []string(tags)
		r.CreatedAt = createdAt.Format(time.RFC3339)
		if publishedAt.Valid {
			s := publishedAt.Time.Format(time.RFC3339)
			r.PublishedAt = &s
		}
		out = append(out, r)
	}
	utils.Success(c, http.StatusOK, "Articles fetched", out)
}

// GetPublishedArticleDetail - GET /content/articles/:id
func GetPublishedArticleDetail(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "")
		return
	}
	var itemID, title string
	var subtitle, body, category, imageURL sql.NullString
	var tags pq.StringArray
	var publishedAt sql.NullTime
	err := config.DB.QueryRow(`
		SELECT id, title, subtitle, body, category, image_url, COALESCE(tags,'{}'), published_at
		FROM content_items WHERE id=$1::uuid AND content_type='article' AND status='published'
	`, id).Scan(&itemID, &title, &subtitle, &body, &category, &imageURL, &tags, &publishedAt)
	if err != nil {
		utils.Error(c, http.StatusNotFound, "Article not found", "")
		return
	}
	out := gin.H{
		"id": itemID, "title": title, "subtitle": subtitle.String, "body": body.String,
		"category": category.String, "image_url": imageURL.String, "tags": []string(tags),
	}
	if publishedAt.Valid {
		out["published_at"] = publishedAt.Time.Format(time.RFC3339)
	}
	utils.Success(c, http.StatusOK, "Article fetched", out)
}

// GetPublishedFAQs - GET /content/faqs?category=
func GetPublishedFAQs(c *gin.Context) {
	category := c.Query("category")
	role := audienceRoleParam(utils.Role(c))
	query := `
		SELECT id, title, body, category, display_order
		FROM content_items WHERE content_type = 'faq' AND status = 'published'`
	args := []interface{}{}
	query += audienceClause(role, &args)
	if category != "" {
		args = append(args, category)
		query += fmt.Sprintf(` AND category = $%d`, len(args))
	}
	query += ` ORDER BY display_order ASC, created_at ASC`

	rows, err := config.DB.Query(query, args...)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch FAQs", err.Error())
		return
	}
	defer rows.Close()
	out := []gin.H{}
	for rows.Next() {
		var id, question string
		var answer, cat sql.NullString
		var order int
		if rows.Scan(&id, &question, &answer, &cat, &order) != nil {
			continue
		}
		out = append(out, gin.H{"id": id, "question": question, "answer": answer.String, "category": cat.String, "display_order": order})
	}
	utils.Success(c, http.StatusOK, "FAQs fetched", out)
}

// GetActiveBanners - GET /content/banners
func GetActiveBanners(c *gin.Context) { getActiveContentByType(c, "banner", "Banners") }

// GetActiveAnnouncements - GET /content/announcements
func GetActiveAnnouncements(c *gin.Context) {
	getActiveContentByType(c, "announcement", "Announcements")
}

// GetActivePromotions - GET /content/promotions
func GetActivePromotions(c *gin.Context) { getActiveContentByType(c, "promotion", "Promotions") }

func getActiveContentByType(c *gin.Context, contentType, label string) {
	role := audienceRoleParam(utils.Role(c))
	query := `
		SELECT id, title, subtitle, body, image_url, cta_text, cta_action, priority, published_at
		FROM content_items WHERE content_type = $1 AND status = 'published'`
	args := []interface{}{contentType}
	query += audienceClause(role, &args)
	query += ` ORDER BY priority DESC, published_at DESC LIMIT 50`

	rows, err := config.DB.Query(query, args...)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch "+label, err.Error())
		return
	}
	defer rows.Close()
	out := []gin.H{}
	for rows.Next() {
		var id, title, priority string
		var subtitle, body, imageURL, ctaText, ctaAction sql.NullString
		var publishedAt sql.NullTime
		if rows.Scan(&id, &title, &subtitle, &body, &imageURL, &ctaText, &ctaAction, &priority, &publishedAt) != nil {
			continue
		}
		item := gin.H{
			"id": id, "title": title, "subtitle": subtitle.String, "body": body.String, "image_url": imageURL.String,
			"cta_text": ctaText.String, "cta_action": ctaAction.String, "priority": priority,
		}
		if publishedAt.Valid {
			item["published_at"] = publishedAt.Time.Format(time.RFC3339)
		}
		out = append(out, item)
	}
	utils.Success(c, http.StatusOK, label+" fetched", out)
}

// GetCurrentLegalDocument - GET /content/legal/:doc_type/current (public, no auth required)
func GetCurrentLegalDocument(c *gin.Context) {
	docType := c.Param("doc_type")
	if docType != "terms" && docType != "privacy" {
		utils.Error(c, http.StatusBadRequest, "Invalid document type", "expected terms or privacy")
		return
	}
	var id, version, content string
	var publishedAt sql.NullTime
	err := config.DB.QueryRow(`
		SELECT id, version, content, published_at
		FROM legal_documents WHERE doc_type=$1 AND status='published'
	`, docType).Scan(&id, &version, &content, &publishedAt)
	if err != nil {
		utils.Error(c, http.StatusNotFound, "No published version available", "")
		return
	}
	out := gin.H{"id": id, "doc_type": docType, "version": version, "content": content}
	if publishedAt.Valid {
		out["published_at"] = publishedAt.Time.Format(time.RFC3339)
	}
	utils.Success(c, http.StatusOK, "Document fetched", out)
}
