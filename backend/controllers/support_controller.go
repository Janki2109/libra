package controllers

import (
	"database/sql"
	"libra/config"
	"libra/utils"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

// ─── SUPPORT / COMPLAINTS — user-facing (Client, Lawyer, Student) ───────
//
// Any authenticated user can create a ticket and see/reply to their own —
// never another user's. The Super Admin management surface lives in
// admin_support_controller.go, gated by the same super_admin route group as
// every other admin endpoint.

func validSupportCategory(s string) bool {
	switch s {
	case "booking", "payment", "refund", "payout", "subscription", "account",
		"lawyer", "client", "student", "documents", "technical", "other":
		return true
	}
	return false
}

// CreateSupportTicket - POST /support/tickets
func CreateSupportTicket(c *gin.Context) {
	userID := utils.UserID(c)
	role := utils.Role(c)
	if role == "super_admin" {
		utils.Error(c, http.StatusForbidden, "Super Admin cannot file a support ticket", "")
		return
	}

	var req struct {
		Subject     string `json:"subject" binding:"required"`
		Description string `json:"description" binding:"required"`
		Category    string `json:"category"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}
	if req.Category == "" {
		req.Category = "other"
	}
	if !validSupportCategory(req.Category) {
		utils.Error(c, http.StatusBadRequest, "Invalid category", "")
		return
	}

	var id, ticketNumber string
	err := config.DB.QueryRow(`
		INSERT INTO support_tickets (id, ticket_number, user_id, subject, description, category)
		VALUES (gen_random_uuid(), 'SUP-' || nextval('support_ticket_number_seq'), $1::uuid, $2, $3, $4)
		RETURNING id, ticket_number
	`, userID, req.Subject, req.Description, req.Category).Scan(&id, &ticketNumber)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to create ticket", err.Error())
		return
	}

	config.DB.Exec(`
		INSERT INTO support_ticket_history (id, ticket_id, actor_user_id, actor_role, action, after_value)
		VALUES (gen_random_uuid(), $1::uuid, $2::uuid, $3, 'TICKET_CREATED', $4)
	`, id, userID, role, req.Subject)

	// Every Super Admin is notified of a new, unassigned ticket — there is no
	// separate support-queue owner role to route it to instead.
	rows, _ := config.DB.Query(`SELECT u.id FROM users u JOIN roles r ON u.role_id = r.id WHERE r.name = 'super_admin'`)
	if rows != nil {
		defer rows.Close()
		for rows.Next() {
			var adminID string
			if rows.Scan(&adminID) == nil {
				utils.NotifyWithRef(adminID, "", "New support ticket "+ticketNumber,
					req.Subject, "support_ticket", id, "support_ticket")
			}
		}
	}

	utils.Success(c, http.StatusCreated, "Support ticket created", gin.H{"id": id, "ticket_number": ticketNumber})
}

// GetMySupportTickets - GET /support/tickets
func GetMySupportTickets(c *gin.Context) {
	userID := utils.UserID(c)
	page := ParsePagination(c)

	rows, err := config.DB.Query(`
		SELECT id, ticket_number, subject, category, priority, status, created_at, updated_at
		FROM support_tickets WHERE user_id = $1::uuid
		ORDER BY updated_at DESC LIMIT $2 OFFSET $3
	`, userID, page.Limit, page.Offset)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch tickets", err.Error())
		return
	}
	defer rows.Close()

	type Row struct {
		ID           string `json:"id"`
		TicketNumber string `json:"ticket_number"`
		Subject      string `json:"subject"`
		Category     string `json:"category"`
		Priority     string `json:"priority"`
		Status       string `json:"status"`
		CreatedAt    string `json:"created_at"`
		UpdatedAt    string `json:"updated_at"`
	}
	out := []Row{}
	for rows.Next() {
		var r Row
		var createdAt, updatedAt time.Time
		if err := rows.Scan(&r.ID, &r.TicketNumber, &r.Subject, &r.Category, &r.Priority, &r.Status, &createdAt, &updatedAt); err != nil {
			continue
		}
		r.CreatedAt = createdAt.Format(time.RFC3339)
		r.UpdatedAt = updatedAt.Format(time.RFC3339)
		out = append(out, r)
	}
	utils.SuccessWithMeta(c, http.StatusOK, "Support tickets fetched", out, page.Meta(len(out)))
}

// GetMySupportTicketDetail - GET /support/tickets/:id
func GetMySupportTicketDetail(c *gin.Context) {
	userID := utils.UserID(c)
	id := c.Param("id")
	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "")
		return
	}

	var ticket gin.H
	var ticketNumber, subject, description, category, priority, status string
	var resolutionNote sql.NullString
	var createdAt, updatedAt time.Time
	var resolvedAt sql.NullTime
	err := config.DB.QueryRow(`
		SELECT ticket_number, subject, description, category, priority, status,
		       resolution_note, created_at, updated_at, resolved_at
		FROM support_tickets WHERE id = $1::uuid AND user_id = $2::uuid
	`, id, userID).Scan(&ticketNumber, &subject, &description, &category, &priority, &status,
		&resolutionNote, &createdAt, &updatedAt, &resolvedAt)
	if err != nil {
		utils.Error(c, http.StatusNotFound, "Ticket not found", "")
		return
	}
	ticket = gin.H{
		"id": id, "ticket_number": ticketNumber, "subject": subject, "description": description,
		"category": category, "priority": priority, "status": status,
		"created_at": createdAt.Format(time.RFC3339), "updated_at": updatedAt.Format(time.RFC3339),
	}
	if resolutionNote.Valid {
		ticket["resolution_note"] = resolutionNote.String
	}
	if resolvedAt.Valid {
		ticket["resolved_at"] = resolvedAt.Time.Format(time.RFC3339)
	}

	messages := fetchSupportMessages(id)
	utils.Success(c, http.StatusOK, "Ticket detail fetched", gin.H{"ticket": ticket, "messages": messages})
}

// fetchSupportMessages is shared between the user-facing and admin detail
// endpoints — the conversation is the same data either way.
func fetchSupportMessages(ticketID string) []gin.H {
	rows, err := config.DB.Query(`
		SELECT sm.id, sm.sender_user_id, sm.sender_role, COALESCE(u.name,''), sm.message, sm.created_at
		FROM support_messages sm
		LEFT JOIN users u ON sm.sender_user_id = u.id
		WHERE sm.ticket_id = $1::uuid
		ORDER BY sm.created_at ASC
	`, ticketID)
	out := []gin.H{}
	if err != nil {
		return out
	}
	defer rows.Close()
	for rows.Next() {
		var id, senderID, role, name, message string
		var createdAt time.Time
		if rows.Scan(&id, &senderID, &role, &name, &message, &createdAt) != nil {
			continue
		}
		out = append(out, gin.H{
			"id": id, "sender_id": senderID, "sender_role": supportRoleLabel(role),
			"sender_name": name, "message": message, "created_at": createdAt.Format(time.RFC3339),
		})
	}
	return out
}

// ReplyToMySupportTicket - POST /support/tickets/:id/messages
func ReplyToMySupportTicket(c *gin.Context) {
	userID := utils.UserID(c)
	role := utils.Role(c)
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

	var status string
	var assignedAdmin sql.NullString
	err := config.DB.QueryRow(`
		SELECT status, assigned_super_admin_id::text FROM support_tickets WHERE id=$1::uuid AND user_id=$2::uuid
	`, id, userID).Scan(&status, &assignedAdmin)
	if err != nil {
		utils.Error(c, http.StatusNotFound, "Ticket not found", "")
		return
	}
	if status == "closed" {
		utils.Error(c, http.StatusBadRequest, "This ticket is closed", "reopen it to continue the conversation")
		return
	}

	config.DB.Exec(`
		INSERT INTO support_messages (id, ticket_id, sender_user_id, sender_role, message)
		VALUES (gen_random_uuid(), $1::uuid, $2::uuid, $3, $4)
	`, id, userID, role, req.Message)
	config.DB.Exec(`
		UPDATE support_tickets SET has_unread_user_reply = true, updated_at = NOW(),
		  status = CASE WHEN status = 'waiting_for_user' THEN 'in_progress' ELSE status END
		WHERE id = $1::uuid
	`, id)
	config.DB.Exec(`
		INSERT INTO support_ticket_history (id, ticket_id, actor_user_id, actor_role, action)
		VALUES (gen_random_uuid(), $1::uuid, $2::uuid, $3, 'USER_REPLIED')
	`, id, userID, role)

	if assignedAdmin.Valid && assignedAdmin.String != "" {
		utils.NotifyWithRef(assignedAdmin.String, "", "New reply on a support ticket",
			req.Message, "support_ticket", id, "support_ticket")
	}

	utils.Success(c, http.StatusOK, "Reply sent", nil)
}

// supportRoleLabel maps a stored role name to the fixed 4-role display
// label this app uses everywhere — never "ADMIN".
func supportRoleLabel(role string) string {
	switch role {
	case "super_admin":
		return "SUPER ADMIN"
	case "lawyer":
		return "LAWYER"
	case "client":
		return "CLIENT"
	case "law_student":
		return "STUDENT"
	default:
		return "UNKNOWN"
	}
}
