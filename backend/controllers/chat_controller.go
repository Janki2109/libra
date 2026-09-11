package controllers

import (
	"database/sql"
	"fmt"
	"libra/config"
	"libra/utils"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

func GetChatRooms(c *gin.Context) {
	role := utils.Role(c)

	var rows *sql.Rows
	var err error

	// fmt.Sprintf("%v", nil) yields the literal string "<nil>", which then
	// blew up the ::uuid cast with a 500 instead of an empty list.
	uID := utils.UserID(c)
	fID := utils.FirmID(c)

	if role == "client" {
		// ✅ Client sees LAWYER name
		rows, err = config.DB.Query(`
			SELECT cr.id,
			       COALESCE(u.name,'Your Lawyer') as lawyer_name,
			       COALESCE(cr.last_message,'') as last_message,
			       COALESCE(cr.last_message_at::text,'') as last_message_at,
			       COALESCE(u.name,'Your Lawyer') as other_name,
			       cr.created_at
			FROM chat_rooms cr
			LEFT JOIN users u ON cr.lawyer_id = u.id
			WHERE cr.client_id = (
				SELECT id FROM clients WHERE email=(
					SELECT email FROM users WHERE id=$1::uuid
				) LIMIT 1
			) AND cr.is_active = true
			ORDER BY cr.last_message_at DESC NULLS LAST
		`, uID)
	} else if role == "law_student" {
		// Student sees lawyer name
		rows, err = config.DB.Query(`
			SELECT cr.id,
			       COALESCE(u.name,'Lawyer') as lawyer_name,
			       COALESCE(cr.last_message,'') as last_message,
			       COALESCE(cr.last_message_at::text,'') as last_message_at,
			       COALESCE(u.name,'Lawyer') as other_name,
			       cr.created_at
			FROM chat_rooms cr
			LEFT JOIN users u ON cr.lawyer_id = u.id
			WHERE cr.student_id = $1::uuid AND cr.is_active = true
			ORDER BY cr.last_message_at DESC NULLS LAST
		`, uID)
	} else {
		if fID == "" {
			utils.Success(c, http.StatusOK, "Rooms fetched", []interface{}{})
			return
		}
		// ✅ Lawyer sees the real name of whoever is on the other end — a
		// client (cr.client_id) or a law student (cr.student_id). Rooms with
		// no matching row in either previously fell back to the literal
		// placeholder "Client", which is what a student's room always did
		// since it only ever sets student_id, never client_id.
		rows, err = config.DB.Query(`
			SELECT cr.id,
			       COALESCE(NULLIF(cl.name,''), NULLIF(su.name,''), 'Client') as lawyer_name,
			       COALESCE(cr.last_message,'') as last_message,
			       COALESCE(cr.last_message_at::text,'') as last_message_at,
			       COALESCE(NULLIF(cl.name,''), NULLIF(su.name,''), 'Client') as other_name,
			       cr.created_at
			FROM chat_rooms cr
			LEFT JOIN clients cl ON cr.client_id = cl.id
			LEFT JOIN users su ON cr.student_id = su.id
			WHERE cr.firm_id=$1::uuid AND cr.is_active=true
			ORDER BY cr.last_message_at DESC NULLS LAST
		`, fID)
	}

	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch rooms", err.Error())
		return
	}
	defer rows.Close()

	type Room struct {
		ID          string    `json:"id"`
		LawyerName  string    `json:"lawyer_name"`
		LastMessage string    `json:"last_message"`
		LastMsgAt   string    `json:"last_message_at"`
		OtherName   string    `json:"other_name"`
		CreatedAt   time.Time `json:"created_at"`
	}
	rooms := []Room{}
	for rows.Next() {
		var r Room
		rows.Scan(&r.ID, &r.LawyerName, &r.LastMessage,
			&r.LastMsgAt, &r.OtherName, &r.CreatedAt)
		rooms = append(rooms, r)
	}
	utils.Success(c, http.StatusOK, "Rooms fetched", rooms)
}

func CreateChatRoom(c *gin.Context) {
	firmID := utils.FirmID(c)
	userID := utils.UserID(c)
	role := utils.Role(c)

	var req struct {
		ClientID string `json:"client_id"`
		LawyerID string `json:"lawyer_id"`
		CaseID   string `json:"case_id"`
		RoomName string `json:"room_name"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}

	var lawyerID, clientID string

	if role == "law_student" {
		// Student creating room with a lawyer
		lawyerID = req.LawyerID
		if !isUUID(lawyerID) {
			utils.Error(c, http.StatusBadRequest, "lawyer_id required", "")
			return
		}
		// Only a real, active lawyer may be messaged. Without this a student
		// could open a room against any user id, including another student's.
		var one int
		if config.DB.QueryRow(`
			SELECT 1 FROM users u JOIN roles r ON u.role_id = r.id
			WHERE u.id=$1::uuid AND u.is_active=true AND r.name IN ('admin','lawyer')
		`, lawyerID).Scan(&one) != nil {
			utils.Error(c, http.StatusBadRequest, "Unknown lawyer", "no such active lawyer")
			return
		}
		// Check existing
		var existingID string
		config.DB.QueryRow(`
			SELECT id FROM chat_rooms 
			WHERE lawyer_id=$1::uuid AND student_id=$2::uuid AND is_active=true LIMIT 1
		`, lawyerID, userID).Scan(&existingID)
		if existingID != "" {
			utils.Success(c, http.StatusOK, "Room exists", gin.H{"id": existingID})
			return
		}

		var lawyerName string
		config.DB.QueryRow("SELECT name FROM users WHERE id=$1::uuid", lawyerID).Scan(&lawyerName)

		id := uuid.New().String()
		// The old code retried a second, near-identical INSERT whenever the
		// first failed and then reported success regardless — so a genuine
		// failure returned a room id that did not exist.
		_, err := config.DB.Exec(`
			INSERT INTO chat_rooms (id, firm_id, lawyer_id, student_id, room_name)
			VALUES ($1, (SELECT firm_id FROM users WHERE id=$2::uuid), $2::uuid, $3::uuid, $4)
		`, id, lawyerID, userID, lawyerName)
		if err != nil {
			utils.Error(c, http.StatusInternalServerError, "Failed to create room", err.Error())
			return
		}
		utils.Success(c, http.StatusCreated, "Room created", gin.H{"id": id, "room_name": lawyerName})
		return
	}

	if role == "client" {
		// Client opening/creating a room with a lawyer (e.g. from a confirmed
		// consultation's "Chat with Lawyer" button).
		//
		// This used to fall through into the lawyer branch below, which calls
		// RequireFirm — but a client who signed up directly (ClientRegister)
		// has no firm_id; their firm association only exists per-lawyer, via a
		// row in `clients` that a lawyer normally creates when onboarding them
		// (provisionPortalUser). A client who instead booked a consultation
		// straight from the app never got that row, so RequireFirm always
		// wrote a 403 before the request reached any real authorization logic
		// — that was the actual cause of "Chat with Lawyer" failing.
		lawyerID = req.LawyerID
		if !isUUID(lawyerID) {
			utils.Error(c, http.StatusBadRequest, "lawyer_id required", "")
			return
		}
		var lawyerName, lawyerFirmID string
		if err := config.DB.QueryRow(`
			SELECT u.name, u.firm_id::text FROM users u JOIN roles r ON u.role_id = r.id
			WHERE u.id=$1::uuid AND u.is_active=true AND r.name IN ('admin','lawyer')
		`, lawyerID).Scan(&lawyerName, &lawyerFirmID); err != nil || lawyerFirmID == "" {
			utils.Error(c, http.StatusBadRequest, "Unknown lawyer", "no such active lawyer")
			return
		}

		// Chat is a premium feature: a client may only message a lawyer they
		// have at least one paid consultation with. This used to be enforced
		// only in the app's UI (which hid the button) — nothing stopped a
		// client from calling this endpoint directly and opening a room with
		// zero paid consultations.
		var hasPaidConsultation bool
		config.DB.QueryRow(`
			SELECT EXISTS(
				SELECT 1 FROM consultations
				WHERE client_id=$1::uuid AND lawyer_id=$2::uuid AND payment_status='paid'
			)
		`, userID, lawyerID).Scan(&hasPaidConsultation)
		if !hasPaidConsultation {
			utils.Error(c, http.StatusPaymentRequired,
				"Chat unlocks once you book a paid consultation with this lawyer", "")
			return
		}

		// chat_rooms.client_id is a hard foreign key into `clients`, not
		// `users` — so the caller's own row there is found (or, the first
		// time they message this particular firm, created) rather than ever
		// trusting a client_id supplied in the request body.
		var callerName, callerEmail, callerPhone string
		config.DB.QueryRow(`SELECT name, email, COALESCE(phone,'') FROM users WHERE id=$1::uuid`,
			userID).Scan(&callerName, &callerEmail, &callerPhone)
		if callerEmail == "" {
			utils.Error(c, http.StatusForbidden, "Account not recognised", "no verified identity")
			return
		}

		var clientRowID string
		err := config.DB.QueryRow(`
			SELECT id FROM clients WHERE firm_id=$1::uuid AND lower(email)=lower($2) LIMIT 1
		`, lawyerFirmID, callerEmail).Scan(&clientRowID)
		if err != nil {
			clientRowID = uuid.New().String()
			if _, err := config.DB.Exec(`
				INSERT INTO clients (id, firm_id, name, email, phone)
				VALUES ($1, $2::uuid, $3, $4, $5)
			`, clientRowID, lawyerFirmID, callerName, callerEmail, callerPhone); err != nil {
				utils.Error(c, http.StatusInternalServerError, "Failed to set up client record", err.Error())
				return
			}
		}
		clientID = clientRowID

		var existingID string
		config.DB.QueryRow(`
			SELECT id FROM chat_rooms
			WHERE lawyer_id=$1::uuid AND client_id=$2::uuid AND is_active=true LIMIT 1
		`, lawyerID, clientID).Scan(&existingID)
		if existingID != "" {
			utils.Success(c, http.StatusOK, "Room exists", gin.H{"id": existingID})
			return
		}

		roomName := req.RoomName
		if roomName == "" {
			roomName = lawyerName
		}

		id := uuid.New().String()
		if _, err := config.DB.Exec(`
			INSERT INTO chat_rooms (id, firm_id, client_id, lawyer_id, room_name)
			VALUES ($1, $2::uuid, $3::uuid, $4::uuid, $5)
		`, id, lawyerFirmID, clientID, lawyerID, roomName); err != nil {
			utils.Error(c, http.StatusInternalServerError, "Failed to create room", err.Error())
			return
		}
		utils.Success(c, http.StatusCreated, "Room created", gin.H{"id": id, "room_name": roomName})
		return
	}

	// Lawyer creating room with client
	firmID, ok := utils.RequireFirm(c)
	if !ok {
		return
	}
	clientID = req.ClientID
	// A lawyer could previously open a room against another firm's client id,
	// which would then have shown that client's name and let the lawyer
	// message them.
	if !isUUID(clientID) || !belongsToFirm(tblClients, clientID, firmID) {
		utils.Error(c, http.StatusBadRequest, "Unknown client", "client not in caller's firm")
		return
	}
	if !belongsToFirm(tblCases, req.CaseID, firmID) {
		utils.Error(c, http.StatusBadRequest, "Unknown case", "case not in caller's firm")
		return
	}
	lawyerID = userID

	// Check existing
	var existingID string
	config.DB.QueryRow(`
		SELECT id FROM chat_rooms 
		WHERE lawyer_id=$1::uuid AND client_id=$2::uuid AND is_active=true LIMIT 1
	`, lawyerID, clientID).Scan(&existingID)
	if existingID != "" {
		utils.Success(c, http.StatusOK, "Room exists", gin.H{"id": existingID})
		return
	}

	var clientName string
	config.DB.QueryRow("SELECT name FROM clients WHERE id=$1::uuid", clientID).Scan(&clientName)

	roomName := req.RoomName
	if roomName == "" {
		roomName = clientName
	}

	id := uuid.New().String()
	_, err := config.DB.Exec(`
		INSERT INTO chat_rooms (id, firm_id, client_id, lawyer_id, case_id, room_name)
		VALUES ($1, $2::uuid, $3::uuid, $4::uuid, $5, $6)
	`, id, firmID, clientID, lawyerID, nullIfEmpty(req.CaseID), roomName)

	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to create room", err.Error())
		return
	}
	utils.Success(c, http.StatusCreated, "Room created", gin.H{"id": id, "room_name": roomName})
}

func GetMessages(c *gin.Context) {
	roomID := c.Param("room_id")
	if !requireChatRoomAccess(c, roomID) {
		return
	}
	userID := utils.UserID(c)
	uID := userID

	// file_content is deliberately not selected here — same reasoning as
	// GetDocuments: dragging every attachment's full base64 body through a
	// list that's polled every 3 seconds would be enormous. HasFile tells
	// the bubble whether to show an attachment at all; the bytes are fetched
	// on demand from GET /chat/messages/:id/file only when opened.
	rows, err := config.DB.Query(`
		SELECT id, COALESCE(sender_id::text,''), sender_name,
		       sender_role, message, COALESCE(message_type,'text'),
		       COALESCE(file_url,''), COALESCE(file_name,''),
		       COALESCE(mime_type,''), (file_content IS NOT NULL AND file_content != ''),
		       is_read, is_deleted_by_sender, created_at
		FROM chat_messages
		WHERE room_id=$1::uuid AND is_deleted_by_sender=false
		ORDER BY created_at ASC
	`, roomID)

	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch messages", err.Error())
		return
	}
	defer rows.Close()

	type Message struct {
		ID                string    `json:"id"`
		SenderID          string    `json:"sender_id"`
		SenderName        string    `json:"sender_name"`
		SenderRole        string    `json:"sender_role"`
		Message           string    `json:"message"`
		MessageType       string    `json:"message_type"`
		FileURL           string    `json:"file_url"`
		FileName          string    `json:"file_name"`
		MimeType          string    `json:"mime_type"`
		HasFile           bool      `json:"has_file"`
		IsRead            bool      `json:"is_read"`
		IsDeletedBySender bool      `json:"is_deleted_by_sender"`
		IsMine            bool      `json:"is_mine"`
		CreatedAt         time.Time `json:"created_at"`
	}

	messages := []Message{}
	for rows.Next() {
		var m Message
		rows.Scan(&m.ID, &m.SenderID, &m.SenderName, &m.SenderRole,
			&m.Message, &m.MessageType, &m.FileURL, &m.FileName,
			&m.MimeType, &m.HasFile,
			&m.IsRead, &m.IsDeletedBySender, &m.CreatedAt)
		m.IsMine = m.SenderID == uID
		messages = append(messages, m)
	}

	// Mark as read
	config.DB.Exec(`
		UPDATE chat_messages SET is_read=true
		WHERE room_id=$1::uuid AND sender_id!=$2::uuid AND is_read=false
	`, roomID, userID)

	utils.Success(c, http.StatusOK, "Messages fetched", messages)
}

func SendMessage(c *gin.Context) {
	roomID := c.Param("room_id")
	if !requireChatRoomAccess(c, roomID) {
		return
	}
	userID := utils.UserID(c)
	role := utils.Role(c)

	var req struct {
		Message     string `json:"message"`
		MessageType string `json:"message_type"`
		FileURL     string `json:"file_url"`
		FileName    string `json:"file_name"`
		FileContent string `json:"file_content"` // base64, image/document attachments
		MimeType    string `json:"mime_type"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}
	// A message needs text or an attachment — not neither. binding:"required"
	// on Message alone would reject a photo/document sent with no caption,
	// which is the normal way people send an attachment.
	if req.Message == "" && req.FileContent == "" {
		utils.Error(c, http.StatusBadRequest, "Message text or an attachment is required", "")
		return
	}
	if len(req.FileContent) > maxInlineChatFileBytes {
		utils.Error(c, http.StatusRequestEntityTooLarge, "File too large", "attachment exceeds limit")
		return
	}

	var senderName string
	config.DB.QueryRow("SELECT name FROM users WHERE id=$1::uuid", userID).Scan(&senderName)

	msgType := req.MessageType
	if msgType == "" {
		msgType = "text"
	}

	id := uuid.New().String()
	now := time.Now()

	_, err := config.DB.Exec(`
		INSERT INTO chat_messages (id, room_id, sender_id, sender_name, sender_role,
		message, message_type, file_url, file_name, file_content, mime_type)
		VALUES ($1, $2::uuid, $3::uuid, $4, $5, $6, $7, $8, $9, $10, $11)
	`, id, roomID, userID, senderName, role,
		req.Message, msgType, req.FileURL, req.FileName,
		nullIfEmpty(req.FileContent), nullIfEmpty(req.MimeType))

	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to send message", err.Error())
		return
	}

	lastMessagePreview := req.Message
	if lastMessagePreview == "" {
		lastMessagePreview = "📎 " + req.FileName
	}
	config.DB.Exec(`
		UPDATE chat_rooms SET last_message=$1, last_message_at=NOW(), updated_at=NOW()
		WHERE id=$2::uuid
	`, lastMessagePreview, roomID)

	// The other side of this conversation previously never learned a message
	// had arrived except by reopening the chat — nothing notified them at
	// all. Same participant shape as requireChatRoomAccess above (lawyer,
	// student, or the client mapped through their portal email), sent after
	// the INSERT has already committed so this can never fire for a message
	// that didn't actually save.
	go notifyOtherChatParticipants(roomID, userID, senderName, lastMessagePreview)

	utils.Success(c, http.StatusCreated, "Message sent", gin.H{
		"id":           id,
		"sender_name":  senderName,
		"sender_role":  role,
		"message":      req.Message,
		"message_type": msgType,
		"file_url":     req.FileURL,
		"file_name":    req.FileName,
		"mime_type":    req.MimeType,
		"has_file":     req.FileContent != "",
		"is_mine":      true,
		"is_read":      false,
		"created_at":   now,
	})
}

// notifyOtherChatParticipants pushes a "new message" notification (existing
// FCM pipeline — utils.NotifyWithRef) to every participant on the room
// except whoever just sent it. A room has at most a lawyer, a student and a
// client, and any of them may be empty, so this notifies whichever of those
// resolve to a real user id and aren't the sender.
func notifyOtherChatParticipants(roomID, senderID, senderName, preview string) {
	var lawyerID, studentID, clientUserID, firmID sql.NullString
	err := config.DB.QueryRow(`
		SELECT cr.lawyer_id::text, cr.student_id::text,
		       (SELECT u.id::text FROM users u
		        JOIN clients cl ON cr.client_id = cl.id
		        WHERE lower(u.email) = lower(cl.email) LIMIT 1),
		       cr.firm_id::text
		FROM chat_rooms cr
		WHERE cr.id = $1::uuid
	`, roomID).Scan(&lawyerID, &studentID, &clientUserID, &firmID)
	if err != nil {
		return
	}

	title := fmt.Sprintf("New message from %s", senderName)
	for _, recipient := range []sql.NullString{lawyerID, studentID, clientUserID} {
		if !recipient.Valid || recipient.String == "" || recipient.String == senderID {
			continue
		}
		firm := ""
		if firmID.Valid {
			firm = firmID.String
		}
		utils.NotifyWithRef(recipient.String, firm, title, preview,
			"chat_message", roomID, "chat_room")
	}
}

// maxInlineChatFileBytes caps a base64 attachment stored directly on the
// message row — same 8MB ceiling as document uploads (maxInlineDocumentBytes
// in remaining_controllers.go), for the same reason: without a limit a
// single request can push an arbitrarily large string into Postgres.
const maxInlineChatFileBytes = 8 << 20

// GetMessageFile returns one message's attachment bytes — kept out of
// GetMessages (see the comment there) and fetched only when the recipient
// actually opens it.
func GetMessageFile(c *gin.Context) {
	messageID := c.Param("message_id")
	if !isUUID(messageID) {
		utils.Error(c, http.StatusBadRequest, "Invalid message id", "not a uuid")
		return
	}

	var roomID string
	var fileName, mimeType, fileContent sql.NullString
	err := config.DB.QueryRow(`
		SELECT room_id::text, file_name, mime_type, file_content
		FROM chat_messages WHERE id=$1::uuid AND is_deleted_by_sender=false
	`, messageID).Scan(&roomID, &fileName, &mimeType, &fileContent)
	if err == sql.ErrNoRows {
		utils.Error(c, http.StatusNotFound, "Message not found", "")
		return
	}
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Database error", err.Error())
		return
	}
	if !requireChatRoomAccess(c, roomID) {
		return
	}
	if !fileContent.Valid || fileContent.String == "" {
		utils.Error(c, http.StatusNotFound, "This message has no attachment", "")
		return
	}

	utils.Success(c, http.StatusOK, "Attachment fetched", gin.H{
		"file_name":    fileName.String,
		"mime_type":    mimeType.String,
		"file_content": fileContent.String,
	})
}

func DeleteMessage(c *gin.Context) {
	messageID := c.Param("message_id")
	if !isUUID(messageID) {
		utils.Error(c, http.StatusBadRequest, "Invalid message id", "not a uuid")
		return
	}
	uID := utils.UserID(c)

	var senderID, roomID string
	err := config.DB.QueryRow(
		"SELECT COALESCE(sender_id::text,''), room_id::text FROM chat_messages WHERE id=$1::uuid",
		messageID,
	).Scan(&senderID, &roomID)

	if err == sql.ErrNoRows {
		utils.Error(c, http.StatusNotFound, "Message not found", "")
		return
	}
	// Any other error used to fall through with an empty senderID, so a
	// database hiccup turned into a 403 rather than a 500.
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Database error", err.Error())
		return
	}

	if !requireChatRoomAccess(c, roomID) {
		return
	}

	if senderID != uID {
		utils.Error(c, http.StatusForbidden, "You can only delete your own messages", "")
		return
	}

	config.DB.Exec(`
		UPDATE chat_messages 
		SET is_deleted_by_sender=true, message='This message was deleted', deleted_at=NOW()
		WHERE id=$1::uuid
	`, messageID)

	utils.Success(c, http.StatusOK, "Message deleted", nil)
}

// onlineWindow is how recently a user must have made an authenticated
// request (see middleware.touchPresence) to be shown as "Online". Chat polls
// every 3s while open, so anyone actively using the app is comfortably
// within this window; it also covers the presence poll's own ~3s cadence
// (see GetRoomPresence below) plus the auth middleware's throttle.
const onlineWindow = 2 * time.Minute

// GetRoomPresence reports whether the other participant in a chat room is
// currently online, based on how recently they last made an authenticated
// request — real activity, not a value the client can just set to "online"
// itself. Polled by the chat screen alongside GetMessages.
func GetRoomPresence(c *gin.Context) {
	roomID := c.Param("room_id")
	if !requireChatRoomAccess(c, roomID) {
		return
	}
	userID := utils.UserID(c)

	var lawyerID string
	var clientID, studentID sql.NullString
	err := config.DB.QueryRow(`
		SELECT COALESCE(lawyer_id::text,''), client_id::text, student_id::text
		FROM chat_rooms WHERE id=$1::uuid
	`, roomID).Scan(&lawyerID, &clientID, &studentID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch presence", err.Error())
		return
	}

	// The other participant is whichever side of the room isn't the caller.
	var otherUserID string
	if lawyerID != "" && lawyerID != userID {
		otherUserID = lawyerID
	} else if studentID.Valid && studentID.String != "" {
		otherUserID = studentID.String
	} else if clientID.Valid && clientID.String != "" {
		// client_id points at `clients`, not `users` — resolve to the
		// client's own login by email, same join used everywhere else a
		// client's user account needs to be found from their client row.
		config.DB.QueryRow(`
			SELECT u.id::text FROM clients cl
			JOIN users u ON lower(u.email) = lower(cl.email)
			WHERE cl.id = $1::uuid LIMIT 1
		`, clientID.String).Scan(&otherUserID)
	}

	if otherUserID == "" {
		utils.Success(c, http.StatusOK, "Presence fetched", gin.H{
			"online": false, "last_seen": nil,
		})
		return
	}

	var lastActive sql.NullTime
	config.DB.QueryRow(`SELECT last_active_at FROM users WHERE id=$1::uuid`, otherUserID).
		Scan(&lastActive)

	online := lastActive.Valid && time.Since(lastActive.Time) < onlineWindow
	resp := gin.H{"online": online}
	if lastActive.Valid {
		resp["last_seen"] = lastActive.Time
	} else {
		resp["last_seen"] = nil
	}
	utils.Success(c, http.StatusOK, "Presence fetched", resp)
}

func GetUnreadCount(c *gin.Context) {
	userID, _ := c.Get("user_id")
	var count int
	config.DB.QueryRow(`
		SELECT COUNT(*) FROM chat_messages cm
		JOIN chat_rooms cr ON cm.room_id = cr.id
		WHERE cm.sender_id != $1::uuid AND cm.is_read=false
		AND (cr.lawyer_id=$1::uuid OR cr.firm_id=(
			SELECT firm_id FROM users WHERE id=$1::uuid
		))
	`, userID).Scan(&count)
	utils.Success(c, http.StatusOK, "Unread count", gin.H{"count": count})
}
