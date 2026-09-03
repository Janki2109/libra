package controllers

import (
	"database/sql"
	"fmt"
	"libra/config"
	"libra/utils"
	"net/http"

	"github.com/gin-gonic/gin"
)

// Every tenant-scoped table this package guards. Callers pass one of these
// constants rather than a free-form string, so the table name interpolated
// into the ownership query can never come from user input.
const (
	tblCases         = "cases"
	tblClients       = "clients"
	tblHearings      = "hearings"
	tblDocuments     = "documents"
	tblInvoices      = "invoices"
	tblPayments      = "payments"
	tblNotifications = "notifications"
	tblCaseNotes     = "case_notes"
	tblConsultations = "consultations"
)

// requireFirmResource verifies that the row identified by id exists and belongs
// to the caller's firm, writing the appropriate error response if not.
//
// Before this existed, every handler that took an `:id` path parameter queried
// on that id alone. Any authenticated user — including a client or a law
// student from an unrelated account — could read, edit, or close any other
// firm's case, client, invoice or document simply by knowing or guessing its
// UUID. For a legal practice tool that is a privilege breach, not just a bug.
func requireFirmResource(c *gin.Context, table, id string) (string, bool) {
	firmID, ok := utils.RequireFirm(c)
	if !ok {
		return "", false
	}

	if !isUUID(id) {
		utils.Error(c, http.StatusBadRequest, "Invalid id", "not a uuid")
		c.Abort()
		return "", false
	}

	// A platform-level super admin legitimately works across firms.
	if utils.IsPlatformAdmin(c) {
		return firmID, true
	}

	var found string
	query := fmt.Sprintf(
		`SELECT firm_id::text FROM %s WHERE id = $1::uuid AND firm_id = $2::uuid`, table)
	err := config.DB.QueryRow(query, id, firmID).Scan(&found)

	if err == sql.ErrNoRows {
		// Deliberately 404 rather than 403: telling a stranger "that id exists
		// but is not yours" confirms the record's existence.
		utils.Error(c, http.StatusNotFound, "Not found", "outside caller's firm")
		c.Abort()
		return "", false
	}
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Authorization check failed", err.Error())
		c.Abort()
		return "", false
	}

	return firmID, true
}

// firmStaffRole mirrors middleware.firmStaffRoles (unexported, and this
// package cannot import middleware without a cycle) — the roles that work
// inside a firm's workspace rather than being its client. Used by handlers
// like CreatePayment that sit outside the RequireFirmStaff() group (because
// a client must also reach them for their own records) but still need to
// tell "firm staff acting on a client's behalf" apart from "the client
// themselves".
func firmStaffRole(role string) bool {
	switch role {
	case "super_admin", "admin", "lawyer", "staff", "clerk":
		return true
	}
	return false
}

// isUUID does a shape check so a malformed path parameter fails fast with a
// 400 instead of surfacing a Postgres cast error as a 500.
func isUUID(s string) bool {
	if len(s) != 36 {
		return false
	}
	for i, ch := range s {
		switch i {
		case 8, 13, 18, 23:
			if ch != '-' {
				return false
			}
		default:
			isHex := (ch >= '0' && ch <= '9') ||
				(ch >= 'a' && ch <= 'f') ||
				(ch >= 'A' && ch <= 'F')
			if !isHex {
				return false
			}
		}
	}
	return true
}

// nullIfEmpty converts an optional id from the request body into a value the
// driver will store as SQL NULL rather than as the empty string, which fails
// every uuid cast.
func nullIfEmpty(s string) interface{} {
	if s == "" {
		return nil
	}
	return s
}

// belongsToFirm reports whether a row is inside the caller's firm without
// writing a response. Use it to validate ids supplied in a request body.
func belongsToFirm(table, id, firmID string) bool {
	if id == "" {
		return true // optional field, nothing to check
	}
	if !isUUID(id) || !isUUID(firmID) {
		return false
	}
	var one int
	query := fmt.Sprintf(
		`SELECT 1 FROM %s WHERE id = $1::uuid AND firm_id = $2::uuid`, table)
	return config.DB.QueryRow(query, id, firmID).Scan(&one) == nil
}

// requireChatRoomAccess verifies the caller is a participant in the room.
//
// GetMessages, SendMessage and DeleteMessage previously trusted the room_id in
// the URL outright. Any authenticated user could page through another firm's
// rooms by id and read — or post into — privileged lawyer/client
// correspondence. That is the single most sensitive data this product holds.
func requireChatRoomAccess(c *gin.Context, roomID string) bool {
	if !isUUID(roomID) {
		utils.Error(c, http.StatusBadRequest, "Invalid room id", "not a uuid")
		c.Abort()
		return false
	}

	userID := utils.UserID(c)
	if userID == "" {
		utils.Error(c, http.StatusUnauthorized, "Not authenticated", "")
		c.Abort()
		return false
	}

	// The caller is a participant if they are the room's lawyer, the law
	// student it was opened for (student_id is a direct users.id, unlike
	// client_id), or the client it was opened for (clients are matched to
	// their portal login by email address). student_id was missing here
	// entirely, which meant a law student could never open their own chat's
	// messages — every request 404'd as "not a participant".
	var one int
	err := config.DB.QueryRow(`
		SELECT 1 FROM chat_rooms cr
		LEFT JOIN clients cl ON cr.client_id = cl.id
		WHERE cr.id = $1::uuid
		  AND (
		    cr.lawyer_id = $2::uuid
		    OR cr.student_id = $2::uuid
		    OR lower(cl.email) = (SELECT lower(email) FROM users WHERE id = $2::uuid)
		  )
	`, roomID, userID).Scan(&one)

	if err == sql.ErrNoRows {
		utils.Error(c, http.StatusNotFound, "Conversation not found", "caller is not a participant")
		c.Abort()
		return false
	}
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Authorization check failed", err.Error())
		c.Abort()
		return false
	}
	return true
}

// userInFirm reports whether a user id belongs to the caller's firm. Users are
// checked separately from firm-owned records because staff rows live in the
// shared users table.
func userInFirm(userID, firmID string) bool {
	if userID == "" {
		return true
	}
	if !isUUID(userID) || !isUUID(firmID) {
		return false
	}
	var one int
	return config.DB.QueryRow(
		`SELECT 1 FROM users WHERE id = $1::uuid AND firm_id = $2::uuid`,
		userID, firmID,
	).Scan(&one) == nil
}
