package controllers

import (
	"crypto/rand"
	"database/sql"
	"errors"
	"fmt"
	"libra/config"
	"libra/services"
	"libra/utils"
	"log"
	"math/big"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

func GetClients(c *gin.Context) {
	firmID, ok := utils.RequireFirm(c)
	if !ok {
		return
	}

	// As with cases, the old code fell back to an unscoped query on any error
	// and handed back other firms' client lists — and returned every row.
	page := ParsePagination(c)
	search := c.Query("q")

	rows, err := config.DB.Query(`
		SELECT id, name, COALESCE(email,''), COALESCE(phone,''),
		       COALESCE(city,''), COALESCE(state,''), is_active, created_at
		FROM clients
		WHERE firm_id = $1::uuid
		  AND ($2 = '' OR name ILIKE '%' || $2 || '%'
		               OR email ILIKE '%' || $2 || '%'
		               OR phone ILIKE '%' || $2 || '%')
		ORDER BY created_at DESC
		LIMIT $3 OFFSET $4
	`, firmID, search, page.Limit, page.Offset)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch clients", err.Error())
		return
	}
	defer rows.Close()

	type Client struct {
		ID        string    `json:"id"`
		Name      string    `json:"name"`
		Email     string    `json:"email"`
		Phone     string    `json:"phone"`
		City      string    `json:"city"`
		State     string    `json:"state"`
		IsActive  bool      `json:"is_active"`
		CreatedAt time.Time `json:"created_at"`
	}

	clients := []Client{}
	for rows.Next() {
		var cl Client
		if err := rows.Scan(&cl.ID, &cl.Name, &cl.Email, &cl.Phone,
			&cl.City, &cl.State, &cl.IsActive, &cl.CreatedAt); err != nil {
			utils.Error(c, http.StatusInternalServerError, "Failed to read clients", err.Error())
			return
		}
		clients = append(clients, cl)
	}
	if err := rows.Err(); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to read clients", err.Error())
		return
	}
	utils.SuccessWithMeta(c, http.StatusOK, "Clients fetched", clients, page.Meta(len(clients)))
}

func CreateClient(c *gin.Context) {
	firmID, ok := utils.RequireFirm(c)
	if !ok {
		return
	}
	uID := utils.UserID(c)

	if !enforcePlanLimit(c, firmID, limitClients) {
		return
	}

	var req struct {
		Name           string `json:"name" binding:"required"`
		Email          string `json:"email" binding:"omitempty,email"`
		Phone          string `json:"phone"`
		AlternatePhone string `json:"alternate_phone"`
		Address        string `json:"address"`
		City           string `json:"city"`
		State          string `json:"state"`
		Pincode        string `json:"pincode"`
		Notes          string `json:"notes"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}
	req.Phone = strings.TrimSpace(req.Phone)
	if !utils.ValidPhone(req.Phone) {
		utils.Error(c, http.StatusBadRequest, "Please enter a valid 10-digit mobile number.", "invalid phone")
		return
	}
	req.AlternatePhone = strings.TrimSpace(req.AlternatePhone)
	if req.AlternatePhone != "" && !utils.ValidPhone(req.AlternatePhone) {
		utils.Error(c, http.StatusBadRequest, "Please enter a valid 10-digit mobile number.", "invalid alternate phone")
		return
	}

	fID := firmID
	portalEmail := normalizeEmail(req.Email)

	clientID := uuid.New().String()
	_, err := config.DB.Exec(`
		INSERT INTO clients (id, firm_id, name, email, phone, alternate_phone,
		address, city, state, pincode, notes, created_by)
		VALUES ($1, $2::uuid, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12::uuid)
	`, clientID, fID, req.Name, portalEmail, req.Phone, req.AlternatePhone,
		req.Address, req.City, req.State, req.Pincode, req.Notes, uID)

	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to create client", err.Error())
		return
	}

	// A client is just a record here — no portal login account is created
	// automatically. Adding a client used to synchronously provision a portal
	// user and send a blocking SMTP email inside this same request; on a slow
	// or misconfigured mail server that held the HTTP response open long
	// enough to look like the app had frozen, even though the client row
	// above was already committed. A firm that wants a client to have portal
	// access can invite them separately.
	//
	// The lawyer↔client chat thread is still opened up front (chat_rooms
	// keys off the clients row directly, not a portal account), so messaging
	// works immediately regardless of whether the client ever logs into a
	// portal.
	ensureChatRoom(fID, clientID, uID, req.Name)

	utils.Success(c, http.StatusCreated, "Client created", gin.H{
		"id": clientID,
	})
}

// provisionPortalUser creates the client's login and emails them a one-time
// password. It returns the new user id and whether an account was made.
func provisionPortalUser(clientID, firmID, name, email, phone string) (string, bool) {
	password, err := generatePassword()
	if err != nil {
		log.Printf("[client] could not generate portal password: %v", err)
		return "", false
	}

	hash, err := utils.HashPassword(password)
	if err != nil {
		log.Printf("[client] could not hash portal password: %v", err)
		return "", false
	}

	var clientRoleID sql.NullString
	config.DB.QueryRow("SELECT id FROM roles WHERE name='client' LIMIT 1").Scan(&clientRoleID)
	if !clientRoleID.Valid {
		log.Println("[client] roles table not seeded; skipping portal account")
		return "", false
	}

	portalUserID := uuid.New().String()
	_, err = config.DB.Exec(`
		INSERT INTO users (id, name, email, phone, password_hash,
		role_id, firm_id, is_active, email_verified, must_change_password)
		VALUES ($1, $2, $3, $4, $5, $6, $7::uuid, true, false, true)
	`, portalUserID, name, email, phone, hash, clientRoleID, firmID)
	if err != nil {
		log.Printf("[client] could not create portal user: %v", err)
		return "", false
	}

	var firmName string
	config.DB.QueryRow(`SELECT name FROM firms WHERE id=$1::uuid`, firmID).Scan(&firmName)
	if firmName == "" {
		firmName = "your legal team"
	}

	body := fmt.Sprintf(
		"Hello %s,\n\n%s has set up a client portal account for you.\n\n"+
			"Email: %s\nTemporary password: %s\n\n"+
			"You will be asked to choose a new password the first time you sign in.\n",
		name, firmName, email, password)

	if err := mailerClient().Send(email, "Your Libra Law client portal access", body); err != nil {
		if errors.Is(err, services.ErrMailNotConfigured) && !utils.IsProduction() {
			log.Printf("[dev] portal password for %s is %s", email, password)
		} else {
			log.Printf("[client] could not email portal credentials to %s: %v", email, err)
		}
	}

	// A pointer to the account, with no credential in it.
	utils.NotifyWithRef(portalUserID, firmID,
		"Welcome to your client portal",
		"Your account is ready. Sign-in details were sent to your email address.",
		"general", clientID, "client")

	return portalUserID, true
}

// ensureChatRoom opens the lawyer↔client thread once, if it does not exist.
func ensureChatRoom(firmID, clientID, lawyerID, clientName string) {
	var existing string
	config.DB.QueryRow(`
		SELECT id FROM chat_rooms
		WHERE lawyer_id=$1::uuid AND client_id=$2::uuid AND is_active=true
		LIMIT 1
	`, lawyerID, clientID).Scan(&existing)
	if existing != "" {
		return
	}

	roomID := uuid.New().String()
	if _, err := config.DB.Exec(`
		INSERT INTO chat_rooms (id, firm_id, client_id, lawyer_id, room_name, is_active)
		VALUES ($1, $2::uuid, $3::uuid, $4::uuid, $5, true)
	`, roomID, firmID, clientID, lawyerID, clientName); err != nil {
		log.Printf("[client] could not open chat room: %v", err)
		return
	}

	var lawyerName string
	config.DB.QueryRow("SELECT name FROM users WHERE id=$1::uuid", lawyerID).Scan(&lawyerName)

	greeting := fmt.Sprintf(
		"Hello %s, welcome to Libra Law Practice. I'm %s — feel free to ask any questions here.",
		clientName, lawyerName)

	config.DB.Exec(`
		INSERT INTO chat_messages (id, room_id, sender_id, sender_name,
		sender_role, message, message_type)
		VALUES ($1, $2::uuid, $3::uuid, $4, 'lawyer', $5, 'text')
	`, uuid.New().String(), roomID, lawyerID, lawyerName, greeting)

	config.DB.Exec(`
		UPDATE chat_rooms SET last_message=$1, last_message_at=NOW() WHERE id=$2::uuid
	`, greeting, roomID)
}

// generatePassword returns a temporary credential.
//
// The old version called the deprecated rand.Seed(time.Now().UnixNano()) on the
// global math/rand source and drew 8 characters from it. Anyone who knew
// roughly when a client was created could reproduce the password; a shared
// global seed also meant two clients created in the same nanosecond window got
// identical passwords.
func generatePassword() (string, error) {
	const chars = "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	const length = 16

	out := make([]byte, length)
	max := big.NewInt(int64(len(chars)))
	for i := range out {
		n, err := rand.Int(rand.Reader, max)
		if err != nil {
			return "", err
		}
		out[i] = chars[n.Int64()]
	}
	return string(out), nil
}

func GetClient(c *gin.Context) {
	id := c.Param("id")
	firmID, ok := requireFirmResource(c, tblClients, id)
	if !ok {
		return
	}

	var cl struct {
		ID        string    `json:"id"`
		Name      string    `json:"name"`
		Email     string    `json:"email"`
		Phone     string    `json:"phone"`
		Address   string    `json:"address"`
		City      string    `json:"city"`
		State     string    `json:"state"`
		Pincode   string    `json:"pincode"`
		Notes     string    `json:"notes"`
		IsActive  bool      `json:"is_active"`
		CreatedAt time.Time `json:"created_at"`
	}
	err := config.DB.QueryRow(`
		SELECT id, name, COALESCE(email,''), COALESCE(phone,''),
		       COALESCE(address,''), COALESCE(city,''), COALESCE(state,''),
		       COALESCE(pincode,''), COALESCE(notes,''), is_active, created_at
		FROM clients WHERE id=$1::uuid AND firm_id=$2::uuid
	`, id, firmID).Scan(&cl.ID, &cl.Name, &cl.Email, &cl.Phone,
		&cl.Address, &cl.City, &cl.State, &cl.Pincode,
		&cl.Notes, &cl.IsActive, &cl.CreatedAt)

	if err == sql.ErrNoRows {
		utils.Error(c, http.StatusNotFound, "Client not found", "")
		return
	}
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Database error", err.Error())
		return
	}
	utils.Success(c, http.StatusOK, "Client fetched", cl)
}

func UpdateClient(c *gin.Context) {
	id := c.Param("id")
	firmID, ok := requireFirmResource(c, tblClients, id)
	if !ok {
		return
	}

	var req struct {
		Name    string `json:"name"`
		Email   string `json:"email" binding:"omitempty,email"`
		Phone   string `json:"phone"`
		Address string `json:"address"`
		City    string `json:"city"`
		State   string `json:"state"`
		Notes   string `json:"notes"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}
	req.Phone = strings.TrimSpace(req.Phone)
	if req.Phone != "" && !utils.ValidPhone(req.Phone) {
		utils.Error(c, http.StatusBadRequest, "Please enter a valid 10-digit mobile number.", "invalid phone")
		return
	}

	// Every field was overwritten unconditionally, so a partial update — the
	// only kind the app sends from its edit form — blanked out whatever it
	// omitted. Keep the stored value when a field is absent.
	// $N::text on every placeholder — see UpdateProfile (auth_controller.go)
	// for why: this same CASE-with-reused-placeholder shape is what broke
	// UpdateCase in production with "inconsistent types deduced".
	_, err := config.DB.Exec(`
		UPDATE clients SET
		  name    = CASE WHEN $1::text != '' THEN $1::text ELSE name END,
		  email   = CASE WHEN $2::text != '' THEN $2::text ELSE email END,
		  phone   = CASE WHEN $3::text != '' THEN $3::text ELSE phone END,
		  address = CASE WHEN $4::text != '' THEN $4::text ELSE address END,
		  city    = CASE WHEN $5::text != '' THEN $5::text ELSE city END,
		  state   = CASE WHEN $6::text != '' THEN $6::text ELSE state END,
		  notes   = CASE WHEN $7::text != '' THEN $7::text ELSE notes END,
		  updated_at = NOW()
		WHERE id=$8::uuid AND firm_id=$9::uuid
	`, req.Name, normalizeEmail(req.Email), req.Phone, req.Address,
		req.City, req.State, req.Notes, id, firmID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to update", err.Error())
		return
	}
	utils.Success(c, http.StatusOK, "Client updated", nil)
}

func DeleteClient(c *gin.Context) {
	id := c.Param("id")
	firmID, ok := requireFirmResource(c, tblClients, id)
	if !ok {
		return
	}
	// The result was previously discarded, so the endpoint reported success
	// even when the statement failed.
	if _, err := config.DB.Exec(
		"UPDATE clients SET is_active=false, updated_at=NOW() WHERE id=$1::uuid AND firm_id=$2::uuid",
		id, firmID,
	); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to delete client", err.Error())
		return
	}
	utils.Success(c, http.StatusOK, "Client deleted", nil)
}

// GetClientBookings returns this client's consultation/booking history with
// the logged-in lawyer. There is no direct foreign key between the firm's
// manually-managed `clients` table and the portal `users` accounts that
// actually create `consultations` rows, so the two are correlated by email
// or phone — the only fields a firm-added client record and a self-registered
// portal account can share.
func GetClientBookings(c *gin.Context) {
	id := c.Param("id")
	firmID, ok := requireFirmResource(c, tblClients, id)
	if !ok {
		return
	}
	lawyerID := utils.UserID(c)

	var email, phone string
	err := config.DB.QueryRow(`
		SELECT COALESCE(email,''), COALESCE(phone,'')
		FROM clients WHERE id=$1::uuid AND firm_id=$2::uuid
	`, id, firmID).Scan(&email, &phone)
	if err == sql.ErrNoRows {
		utils.Error(c, http.StatusNotFound, "Client not found", "")
		return
	}
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Database error", err.Error())
		return
	}

	rows, err := config.DB.Query(`
		SELECT con.id, con.consultation_type,
			con.consultation_date::text, con.consultation_time,
			con.status, con.session_status,
			con.payment_status, COALESCE(con.amount_paise,0),
			COALESCE(con.call_duration_seconds,0),
			con.session_started_at, con.session_ended_at, con.created_at
		FROM consultations con
		JOIN users u ON con.client_id = u.id
		WHERE con.lawyer_id = $1::uuid
		  AND ((($2::text) != '' AND u.email = $2::text)
		       OR (($3::text) != '' AND u.phone = $3::text))
		ORDER BY con.consultation_date DESC, con.consultation_time DESC
	`, lawyerID, email, phone)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch bookings", err.Error())
		return
	}
	defer rows.Close()

	type Booking struct {
		ID                  string     `json:"id"`
		ConsultationType    string     `json:"consultation_type"`
		ConsultationDate    string     `json:"consultation_date"`
		ConsultationTime    string     `json:"consultation_time"`
		Status              string     `json:"status"`
		SessionStatus       string     `json:"session_status"`
		PaymentStatus       string     `json:"payment_status"`
		AmountPaise         int64      `json:"amount_paise"`
		CallDurationSeconds int        `json:"call_duration_seconds"`
		SessionStartedAt    *time.Time `json:"session_started_at"`
		SessionEndedAt      *time.Time `json:"session_ended_at"`
		CreatedAt           time.Time  `json:"created_at"`
	}

	bookings := []Booking{}
	for rows.Next() {
		var b Booking
		var startedAt, endedAt sql.NullTime
		if err := rows.Scan(&b.ID, &b.ConsultationType, &b.ConsultationDate,
			&b.ConsultationTime, &b.Status, &b.SessionStatus,
			&b.PaymentStatus, &b.AmountPaise, &b.CallDurationSeconds,
			&startedAt, &endedAt, &b.CreatedAt); err != nil {
			utils.Error(c, http.StatusInternalServerError, "Failed to read bookings", err.Error())
			return
		}
		if startedAt.Valid {
			b.SessionStartedAt = &startedAt.Time
		}
		if endedAt.Valid {
			b.SessionEndedAt = &endedAt.Time
		}
		bookings = append(bookings, b)
	}
	utils.Success(c, http.StatusOK, "Bookings fetched", bookings)
}
