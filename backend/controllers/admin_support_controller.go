package controllers

import (
	"database/sql"
	"fmt"
	"libra/config"
	"libra/utils"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

// ─── SUPPORT / COMPLAINTS — Super Admin management ──────────────────────
//
// Reuses support_tickets/support_messages/support_ticket_history
// (migration 029) and the existing utils.LogAudit/utils.Notify
// infrastructure — no parallel notification or audit system is created.
// Every write here also appends to support_ticket_history so the ticket's
// own timeline (section 18 of the spec) is always backed by real rows, the
// same append-only table every reader in this file also reads from.

func supportHistoryEntry(ticketID, actorID, actorRole, action, before, after string) {
	config.DB.Exec(`
		INSERT INTO support_ticket_history (id, ticket_id, actor_user_id, actor_role, action, before_value, after_value)
		VALUES (gen_random_uuid(), $1::uuid, NULLIF($2,'')::uuid, $3, $4, NULLIF($5,''), NULLIF($6,''))
	`, ticketID, actorID, actorRole, action, before, after)
}

func supportDateFilter(col, from, to string, args *[]interface{}) string {
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

// AdminGetSupportStats - GET /admin/support/stats
func AdminGetSupportStats(c *gin.Context) {
	var out struct {
		Total       int `json:"total_tickets"`
		Open        int `json:"open_tickets"`
		InProgress  int `json:"in_progress"`
		Resolved    int `json:"resolved"`
		Closed      int `json:"closed"`
		HighPriority int `json:"high_priority"`
	}
	config.DB.QueryRow(`SELECT COUNT(*) FROM support_tickets`).Scan(&out.Total)
	config.DB.QueryRow(`SELECT COUNT(*) FROM support_tickets WHERE status='open'`).Scan(&out.Open)
	config.DB.QueryRow(`SELECT COUNT(*) FROM support_tickets WHERE status IN ('in_progress','waiting_for_user')`).Scan(&out.InProgress)
	config.DB.QueryRow(`SELECT COUNT(*) FROM support_tickets WHERE status='resolved'`).Scan(&out.Resolved)
	config.DB.QueryRow(`SELECT COUNT(*) FROM support_tickets WHERE status='closed'`).Scan(&out.Closed)
	config.DB.QueryRow(`SELECT COUNT(*) FROM support_tickets WHERE priority IN ('high','urgent') AND status NOT IN ('resolved','closed')`).Scan(&out.HighPriority)
	utils.Success(c, http.StatusOK, "Support stats fetched", out)
}

// AdminGetSupportTickets - GET /admin/support/tickets
// ?search=&role=&status=&priority=&category=&assigned=&from=&to=&sort=&order=&page=&limit=
func AdminGetSupportTickets(c *gin.Context) {
	search := c.Query("search")
	role := c.Query("role")
	status := c.Query("status")
	priority := c.Query("priority")
	category := c.Query("category")
	assigned := c.Query("assigned") // "", "unassigned", or a super admin's user id
	from, to := c.Query("from"), c.Query("to")
	sortCol := map[string]string{
		"created_at": "st.created_at",
		"updated_at": "st.updated_at",
		"priority":   "st.priority",
		"status":     "st.status",
	}[c.DefaultQuery("sort", "updated_at")]
	if sortCol == "" {
		sortCol = "st.updated_at"
	}
	order := "DESC"
	if c.Query("order") == "asc" {
		order = "ASC"
	}
	page := ParsePagination(c)

	query := `
		SELECT st.id, st.ticket_number, u.id, u.name, u.email, COALESCE(ur.name,''),
		       st.subject, st.category, st.priority, st.status,
		       st.assigned_super_admin_id, COALESCE(admin.name,''),
		       st.has_unread_user_reply, st.created_at, st.updated_at
		FROM support_tickets st
		JOIN users u ON st.user_id = u.id
		LEFT JOIN roles ur ON u.role_id = ur.id
		LEFT JOIN users admin ON st.assigned_super_admin_id = admin.id
		WHERE 1=1`
	args := []interface{}{}
	if search != "" {
		args = append(args, "%"+search+"%")
		n := len(args)
		query += fmt.Sprintf(` AND (st.ticket_number ILIKE $%d OR u.name ILIKE $%d OR u.email ILIKE $%d
			OR u.id::text ILIKE $%d OR st.subject ILIKE $%d OR st.description ILIKE $%d)`, n, n, n, n, n, n)
	}
	if role != "" {
		args = append(args, role)
		query += fmt.Sprintf(` AND ur.name = $%d`, len(args))
	}
	if status != "" {
		args = append(args, status)
		query += fmt.Sprintf(` AND st.status = $%d`, len(args))
	}
	if priority != "" {
		args = append(args, priority)
		query += fmt.Sprintf(` AND st.priority = $%d`, len(args))
	}
	if category != "" {
		args = append(args, category)
		query += fmt.Sprintf(` AND st.category = $%d`, len(args))
	}
	if assigned == "unassigned" {
		query += ` AND st.assigned_super_admin_id IS NULL`
	} else if assigned != "" && isUUID(assigned) {
		args = append(args, assigned)
		query += fmt.Sprintf(` AND st.assigned_super_admin_id = $%d`, len(args))
	}
	query += supportDateFilter("st.created_at", from, to, &args)
	query += fmt.Sprintf(` ORDER BY %s %s`, sortCol, order)
	args = append(args, page.Limit, page.Offset)
	query += fmt.Sprintf(` LIMIT $%d OFFSET $%d`, len(args)-1, len(args))

	rows, err := config.DB.Query(query, args...)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch tickets", err.Error())
		return
	}
	defer rows.Close()

	type Row struct {
		ID             string  `json:"id"`
		TicketNumber   string  `json:"ticket_number"`
		UserID         string  `json:"user_id"`
		UserName       string  `json:"user_name"`
		UserEmail      string  `json:"user_email"`
		Role           string  `json:"role"`
		Subject        string  `json:"subject"`
		Category       string  `json:"category"`
		Priority       string  `json:"priority"`
		Status         string  `json:"status"`
		AssignedID     *string `json:"assigned_id"`
		AssignedName   string  `json:"assigned_name"`
		HasUnreadReply bool    `json:"has_unread_reply"`
		CreatedAt      string  `json:"created_at"`
		UpdatedAt      string  `json:"updated_at"`
	}
	out := []Row{}
	for rows.Next() {
		var r Row
		var assignedID sql.NullString
		var createdAt, updatedAt time.Time
		if err := rows.Scan(&r.ID, &r.TicketNumber, &r.UserID, &r.UserName, &r.UserEmail, &r.Role,
			&r.Subject, &r.Category, &r.Priority, &r.Status, &assignedID, &r.AssignedName,
			&r.HasUnreadReply, &createdAt, &updatedAt); err != nil {
			continue
		}
		if assignedID.Valid {
			r.AssignedID = &assignedID.String
		}
		r.Role = supportRoleLabel(r.Role)
		r.CreatedAt = createdAt.Format(time.RFC3339)
		r.UpdatedAt = updatedAt.Format(time.RFC3339)
		out = append(out, r)
	}
	utils.SuccessWithMeta(c, http.StatusOK, "Support tickets fetched", out, page.Meta(len(out)))
}

// AdminGetSupportTicketDetail - GET /admin/support/tickets/:id
// Viewing a ticket as Super Admin clears its unread-user-reply flag.
func AdminGetSupportTicketDetail(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "")
		return
	}

	var t struct {
		ID             string  `json:"id"`
		TicketNumber   string  `json:"ticket_number"`
		Subject        string  `json:"subject"`
		Description    string  `json:"description"`
		Category       string  `json:"category"`
		Priority       string  `json:"priority"`
		Status         string  `json:"status"`
		UserID         string  `json:"user_id"`
		UserName       string  `json:"user_name"`
		UserEmail      string  `json:"user_email"`
		UserPhone      string  `json:"user_phone"`
		Role           string  `json:"role"`
		AssignedID     *string `json:"assigned_id"`
		AssignedName   string  `json:"assigned_name"`
		AssignedAt     *string `json:"assigned_at"`
		ResolutionNote *string `json:"resolution_note"`
		ResolvedByName string  `json:"resolved_by_name"`
		ResolvedAt     *string `json:"resolved_at"`
		ClosedByName   string  `json:"closed_by_name"`
		ClosedAt       *string `json:"closed_at"`
		CreatedAt      string  `json:"created_at"`
		UpdatedAt      string  `json:"updated_at"`
	}
	var assignedID, resolutionNote sql.NullString
	var assignedAt, resolvedAt, closedAt sql.NullTime
	var resolvedByName, closedByName sql.NullString
	var createdAt, updatedAt time.Time
	err := config.DB.QueryRow(`
		SELECT st.id, st.ticket_number, st.subject, st.description, st.category, st.priority, st.status,
		       u.id, u.name, u.email, COALESCE(u.phone,''), COALESCE(ur.name,''),
		       st.assigned_super_admin_id, COALESCE(admin.name,''), st.assigned_at,
		       st.resolution_note, resolver.name, st.resolved_at,
		       closer.name, st.closed_at, st.created_at, st.updated_at
		FROM support_tickets st
		JOIN users u ON st.user_id = u.id
		LEFT JOIN roles ur ON u.role_id = ur.id
		LEFT JOIN users admin ON st.assigned_super_admin_id = admin.id
		LEFT JOIN users resolver ON st.resolved_by = resolver.id
		LEFT JOIN users closer ON st.closed_by = closer.id
		WHERE st.id = $1::uuid
	`, id).Scan(&t.ID, &t.TicketNumber, &t.Subject, &t.Description, &t.Category, &t.Priority, &t.Status,
		&t.UserID, &t.UserName, &t.UserEmail, &t.UserPhone, &t.Role,
		&assignedID, &t.AssignedName, &assignedAt, &resolutionNote, &resolvedByName, &resolvedAt,
		&closedByName, &closedAt, &createdAt, &updatedAt)
	if err != nil {
		utils.Error(c, http.StatusNotFound, "Ticket not found", err.Error())
		return
	}
	if assignedID.Valid {
		t.AssignedID = &assignedID.String
	}
	if assignedAt.Valid {
		s := assignedAt.Time.Format(time.RFC3339)
		t.AssignedAt = &s
	}
	if resolutionNote.Valid {
		t.ResolutionNote = &resolutionNote.String
	}
	if resolvedByName.Valid {
		t.ResolvedByName = resolvedByName.String
	}
	if resolvedAt.Valid {
		s := resolvedAt.Time.Format(time.RFC3339)
		t.ResolvedAt = &s
	}
	if closedByName.Valid {
		t.ClosedByName = closedByName.String
	}
	if closedAt.Valid {
		s := closedAt.Time.Format(time.RFC3339)
		t.ClosedAt = &s
	}
	t.Role = supportRoleLabel(t.Role)
	t.CreatedAt = createdAt.Format(time.RFC3339)
	t.UpdatedAt = updatedAt.Format(time.RFC3339)

	config.DB.Exec(`UPDATE support_tickets SET has_unread_user_reply = false WHERE id = $1::uuid`, id)

	messages := fetchSupportMessages(id)

	historyRows, _ := config.DB.Query(`
		SELECT h.id, COALESCE(a.name,''), h.actor_role, h.action, COALESCE(h.before_value,''), COALESCE(h.after_value,''), h.created_at
		FROM support_ticket_history h
		LEFT JOIN users a ON h.actor_user_id = a.id
		WHERE h.ticket_id = $1::uuid
		ORDER BY h.created_at ASC
	`, id)
	history := []gin.H{}
	if historyRows != nil {
		defer historyRows.Close()
		for historyRows.Next() {
			var hid, actorName, actorRole, action, before, after string
			var createdAt time.Time
			if historyRows.Scan(&hid, &actorName, &actorRole, &action, &before, &after, &createdAt) != nil {
				continue
			}
			history = append(history, gin.H{
				"id": hid, "actor_name": actorName, "actor_role": supportRoleLabel(actorRole),
				"action": action, "before": before, "after": after, "created_at": createdAt.Format(time.RFC3339),
			})
		}
	}

	utils.Success(c, http.StatusOK, "Ticket detail fetched", gin.H{
		"ticket": t, "messages": messages, "history": history,
	})
}

// AdminAssignSupportTicket - PUT /admin/support/tickets/:id/assign
// {"super_admin_id": "..."} or {"super_admin_id": ""} to unassign.
func AdminAssignSupportTicket(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "")
		return
	}
	var req struct {
		SuperAdminID string `json:"super_admin_id"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}
	if req.SuperAdminID != "" {
		var isSuper bool
		config.DB.QueryRow(`
			SELECT r.name = 'super_admin' FROM users u JOIN roles r ON u.role_id = r.id WHERE u.id = $1::uuid
		`, req.SuperAdminID).Scan(&isSuper)
		if !isSuper {
			utils.Error(c, http.StatusBadRequest, "Tickets can only be assigned to a Super Admin", "")
			return
		}
	}

	var previousID sql.NullString
	config.DB.QueryRow(`SELECT assigned_super_admin_id::text FROM support_tickets WHERE id=$1::uuid`, id).Scan(&previousID)

	_, err := config.DB.Exec(`
		UPDATE support_tickets SET assigned_super_admin_id = NULLIF($1,'')::uuid,
		  assigned_at = CASE WHEN NULLIF($1,'') IS NULL THEN NULL ELSE NOW() END, updated_at = NOW()
		WHERE id = $2::uuid
	`, req.SuperAdminID, id)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to update assignment", err.Error())
		return
	}

	actorID, actorRole := utils.UserID(c), utils.Role(c)
	action := "SUPPORT_TICKET_ASSIGNED"
	if previousID.Valid && previousID.String != "" {
		if req.SuperAdminID == "" {
			action = "SUPPORT_TICKET_UNASSIGNED"
		} else {
			action = "SUPPORT_TICKET_REASSIGNED"
		}
	}
	supportHistoryEntry(id, actorID, actorRole, action, previousID.String, req.SuperAdminID)
	utils.LogAudit(c, utils.AuditEntry{
		Action: action, Module: "support", TargetType: "support_ticket", TargetID: id,
		Description: "Support ticket assignment changed",
		Before:      map[string]string{"assigned_super_admin_id": previousID.String},
		After:       map[string]string{"assigned_super_admin_id": req.SuperAdminID},
	})
	if req.SuperAdminID != "" {
		utils.NotifyWithRef(req.SuperAdminID, "", "A support ticket was assigned to you",
			"You have a new support ticket to handle.", "support_ticket", id, "support_ticket")
	}

	utils.Success(c, http.StatusOK, "Assignment updated", nil)
}

// AdminUpdateSupportPriority - PUT /admin/support/tickets/:id/priority
func AdminUpdateSupportPriority(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "")
		return
	}
	var req struct {
		Priority string `json:"priority" binding:"required,oneof=low medium high urgent"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}
	var previous string
	config.DB.QueryRow(`SELECT priority FROM support_tickets WHERE id=$1::uuid`, id).Scan(&previous)
	if _, err := config.DB.Exec(`UPDATE support_tickets SET priority=$1, updated_at=NOW() WHERE id=$2::uuid`, req.Priority, id); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to update priority", err.Error())
		return
	}
	actorID, actorRole := utils.UserID(c), utils.Role(c)
	supportHistoryEntry(id, actorID, actorRole, "SUPPORT_PRIORITY_CHANGED", previous, req.Priority)
	utils.LogAudit(c, utils.AuditEntry{
		Action: "SUPPORT_PRIORITY_CHANGED", Module: "support", TargetType: "support_ticket", TargetID: id,
		Description: "Support ticket priority changed",
		Before:      map[string]string{"priority": previous}, After: map[string]string{"priority": req.Priority},
	})
	utils.Success(c, http.StatusOK, "Priority updated", nil)
}

// AdminUpdateSupportStatus - PUT /admin/support/tickets/:id/status
// For the plain in_progress/waiting_for_user transitions; resolve/close/
// reopen are their own endpoints since they require extra data/rules.
func AdminUpdateSupportStatus(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "")
		return
	}
	var req struct {
		Status string `json:"status" binding:"required,oneof=open in_progress waiting_for_user"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}
	var previous string
	config.DB.QueryRow(`SELECT status FROM support_tickets WHERE id=$1::uuid`, id).Scan(&previous)
	if previous == "closed" {
		utils.Error(c, http.StatusBadRequest, "This ticket is closed", "reopen it first")
		return
	}
	if _, err := config.DB.Exec(`UPDATE support_tickets SET status=$1, updated_at=NOW() WHERE id=$2::uuid`, req.Status, id); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to update status", err.Error())
		return
	}
	actorID, actorRole := utils.UserID(c), utils.Role(c)
	supportHistoryEntry(id, actorID, actorRole, "SUPPORT_STATUS_CHANGED", previous, req.Status)
	utils.LogAudit(c, utils.AuditEntry{
		Action: "SUPPORT_STATUS_CHANGED", Module: "support", TargetType: "support_ticket", TargetID: id,
		Description: "Support ticket status changed",
		Before:      map[string]string{"status": previous}, After: map[string]string{"status": req.Status},
	})
	utils.Success(c, http.StatusOK, "Status updated", nil)
}

// AdminReplySupportTicket - POST /admin/support/tickets/:id/messages
func AdminReplySupportTicket(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "")
		return
	}
	var req struct {
		Message string `json:"message" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}
	var ticketOwnerID, status string
	if err := config.DB.QueryRow(`SELECT user_id::text, status FROM support_tickets WHERE id=$1::uuid`, id).
		Scan(&ticketOwnerID, &status); err != nil {
		utils.Error(c, http.StatusNotFound, "Ticket not found", "")
		return
	}

	actorID, actorRole := utils.UserID(c), utils.Role(c)
	config.DB.Exec(`
		INSERT INTO support_messages (id, ticket_id, sender_user_id, sender_role, message)
		VALUES (gen_random_uuid(), $1::uuid, $2::uuid, $3, $4)
	`, id, actorID, actorRole, req.Message)
	config.DB.Exec(`
		UPDATE support_tickets SET updated_at = NOW(),
		  status = CASE WHEN status = 'open' THEN 'in_progress' ELSE status END
		WHERE id = $1::uuid
	`, id)
	supportHistoryEntry(id, actorID, actorRole, "SUPPORT_REPLY_SENT", "", "")
	utils.LogAudit(c, utils.AuditEntry{
		Action: "SUPPORT_REPLY_SENT", Module: "support", TargetType: "support_ticket", TargetID: id,
		Description: "Super Admin replied to support ticket",
	})
	utils.NotifyWithRef(ticketOwnerID, "", "New reply on your support ticket",
		req.Message, "support_ticket", id, "support_ticket")

	utils.Success(c, http.StatusOK, "Reply sent", nil)
}

// AdminResolveSupportTicket - PUT /admin/support/tickets/:id/resolve
func AdminResolveSupportTicket(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "")
		return
	}
	var req struct {
		ResolutionNote string `json:"resolution_note" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}
	var previous, ticketOwnerID string
	config.DB.QueryRow(`SELECT status, user_id::text FROM support_tickets WHERE id=$1::uuid`, id).Scan(&previous, &ticketOwnerID)
	if previous == "closed" {
		utils.Error(c, http.StatusBadRequest, "This ticket is closed", "reopen it first")
		return
	}
	actorID, actorRole := utils.UserID(c), utils.Role(c)
	if _, err := config.DB.Exec(`
		UPDATE support_tickets SET status='resolved', resolution_note=$1, resolved_by=$2::uuid, resolved_at=NOW(), updated_at=NOW()
		WHERE id=$3::uuid
	`, req.ResolutionNote, actorID, id); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to resolve ticket", err.Error())
		return
	}
	supportHistoryEntry(id, actorID, actorRole, "SUPPORT_TICKET_RESOLVED", previous, "resolved")
	utils.LogAudit(c, utils.AuditEntry{
		Action: "SUPPORT_TICKET_RESOLVED", Module: "support", TargetType: "support_ticket", TargetID: id,
		Description: "Support ticket resolved",
		Before:      map[string]string{"status": previous}, After: map[string]string{"status": "resolved"},
	})
	utils.NotifyWithRef(ticketOwnerID, "", "Your support ticket was resolved",
		req.ResolutionNote, "support_ticket", id, "support_ticket")

	utils.Success(c, http.StatusOK, "Ticket resolved", nil)
}

// AdminCloseSupportTicket - PUT /admin/support/tickets/:id/close
func AdminCloseSupportTicket(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "")
		return
	}
	var previous string
	var resolutionNote sql.NullString
	config.DB.QueryRow(`SELECT status, resolution_note FROM support_tickets WHERE id=$1::uuid`, id).Scan(&previous, &resolutionNote)
	if previous != "resolved" {
		utils.Error(c, http.StatusBadRequest, "Only a resolved ticket can be closed", "add a resolution first")
		return
	}
	actorID, actorRole := utils.UserID(c), utils.Role(c)
	if _, err := config.DB.Exec(`
		UPDATE support_tickets SET status='closed', closed_by=$1::uuid, closed_at=NOW(), updated_at=NOW() WHERE id=$2::uuid
	`, actorID, id); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to close ticket", err.Error())
		return
	}
	supportHistoryEntry(id, actorID, actorRole, "SUPPORT_TICKET_CLOSED", previous, "closed")
	utils.LogAudit(c, utils.AuditEntry{
		Action: "SUPPORT_TICKET_CLOSED", Module: "support", TargetType: "support_ticket", TargetID: id,
		Description: "Support ticket closed",
		Before:      map[string]string{"status": previous}, After: map[string]string{"status": "closed"},
	})
	utils.Success(c, http.StatusOK, "Ticket closed", nil)
}

// AdminReopenSupportTicket - PUT /admin/support/tickets/:id/reopen
func AdminReopenSupportTicket(c *gin.Context) {
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "")
		return
	}
	var previous, ticketOwnerID string
	var assignedID sql.NullString
	config.DB.QueryRow(`SELECT status, user_id::text, assigned_super_admin_id::text FROM support_tickets WHERE id=$1::uuid`, id).
		Scan(&previous, &ticketOwnerID, &assignedID)
	if previous != "resolved" && previous != "closed" {
		utils.Error(c, http.StatusBadRequest, "Only a resolved or closed ticket can be reopened", "")
		return
	}
	actorID, actorRole := utils.UserID(c), utils.Role(c)
	// Resolution history (resolution_note/resolved_by/resolved_at) is
	// deliberately left in place — reopening starts a new work cycle, it
	// does not erase what happened before, per the "do not erase previous
	// resolution history" requirement.
	if _, err := config.DB.Exec(`UPDATE support_tickets SET status='open', updated_at=NOW() WHERE id=$1::uuid`, id); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to reopen ticket", err.Error())
		return
	}
	supportHistoryEntry(id, actorID, actorRole, "SUPPORT_TICKET_REOPENED", previous, "open")
	utils.LogAudit(c, utils.AuditEntry{
		Action: "SUPPORT_TICKET_REOPENED", Module: "support", TargetType: "support_ticket", TargetID: id,
		Description: "Support ticket reopened",
		Before:      map[string]string{"status": previous}, After: map[string]string{"status": "open"},
	})
	if assignedID.Valid && assignedID.String != "" {
		utils.NotifyWithRef(assignedID.String, "", "A support ticket was reopened",
			"A ticket assigned to you has been reopened.", "support_ticket", id, "support_ticket")
	}
	utils.Success(c, http.StatusOK, "Ticket reopened", nil)
}
