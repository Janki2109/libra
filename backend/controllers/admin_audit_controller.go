package controllers

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"libra/config"
	"libra/utils"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/lib/pq"
)

// ─── AUDIT LOGS (Super Admin only) ──────────────────────────────────────
//
// audit_logs already existed (migration 007) for a handful of write sites
// (password reset, bank details); migration 028 extended it with the
// columns this module needs (actor_role, target_type, device_type,
// request_id, status, description) and made it append-only at the database
// level. utils.LogAudit/LogSystemAudit is the single write path every
// action point below calls — this file only reads.

// auditRoleLabel maps a stored role name to the fixed 4-role display label
// this app uses everywhere else — never "ADMIN", and 'law_student' (the
// actual DB role name) reads as "STUDENT" like every other admin screen.
func auditRoleLabel(role string) string {
	switch role {
	case "super_admin":
		return "SUPER ADMIN"
	case "lawyer":
		return "LAWYER"
	case "client":
		return "CLIENT"
	case "law_student":
		return "STUDENT"
	case "system":
		return "SYSTEM"
	default:
		return "UNKNOWN"
	}
}

// auditHighRisk marks the action types called out as "make visually
// distinguishable" — a fixed list, not a guess, matching the exact actions
// this module's file header names as high-risk.
func auditHighRisk(action string) bool {
	switch action {
	case "REFUND_APPROVED", "REFUND_REJECTED", "REFUND_PROCESSED",
		"PAYOUT_APPROVED", "PAYOUT_MARKED_PAID",
		"LAWYER_VERIFIED", "LAWYER_REJECTED",
		"USER_ROLE_CHANGED", "USER_SUSPENDED",
		"SETTINGS_CHANGED":
		return true
	default:
		return false
	}
}

func auditDateFilter(col, from, to string, args *[]interface{}) string {
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

// AdminGetAuditLogStats - GET /admin/audit-logs/stats
func AdminGetAuditLogStats(c *gin.Context) {
	var out struct {
		TotalEvents       int `json:"total_events"`
		TodayEvents       int `json:"today_events"`
		HighRiskActions   int `json:"high_risk_actions"`
		SuperAdminActions int `json:"super_admin_actions"`
	}
	config.DB.QueryRow(`SELECT COUNT(*) FROM audit_logs`).Scan(&out.TotalEvents)
	config.DB.QueryRow(`SELECT COUNT(*) FROM audit_logs WHERE created_at >= CURRENT_DATE`).Scan(&out.TodayEvents)
	config.DB.QueryRow(`
		SELECT COUNT(*) FROM audit_logs WHERE action = ANY($1)
	`, pq.Array([]string{
		"REFUND_APPROVED", "REFUND_REJECTED", "REFUND_PROCESSED",
		"PAYOUT_APPROVED", "PAYOUT_MARKED_PAID",
		"LAWYER_VERIFIED", "LAWYER_REJECTED",
		"USER_ROLE_CHANGED", "USER_SUSPENDED", "SETTINGS_CHANGED",
	})).Scan(&out.HighRiskActions)
	config.DB.QueryRow(`
		SELECT COUNT(*) FROM audit_logs al
		LEFT JOIN users u ON al.user_id = u.id
		LEFT JOIN roles ur ON u.role_id = ur.id
		WHERE COALESCE(al.actor_role, ur.name, '') = 'super_admin'
	`).Scan(&out.SuperAdminActions)
	utils.Success(c, http.StatusOK, "Audit log stats fetched", out)
}

// AdminGetAuditLogs - GET /admin/audit-logs
// ?search=&role=&action=&module=&status=&from=&to=&sort=created_at|actor|action|module&order=desc|asc&page=&limit=
func AdminGetAuditLogs(c *gin.Context) {
	search := c.Query("search")
	role := c.Query("role")
	action := c.Query("action")
	module := c.Query("module")
	status := c.Query("status")
	from, to := c.Query("from"), c.Query("to")
	sortCol := map[string]string{
		"created_at": "al.created_at",
		"actor":      "COALESCE(u.name,'')",
		"action":     "al.action",
		"module":     "COALESCE(al.module,'')",
	}[c.DefaultQuery("sort", "created_at")]
	if sortCol == "" {
		sortCol = "al.created_at"
	}
	order := "DESC"
	if c.Query("order") == "asc" {
		order = "ASC"
	}
	page := ParsePagination(c)

	query := `
		SELECT al.id, al.user_id, COALESCE(u.name,''), COALESCE(u.email,''),
		       COALESCE(al.actor_role, ur.name, ''), al.action, COALESCE(al.module,''),
		       COALESCE(al.target_type,''), al.reference_id, COALESCE(al.description,''),
		       COALESCE(al.ip_address,''), COALESCE(al.device_type,''), al.status, al.created_at
		FROM audit_logs al
		LEFT JOIN users u ON al.user_id = u.id
		LEFT JOIN roles ur ON u.role_id = ur.id
		WHERE 1=1`
	args := []interface{}{}
	if search != "" {
		args = append(args, "%"+search+"%")
		n := len(args)
		query += fmt.Sprintf(` AND (u.name ILIKE $%d OR u.email ILIKE $%d OR al.user_id::text ILIKE $%d
			OR al.action ILIKE $%d OR al.reference_id::text ILIKE $%d OR al.description ILIKE $%d)`,
			n, n, n, n, n, n)
	}
	if role != "" {
		args = append(args, role)
		query += fmt.Sprintf(` AND COALESCE(al.actor_role, ur.name, '') = $%d`, len(args))
	}
	if action != "" {
		args = append(args, action)
		query += fmt.Sprintf(` AND al.action = $%d`, len(args))
	}
	if module != "" {
		args = append(args, module)
		query += fmt.Sprintf(` AND al.module = $%d`, len(args))
	}
	if status != "" {
		args = append(args, status)
		query += fmt.Sprintf(` AND al.status = $%d`, len(args))
	}
	query += auditDateFilter("al.created_at", from, to, &args)
	query += fmt.Sprintf(` ORDER BY %s %s`, sortCol, order)
	args = append(args, page.Limit, page.Offset)
	query += fmt.Sprintf(` LIMIT $%d OFFSET $%d`, len(args)-1, len(args))

	rows, err := config.DB.Query(query, args...)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch audit logs", err.Error())
		return
	}
	defer rows.Close()

	type Row struct {
		ID          string  `json:"id"`
		ActorID     *string `json:"actor_id"`
		ActorName   string  `json:"actor_name"`
		ActorEmail  string  `json:"actor_email"`
		Role        string  `json:"role"`
		Action      string  `json:"action"`
		Module      string  `json:"module"`
		TargetType  string  `json:"target_type"`
		TargetID    *string `json:"target_id"`
		Description string  `json:"description"`
		IPAddress   string  `json:"ip_address"`
		Device      string  `json:"device"`
		Status      string  `json:"status"`
		CreatedAt   string  `json:"created_at"`
		HighRisk    bool    `json:"high_risk"`
	}
	out := []Row{}
	for rows.Next() {
		var r Row
		var actorID, targetID sql.NullString
		var createdAt time.Time
		if err := rows.Scan(&r.ID, &actorID, &r.ActorName, &r.ActorEmail, &r.Role, &r.Action, &r.Module,
			&r.TargetType, &targetID, &r.Description, &r.IPAddress, &r.Device, &r.Status, &createdAt); err != nil {
			continue
		}
		if actorID.Valid {
			r.ActorID = &actorID.String
		}
		if targetID.Valid {
			r.TargetID = &targetID.String
		}
		if r.Role == "" {
			r.Role = "system"
		}
		r.Role = auditRoleLabel(r.Role)
		if r.ActorName == "" && r.ActorID == nil {
			r.ActorName = "System"
		}
		if r.IPAddress == "" {
			r.IPAddress = "Unavailable"
		}
		r.CreatedAt = createdAt.Format(time.RFC3339)
		r.HighRisk = auditHighRisk(r.Action)
		out = append(out, r)
	}
	utils.SuccessWithMeta(c, http.StatusOK, "Audit logs fetched", out, page.Meta(len(out)))
}

// AdminGetAuditLogDetail - GET /admin/audit-logs/:id
func AdminGetAuditLogDetail(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "not a uuid")
		return
	}

	var r struct {
		ID          string          `json:"id"`
		ActorID     *string         `json:"actor_id"`
		ActorName   string          `json:"actor_name"`
		ActorEmail  string          `json:"actor_email"`
		Role        string          `json:"role"`
		Action      string          `json:"action"`
		Module      string          `json:"module"`
		TargetType  string          `json:"target_type"`
		TargetID    *string         `json:"target_id"`
		Description string          `json:"description"`
		IPAddress   string          `json:"ip_address"`
		UserAgent   string          `json:"user_agent"`
		Device      string          `json:"device"`
		Status      string          `json:"status"`
		RequestID   string          `json:"request_id"`
		CreatedAt   string          `json:"created_at"`
		Before      json.RawMessage `json:"before"`
		After       json.RawMessage `json:"after"`
	}
	var actorID, targetID, requestID sql.NullString
	var before, after sql.NullString
	var createdAt time.Time
	err := config.DB.QueryRow(`
		SELECT al.id, al.user_id, COALESCE(u.name,''), COALESCE(u.email,''),
		       COALESCE(al.actor_role, ur.name, ''), al.action, COALESCE(al.module,''),
		       COALESCE(al.target_type,''), al.reference_id, COALESCE(al.description,''),
		       COALESCE(al.ip_address,''), COALESCE(al.user_agent,''), COALESCE(al.device_type,''),
		       al.status, al.request_id::text, al.created_at,
		       al.old_values::text, al.new_values::text
		FROM audit_logs al
		LEFT JOIN users u ON al.user_id = u.id
		LEFT JOIN roles ur ON u.role_id = ur.id
		WHERE al.id = $1::uuid
	`, id).Scan(&r.ID, &actorID, &r.ActorName, &r.ActorEmail, &r.Role, &r.Action, &r.Module,
		&r.TargetType, &targetID, &r.Description, &r.IPAddress, &r.UserAgent, &r.Device,
		&r.Status, &requestID, &createdAt, &before, &after)
	if err != nil {
		utils.Error(c, http.StatusNotFound, "Audit log not found", err.Error())
		return
	}
	if actorID.Valid {
		r.ActorID = &actorID.String
	}
	if targetID.Valid {
		r.TargetID = &targetID.String
	}
	if r.Role == "" {
		r.Role = "system"
	}
	r.Role = auditRoleLabel(r.Role)
	if r.ActorName == "" && r.ActorID == nil {
		r.ActorName = "System"
	}
	if r.IPAddress == "" {
		r.IPAddress = "Unavailable"
	}
	if requestID.Valid {
		r.RequestID = requestID.String
	}
	r.CreatedAt = createdAt.Format(time.RFC3339)
	if before.Valid {
		r.Before = json.RawMessage(before.String)
	}
	if after.Valid {
		r.After = json.RawMessage(after.String)
	}

	utils.Success(c, http.StatusOK, "Audit log detail fetched", r)
}
