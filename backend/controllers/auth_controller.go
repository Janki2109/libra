package controllers

import (
	"database/sql"
	"errors"
	"libra/config"
	"libra/models"
	"libra/services"
	"libra/utils"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

// mailer delivers verification codes and notifications.

// normalizeEmail makes lookups case-insensitive. Addresses are case-insensitive
// in practice, so "Foo@x.com" and "foo@x.com" previously produced two accounts
// and a login that worked only with the exact original casing.
func normalizeEmail(e string) string {
	return strings.ToLower(strings.TrimSpace(e))
}

// dummyBcryptHash is a valid bcrypt digest of a value nobody knows. It exists
// only so the unknown-user path costs the same as the wrong-password path.
const dummyBcryptHash = "$2a$14$C6UzMDM.H6dfI/f/IKcEe.7Z7lLu7NfyO5rHLQpVoHBH8oSAhc/3."

// ─── LOGIN ───────────────────────────────────
func Login(c *gin.Context) {
	var req models.LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}

	var user models.User
	var passwordHash string

	query := `
		SELECT u.id, u.name, u.email, COALESCE(u.phone,''), u.password_hash,
		       COALESCE(u.role_id::text, ''), COALESCE(r.name, ''),
		       COALESCE(u.firm_id::text, ''), COALESCE(u.avatar_url, ''),
		       u.is_active
		FROM users u
		LEFT JOIN roles r ON u.role_id = r.id
		WHERE lower(u.email) = $1 AND u.is_active = true
	`

	err := config.DB.QueryRow(query, normalizeEmail(req.Email)).Scan(
		&user.ID, &user.Name, &user.Email, &user.Phone, &passwordHash,
		&user.RoleID, &user.RoleName, &user.FirmID, &user.AvatarURL,
		&user.IsActive,
	)

	if err == sql.ErrNoRows {
		// Run a bcrypt comparison against a dummy hash anyway. Returning
		// immediately made "no such user" measurably faster than "wrong
		// password", which leaks which addresses are registered.
		utils.CheckPassword(req.Password, dummyBcryptHash)
		utils.Error(c, http.StatusUnauthorized, "Invalid email or password", "user not found")
		return
	}
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Database error", err.Error())
		return
	}

	if !utils.CheckPassword(req.Password, passwordHash) {
		utils.Error(c, http.StatusUnauthorized, "Invalid email or password", "wrong password")
		return
	}

	config.DB.Exec("UPDATE users SET last_login_at = $1 WHERE id = $2", time.Now(), user.ID)

	token, err := utils.GenerateToken(user.ID, user.Email, user.RoleName, user.FirmID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Token generation failed", err.Error())
		return
	}

	utils.Success(c, http.StatusOK, "Login successful", models.AuthResponse{
		Token: token,
		User:  user,
	})
}

// ─── LAWYER REGISTER ─────────────────────────
func Register(c *gin.Context) {
	var req struct {
		FirmName         string `json:"firm_name" binding:"required"`
		Name             string `json:"name" binding:"required"`
		Email            string `json:"email" binding:"required,email"`
		Phone            string `json:"phone" binding:"required"`
		Password         string `json:"password" binding:"required,min=6"`
		BarCouncilNumber string `json:"bar_council_number"`
		City             string `json:"city"`
		State            string `json:"state"`
		Designation      string `json:"designation"`
		// Plan is the name of one of the plans row (lawyer/lawyer_pro/
		// lawyer_premium) the signer chose on the "Choose Your Plan" screen.
		// Optional and defaults to the base 'lawyer' plan so existing callers
		// that don't send it keep working exactly as before.
		Plan string `json:"plan"`
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

	email := normalizeEmail(req.Email)

	hash, err := utils.HashPassword(req.Password)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Password hashing failed", err.Error())
		return
	}

	// One transaction for firm + subscription + user. Previously each INSERT
	// stood alone, so a failure partway through left an orphaned firm and a
	// dangling subscription that no one could ever log into or clean up.
	tx, err := config.DB.Begin()
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to start signup", err.Error())
		return
	}
	defer tx.Rollback() // no-op once Commit succeeds

	var exists int
	tx.QueryRow("SELECT COUNT(*) FROM users WHERE lower(email) = $1", email).Scan(&exists)
	if exists > 0 {
		utils.Error(c, http.StatusConflict, "Email already registered", "duplicate email")
		return
	}

	// Only a lawyer-tier plan is valid here — anything else (including a
	// tampered or unrecognised value) falls back to the base plan rather than
	// silently granting a higher tier.
	planName := req.Plan
	switch planName {
	case "lawyer", "lawyer_pro", "lawyer_premium":
	default:
		planName = "lawyer"
	}
	var planID sql.NullString
	tx.QueryRow("SELECT id FROM plans WHERE name = $1 LIMIT 1", planName).Scan(&planID)

	trialEnds := time.Now().Add(trialPeriod)

	firmID := uuid.New().String()
	_, err = tx.Exec(`
		INSERT INTO firms (id, name, email, phone, city, state, plan_id, bar_council_number, trial_ends_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
	`, firmID, req.FirmName, email, req.Phone, req.City, req.State,
		planID, req.BarCouncilNumber, trialEnds)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to create firm", err.Error())
		return
	}

	_, err = tx.Exec(`
		INSERT INTO subscriptions (id, firm_id, plan_id, billing_cycle, amount, status, trial_ends_at)
		VALUES ($1, $2::uuid, $3, 'monthly', 0, 'trial', $4)
	`, uuid.New().String(), firmID, planID, trialEnds)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to start trial", err.Error())
		return
	}

	var roleID sql.NullString
	tx.QueryRow("SELECT id FROM roles WHERE name = 'admin' LIMIT 1").Scan(&roleID)
	if !roleID.Valid {
		utils.Error(c, http.StatusInternalServerError, "Signup unavailable",
			"roles table is not seeded — run database/seeds/seed_roles.sql")
		return
	}

	userID := uuid.New().String()
	_, err = tx.Exec(`
		INSERT INTO users (id, name, email, phone, password_hash, role_id, firm_id, is_active, email_verified, verification_status, bar_council_number, designation)
		VALUES ($1, $2, $3, $4, $5, $6, $7::uuid, true, false, 'pending', $8, $9)
	`, userID, req.Name, email, req.Phone, hash, roleID, firmID, req.BarCouncilNumber, req.Designation)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to create user", err.Error())
		return
	}

	if err := tx.Commit(); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to complete signup", err.Error())
		return
	}

	token, err := utils.GenerateToken(userID, email, "admin", firmID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Token generation failed", err.Error())
		return
	}

	utils.Success(c, http.StatusCreated, "Account created! 5 day free trial started.", gin.H{
		"token":      token,
		"user_id":    userID,
		"firm_id":    firmID,
		"trial_ends": trialEnds,
	})
}

// trialPeriod is the free window a new firm gets.
const trialPeriod = 5 * 24 * time.Hour

// ─── CLIENT REGISTER ─────────────────────────
func ClientRegister(c *gin.Context) {
	var req struct {
		Name     string `json:"name" binding:"required"`
		Email    string `json:"email" binding:"required,email"`
		Phone    string `json:"phone" binding:"required"`
		Password string `json:"password" binding:"required,min=6"`
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

	email := normalizeEmail(req.Email)

	var count int
	config.DB.QueryRow("SELECT COUNT(*) FROM users WHERE lower(email)=$1", email).Scan(&count)
	if count > 0 {
		utils.Error(c, http.StatusConflict, "Email already registered", "duplicate email")
		return
	}

	hash, err := utils.HashPassword(req.Password)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to hash password", err.Error())
		return
	}

	var clientRoleID sql.NullString
	config.DB.QueryRow("SELECT id FROM roles WHERE name='client' LIMIT 1").Scan(&clientRoleID)
	if !clientRoleID.Valid {
		utils.Error(c, http.StatusInternalServerError, "Signup unavailable",
			"roles table is not seeded")
		return
	}

	userID := uuid.New().String()

	// firm_id stays NULL. The old code minted a fresh random UUID here, which
	// pointed at a firm that does not exist: every tenant-scoped query then
	// matched nothing, so clients saw an empty app, and any row written with
	// that id was unreachable forever. A client's firm association comes from
	// the lawyer who adds them, not from signup.
	_, err = config.DB.Exec(`
		INSERT INTO users (id, name, email, phone, password_hash, role_id, firm_id, is_active, email_verified)
		VALUES ($1, $2, $3, $4, $5, $6, NULL, true, false)
	`, userID, req.Name, email, req.Phone, hash, clientRoleID)

	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to create account", err.Error())
		return
	}

	token, err := utils.GenerateToken(userID, email, "client", "")
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Token generation failed", err.Error())
		return
	}

	utils.Success(c, http.StatusCreated, "Client account created!", gin.H{
		"token":   token,
		"user_id": userID,
		"user": gin.H{
			"id":        userID,
			"name":      req.Name,
			"email":     email,
			"phone":     req.Phone,
			"role":      "client",
			"role_name": "client",
			"firm_id":   "",
		},
	})
}

// ─── STUDENT REGISTER ────────────────────────
func StudentRegister(c *gin.Context) {
	var req struct {
		Name        string `json:"name" binding:"required"`
		Email       string `json:"email" binding:"required,email"`
		Phone       string `json:"phone" binding:"required"`
		Password    string `json:"password" binding:"required,min=6"`
		CollegeName string `json:"college_name"`
		Year        string `json:"year"`
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

	email := normalizeEmail(req.Email)

	var count int
	config.DB.QueryRow("SELECT COUNT(*) FROM users WHERE lower(email)=$1", email).Scan(&count)
	if count > 0 {
		utils.Error(c, http.StatusConflict, "Email already registered", "duplicate email")
		return
	}

	hash, err := utils.HashPassword(req.Password)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to hash password", err.Error())
		return
	}

	// The law_student role is created by migration 008; this insert covers a
	// database that predates it. ON CONFLICT must name the conflicting column
	// or the row is silently dropped when the role already exists.
	var studentRoleID string
	err = config.DB.QueryRow(`
		INSERT INTO roles (id, name, description)
		VALUES ($1, 'law_student', 'Law student with learning access')
		ON CONFLICT (name) DO UPDATE SET name = EXCLUDED.name
		RETURNING id
	`, uuid.New().String()).Scan(&studentRoleID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to resolve role", err.Error())
		return
	}

	userID := uuid.New().String()

	designation := req.CollegeName
	if req.Year != "" {
		designation = strings.TrimSpace(req.CollegeName + " - " + req.Year)
	}

	// Students belong to no firm — see the note in ClientRegister.
	_, err = config.DB.Exec(`
		INSERT INTO users (id, name, email, phone, password_hash, role_id, firm_id,
		designation, is_active, email_verified)
		VALUES ($1, $2, $3, $4, $5, $6, NULL, $7, true, false)
	`, userID, req.Name, email, req.Phone, hash, studentRoleID, designation)

	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to create account", err.Error())
		return
	}

	token, err := utils.GenerateToken(userID, email, "law_student", "")
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Token generation failed", err.Error())
		return
	}

	utils.Success(c, http.StatusCreated, "Student account created!", gin.H{
		"token":   token,
		"user_id": userID,
		"user": gin.H{
			"id":          userID,
			"name":        req.Name,
			"email":       email,
			"phone":       req.Phone,
			"role":        "law_student",
			"role_name":   "law_student",
			"firm_id":     "",
			"designation": designation,
		},
	})
}

// otpValidMinutes is how long a freshly issued code stays usable.
const otpValidMinutes = 10

// maxOTPAttempts caps guesses against a single issued code.
const maxOTPAttempts = 5

// ─── SEND OTP ────────────────────────────────
func SendOTP(c *gin.Context) {
	var req struct {
		Email string `json:"email" binding:"required,email"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}

	email := normalizeEmail(req.Email)

	// Always answer identically whether or not the address exists, so this
	// endpoint cannot be used to enumerate registered users.
	const genericMsg = "If an account exists for that address, a code has been sent."

	var userID string
	err := config.DB.QueryRow(
		`SELECT id FROM users WHERE lower(email) = $1 AND is_active = true`, email,
	).Scan(&userID)
	if err != nil {
		if err != sql.ErrNoRows {
			utils.Error(c, http.StatusInternalServerError, "Could not send code", err.Error())
			return
		}
		utils.Success(c, http.StatusOK, genericMsg, nil)
		return
	}

	otp, err := utils.GenerateOTP()
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Could not generate code", err.Error())
		return
	}

	// Retire any codes still outstanding for this address so an attacker
	// cannot keep several valid codes in flight at once.
	config.DB.Exec(`UPDATE otps SET is_used = true WHERE email = $1 AND is_used = false`, email)

	_, err = config.DB.Exec(`
		INSERT INTO otps (id, email, otp_hash, purpose, attempts, expires_at)
		VALUES ($1, $2, $3, 'login', 0, NOW() + ($4 || ' minutes')::interval)
	`, uuid.New().String(), email, utils.HashOTP(email, otp), otpValidMinutes)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Could not send code", err.Error())
		return
	}

	// The code goes to the user's inbox — never back in this response body.
	// Returning it here previously meant anyone who could call the endpoint
	// could log in as any user.
	if err := mailerClient().SendOTP(email, otp, otpValidMinutes); err != nil {
		if errors.Is(err, services.ErrMailNotConfigured) && !utils.IsProduction() {
			// Local development without SMTP: print to the server log, which
			// the developer can already read, rather than to the HTTP client.
			log.Printf("[dev] OTP for %s is %s", email, otp)
			utils.Success(c, http.StatusOK, genericMsg, nil)
			return
		}
		utils.Error(c, http.StatusInternalServerError, "Could not send code", err.Error())
		return
	}

	utils.Success(c, http.StatusOK, genericMsg, nil)
}

// ─── VERIFY OTP ──────────────────────────────
func VerifyOTP(c *gin.Context) {
	var req struct {
		Email string `json:"email" binding:"required,email"`
		OTP   string `json:"otp" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}

	email := normalizeEmail(req.Email)

	var otpID, storedHash string
	var attempts int
	err := config.DB.QueryRow(`
		SELECT id, otp_hash, attempts FROM otps
		WHERE email = $1 AND is_used = false AND expires_at > NOW()
		ORDER BY created_at DESC LIMIT 1
	`, email).Scan(&otpID, &storedHash, &attempts)

	if err == sql.ErrNoRows {
		utils.Error(c, http.StatusBadRequest, "Invalid or expired code", "no live otp")
		return
	}
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Could not verify code", err.Error())
		return
	}

	if attempts >= maxOTPAttempts {
		config.DB.Exec(`UPDATE otps SET is_used = true WHERE id = $1`, otpID)
		utils.Error(c, http.StatusTooManyRequests,
			"Too many incorrect attempts. Request a new code.", "otp attempts exhausted")
		return
	}

	if !utils.CompareOTPHash(storedHash, utils.HashOTP(email, req.OTP)) {
		config.DB.Exec(`UPDATE otps SET attempts = attempts + 1 WHERE id = $1`, otpID)
		utils.Error(c, http.StatusBadRequest, "Invalid or expired code", "otp mismatch")
		return
	}

	// Single-use: burn the code before issuing anything.
	res, err := config.DB.Exec(
		`UPDATE otps SET is_used = true WHERE id = $1 AND is_used = false`, otpID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Could not verify code", err.Error())
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		// Another concurrent request already consumed it.
		utils.Error(c, http.StatusBadRequest, "Invalid or expired code", "otp already used")
		return
	}

	var user models.User
	err = config.DB.QueryRow(`
		SELECT u.id, u.name, u.email, COALESCE(u.phone,''),
		       COALESCE(u.role_id::text,''), COALESCE(r.name,''),
		       COALESCE(u.firm_id::text,''), u.is_active
		FROM users u
		LEFT JOIN roles r ON u.role_id = r.id
		WHERE lower(u.email) = $1 AND u.is_active = true
	`, email).Scan(
		&user.ID, &user.Name, &user.Email, &user.Phone,
		&user.RoleID, &user.RoleName, &user.FirmID, &user.IsActive,
	)
	// The old code ignored this error and minted a token for the zero-value
	// user, i.e. a valid session with an empty user id.
	if err != nil {
		utils.Error(c, http.StatusUnauthorized, "Account not available", "user lookup failed")
		return
	}

	token, err := utils.GenerateToken(user.ID, user.Email, user.RoleName, user.FirmID)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Token generation failed", err.Error())
		return
	}

	config.DB.Exec("UPDATE users SET last_login_at = NOW() WHERE id = $1::uuid", user.ID)

	utils.Success(c, http.StatusOK, "Code verified", models.AuthResponse{
		Token: token,
		User:  user,
	})
}

// ─── FORGOT PASSWORD ─────────────────────────
// Same OTP mechanism SendOTP/VerifyOTP already use (otps table, bcrypt-style
// hash comparison, SMTP delivery via mailerClient) with its own 'purpose' so
// a code issued here can never be replayed against the passwordless-login
// flow or vice versa. Works identically for lawyer, client and student
// accounts — the otps/users tables aren't role-specific.
func ForgotPassword(c *gin.Context) {
	var req struct {
		Email string `json:"email" binding:"required,email"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}

	email := normalizeEmail(req.Email)

	// Identical response whether or not the address is registered — this
	// endpoint must never let a caller enumerate accounts.
	const genericMsg = "If an account exists for that address, a reset code has been sent."

	var userID string
	err := config.DB.QueryRow(
		`SELECT id FROM users WHERE lower(email) = $1 AND is_active = true`, email,
	).Scan(&userID)
	if err != nil {
		if err != sql.ErrNoRows {
			utils.Error(c, http.StatusInternalServerError, "Could not send code", err.Error())
			return
		}
		utils.Success(c, http.StatusOK, genericMsg, nil)
		return
	}

	otp, err := utils.GenerateOTP()
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Could not generate code", err.Error())
		return
	}

	// Retire any still-outstanding reset codes for this address first, same
	// as the login-OTP flow — only one live code at a time per purpose.
	config.DB.Exec(`UPDATE otps SET is_used = true WHERE email = $1 AND purpose = 'password_reset' AND is_used = false`, email)

	_, err = config.DB.Exec(`
		INSERT INTO otps (id, email, otp_hash, purpose, attempts, expires_at)
		VALUES ($1, $2, $3, 'password_reset', 0, NOW() + ($4 || ' minutes')::interval)
	`, uuid.New().String(), email, utils.HashOTP(email, otp), otpValidMinutes)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Could not send code", err.Error())
		return
	}

	// Never returned in the response, and never logged in production — only
	// the user's own inbox ever sees the actual code.
	if err := mailerClient().SendOTP(email, otp, otpValidMinutes); err != nil {
		if errors.Is(err, services.ErrMailNotConfigured) && !utils.IsProduction() {
			log.Printf("[dev] password reset code for %s is %s", email, otp)
			utils.Success(c, http.StatusOK, genericMsg, nil)
			return
		}
		utils.Error(c, http.StatusInternalServerError, "Could not send code", err.Error())
		return
	}

	utils.Success(c, http.StatusOK, genericMsg, nil)
}

// verifyPasswordResetOTP is shared by VerifyPasswordResetOTP (checks only,
// lets the UI advance to the new-password screen) and ResetPassword (checks
// again immediately before actually burning the code and changing the
// password). consume=false never marks the code used, so failing to submit
// a new password afterward doesn't strand the user's one live code.
func verifyPasswordResetOTP(email, otp string, consume bool) (otpID string, code int, msg string) {
	var storedHash string
	var attempts int
	err := config.DB.QueryRow(`
		SELECT id, otp_hash, attempts FROM otps
		WHERE email = $1 AND purpose = 'password_reset' AND is_used = false AND expires_at > NOW()
		ORDER BY created_at DESC LIMIT 1
	`, email).Scan(&otpID, &storedHash, &attempts)
	if err == sql.ErrNoRows {
		return "", http.StatusBadRequest, "Invalid or expired code"
	}
	if err != nil {
		return "", http.StatusInternalServerError, "Could not verify code"
	}
	if attempts >= maxOTPAttempts {
		config.DB.Exec(`UPDATE otps SET is_used = true WHERE id = $1`, otpID)
		return "", http.StatusTooManyRequests, "Too many incorrect attempts. Request a new code."
	}
	if !utils.CompareOTPHash(storedHash, utils.HashOTP(email, otp)) {
		config.DB.Exec(`UPDATE otps SET attempts = attempts + 1 WHERE id = $1`, otpID)
		return "", http.StatusBadRequest, "Invalid or expired code"
	}
	if consume {
		res, err := config.DB.Exec(
			`UPDATE otps SET is_used = true WHERE id = $1 AND is_used = false`, otpID)
		if err != nil {
			return "", http.StatusInternalServerError, "Could not verify code"
		}
		if n, _ := res.RowsAffected(); n == 0 {
			return "", http.StatusBadRequest, "Invalid or expired code"
		}
	}
	return otpID, 0, ""
}

// VerifyPasswordResetOTP - Step 5: lets the app confirm the code before
// showing the New Password screen, without spending the code yet.
func VerifyPasswordResetOTP(c *gin.Context) {
	var req struct {
		Email string `json:"email" binding:"required,email"`
		OTP   string `json:"otp" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}
	_, code, msg := verifyPasswordResetOTP(normalizeEmail(req.Email), req.OTP, false)
	if code != 0 {
		utils.Error(c, code, msg, "")
		return
	}
	utils.Success(c, http.StatusOK, "Code verified", nil)
}

// ResetPassword - Steps 6-7: re-verifies the same code (never trusts the
// earlier "verified" response alone) and, only if it still checks out,
// burns it and writes the new password hash in the same request.
func ResetPassword(c *gin.Context) {
	var req struct {
		Email       string `json:"email" binding:"required,email"`
		OTP         string `json:"otp" binding:"required"`
		NewPassword string `json:"new_password" binding:"required,min=6"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}

	email := normalizeEmail(req.Email)
	_, code, msg := verifyPasswordResetOTP(email, req.OTP, true)
	if code != 0 {
		utils.Error(c, code, msg, "")
		return
	}

	hash, err := utils.HashPassword(req.NewPassword)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Could not reset password", err.Error())
		return
	}

	res, err := config.DB.Exec(
		`UPDATE users SET password_hash = $1, updated_at = NOW() WHERE lower(email) = $2 AND is_active = true`,
		hash, email)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Could not reset password", err.Error())
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		// The OTP matched an account that's since been deactivated between
		// send and reset — same generic shape as everywhere else here.
		utils.Error(c, http.StatusBadRequest, "Could not reset password", "account not available")
		return
	}

	utils.Success(c, http.StatusOK, "Password reset successfully", nil)
}

// ─── GET ME ──────────────────────────────────
func GetMe(c *gin.Context) {
	userID, _ := c.Get("user_id")

	var user models.User
	query := `
		SELECT u.id, u.name, u.email, COALESCE(u.phone,''),
		       COALESCE(u.role_id::text,''), COALESCE(r.name,''),
		       COALESCE(u.firm_id::text,''), COALESCE(u.avatar_url,''),
		       COALESCE(u.designation,''), u.is_active, u.created_at
		FROM users u
		LEFT JOIN roles r ON u.role_id = r.id
		WHERE u.id = $1
	`
	err := config.DB.QueryRow(query, userID).Scan(
		&user.ID, &user.Name, &user.Email, &user.Phone,
		&user.RoleID, &user.RoleName, &user.FirmID, &user.AvatarURL,
		&user.Designation, &user.IsActive, &user.CreatedAt,
	)
	if err != nil {
		utils.Error(c, http.StatusNotFound, "User not found", err.Error())
		return
	}

	utils.Success(c, http.StatusOK, "User fetched", user)
}

// UpdateAvatar persists the caller's profile photo server-side. It used to
// only be kept in the app's local SharedPreferences cache, so nobody else —
// a client viewing a lawyer's profile, a lawyer viewing a client's — ever
// saw it, and it vanished on reinstall.
//
// Stored as a data URI directly in the users row, matching how documents are
// already stored inline as base64 elsewhere in this app. Capped well below
// that 8MB document limit since this is a small, client-resized photo.
const maxAvatarDataURILen = 2 * 1024 * 1024 // ~2MB of base64

func UpdateAvatar(c *gin.Context) {
	userID, _ := c.Get("user_id")

	var req struct {
		// No `required` — an empty string is a valid request here, used to
		// remove the current photo (falling back to the initials
		// placeholder), not just to set a new one.
		AvatarURL string `json:"avatar_url"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}
	if len(req.AvatarURL) > maxAvatarDataURILen {
		utils.Error(c, http.StatusRequestEntityTooLarge,
			"Photo is too large", "resize before uploading")
		return
	}

	if _, err := config.DB.Exec(
		`UPDATE users SET avatar_url=$1, updated_at=NOW() WHERE id=$2::uuid`,
		req.AvatarURL, userID,
	); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to update photo", err.Error())
		return
	}

	utils.Success(c, http.StatusOK, "Photo updated", gin.H{"avatar_url": req.AvatarURL})
}

// UpdateProfile lets a signed-in user edit their own name/phone/designation.
// There was previously no self-service way to do this at all — an admin
// could rename a staff member (UpdateStaff), but a lawyer had no path to set
// their own designation, which is why it always showed "Not set".
func UpdateProfile(c *gin.Context) {
	userID, _ := c.Get("user_id")

	var req struct {
		Name        string `json:"name"`
		Phone       string `json:"phone"`
		Designation string `json:"designation"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}
	if req.Name != "" && len(strings.Fields(req.Name)) < 2 {
		utils.Error(c, http.StatusBadRequest,
			"Enter your full name (first and last name)", "")
		return
	}
	req.Phone = strings.TrimSpace(req.Phone)
	if req.Phone != "" && !utils.ValidPhone(req.Phone) {
		utils.Error(c, http.StatusBadRequest, "Please enter a valid 10-digit mobile number.", "invalid phone")
		return
	}

	// $N::text on every placeholder: Postgres deduces each parameter's type
	// before it sees an argument, and a bare $N reused as both the CASE WHEN
	// test and its THEN result can end up with two different inferred
	// types — reproduced in UpdateCase (case_controller.go) as "inconsistent
	// types deduced for parameter" (42P08), which failed the update outright.
	if _, err := config.DB.Exec(`
		UPDATE users SET
		  name        = CASE WHEN $1::text != '' THEN $1::text ELSE name END,
		  phone       = CASE WHEN $2::text != '' THEN $2::text ELSE phone END,
		  designation = CASE WHEN $3::text != '' THEN $3::text ELSE designation END,
		  updated_at  = NOW()
		WHERE id=$4::uuid
	`, req.Name, req.Phone, req.Designation, userID); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to update profile", err.Error())
		return
	}

	utils.Success(c, http.StatusOK, "Profile updated", nil)
}

// ─── LOGOUT ──────────────────────────────────
func Logout(c *gin.Context) {
	utils.Success(c, http.StatusOK, "Logged out successfully", nil)
}

// ─── GET PLANS ───────────────────────────────
func GetPlans(c *gin.Context) {
	rows, err := config.DB.Query(`
		SELECT id, name, display_name, price_monthly, price_yearly,
		       max_cases, max_staff, max_clients, features
		FROM plans WHERE is_active = true ORDER BY price_monthly ASC
	`)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to fetch plans", err.Error())
		return
	}
	defer rows.Close()

	type Plan struct {
		ID           string  `json:"id"`
		Name         string  `json:"name"`
		DisplayName  string  `json:"display_name"`
		PriceMonthly float64 `json:"price_monthly"`
		PriceYearly  float64 `json:"price_yearly"`
		MaxCases     int     `json:"max_cases"`
		MaxStaff     int     `json:"max_staff"`
		MaxClients   int     `json:"max_clients"`
		Features     string  `json:"features"`
	}

	plans := []Plan{}
	for rows.Next() {
		var p Plan
		rows.Scan(&p.ID, &p.Name, &p.DisplayName, &p.PriceMonthly,
			&p.PriceYearly, &p.MaxCases, &p.MaxStaff, &p.MaxClients, &p.Features)
		plans = append(plans, p)
	}
	utils.Success(c, http.StatusOK, "Plans fetched", plans)
}
