package controllers

import (
	"net/http"

	"libra/config"
	"libra/utils"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

// RegisterDeviceToken associates an FCM token with the logged-in user,
// regardless of role — lawyer, client, student and admin all call this the
// same way after Firebase hands the app a token. A token can only belong to
// one user at a time (it identifies one app install), so re-registering it
// under a different account (e.g. after logout/login as someone else on the
// same device) reassigns it rather than erroring.
func RegisterDeviceToken(c *gin.Context) {
	userID := utils.UserID(c)

	var req struct {
		Token    string `json:"token" binding:"required"`
		Platform string `json:"platform"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}

	_, err := config.DB.Exec(`
		INSERT INTO device_tokens (id, user_id, token, platform, updated_at)
		VALUES ($1, $2::uuid, $3, $4, NOW())
		ON CONFLICT (token) DO UPDATE
		SET user_id = EXCLUDED.user_id, platform = EXCLUDED.platform, updated_at = NOW()
	`, uuid.New().String(), userID, req.Token, req.Platform)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to register device", err.Error())
		return
	}
	utils.Success(c, http.StatusOK, "Device registered", nil)
}

// UnregisterDeviceToken removes a token, called on logout so a signed-out
// device stops receiving that user's pushes.
func UnregisterDeviceToken(c *gin.Context) {
	var req struct {
		Token string `json:"token" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}
	config.DB.Exec(`DELETE FROM device_tokens WHERE token = $1 AND user_id = $2::uuid`,
		req.Token, utils.UserID(c))
	utils.Success(c, http.StatusOK, "Device unregistered", nil)
}
