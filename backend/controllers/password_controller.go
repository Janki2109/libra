package controllers

import (
	"database/sql"
	"libra/config"
	"libra/utils"
	"net/http"

	"github.com/gin-gonic/gin"
)

// ChangePassword lets a signed-in user replace their own password.
//
// The app has shipped a change-password screen and a settings entry that link
// to it since the beginning, but no route ever served
// POST /users/change-password — every submission 404'd. Users provisioned with
// a generated temporary password (clients and staff) therefore had no way to
// replace it.
//
// POST /api/v1/users/change-password
func ChangePassword(c *gin.Context) {
	userID := utils.UserID(c)
	if !isUUID(userID) {
		utils.Error(c, http.StatusUnauthorized, "Not authenticated", "")
		return
	}

	var req struct {
		CurrentPassword string `json:"current_password" binding:"required"`
		NewPassword     string `json:"new_password" binding:"required,min=8"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest,
			"New password must be at least 8 characters", err.Error())
		return
	}

	if req.NewPassword == req.CurrentPassword {
		utils.Error(c, http.StatusBadRequest,
			"The new password must be different from the current one", "")
		return
	}

	var storedHash string
	err := config.DB.QueryRow(
		`SELECT password_hash FROM users WHERE id=$1::uuid AND is_active=true`,
		userID,
	).Scan(&storedHash)
	if err == sql.ErrNoRows {
		utils.Error(c, http.StatusUnauthorized, "Account not available", "")
		return
	}
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to change password", err.Error())
		return
	}

	// Requiring the current password is what stops a stolen or borrowed
	// session from locking the real owner out of their account.
	if !utils.CheckPassword(req.CurrentPassword, storedHash) {
		utils.Error(c, http.StatusUnauthorized, "Current password is incorrect", "")
		return
	}

	newHash, err := utils.HashPassword(req.NewPassword)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to change password", err.Error())
		return
	}

	// Clearing must_change_password releases accounts created with a generated
	// temporary credential.
	if _, err := config.DB.Exec(`
		UPDATE users SET password_hash=$1, must_change_password=false, updated_at=NOW()
		WHERE id=$2::uuid
	`, newHash, userID); err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to change password", err.Error())
		return
	}

	config.DB.Exec(`
		INSERT INTO audit_logs (id, firm_id, user_id, action, module, ip_address)
		VALUES (gen_random_uuid(), NULLIF($1,'')::uuid, $2::uuid, 'password_changed', 'auth', $3)
	`, utils.FirmID(c), userID, c.ClientIP())

	// Existing tokens stay valid until they expire — there is no revocation
	// list yet, so a changed password does not end other sessions. Say so
	// rather than implying otherwise.
	utils.Success(c, http.StatusOK, "Password changed", gin.H{
		"note": "Other signed-in devices stay signed in until their session expires.",
	})
}
