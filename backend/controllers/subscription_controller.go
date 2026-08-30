package controllers

import (
	"database/sql"
	"libra/config"
	"libra/utils"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

// GetMySubscription reports the caller's entitlement.
//
// The Flutter app decided this locally: TrialService wrote a first-launch
// timestamp and an `is_subscribed` boolean into SharedPreferences, and the
// paywall read them back. Clearing app data — or reinstalling, or flipping the
// value in the plaintext prefs file — restored a full trial, so the product
// could not actually charge anyone. Entitlement has to be decided by the
// server against the subscriptions table.
//
// GET /api/v1/subscription
func GetMySubscription(c *gin.Context) {
	firmID := utils.FirmID(c)

	// Clients and law students carry no firm and are not billed.
	if firmID == "" {
		utils.Success(c, http.StatusOK, "Subscription fetched", gin.H{
			"status":         "not_applicable",
			"is_active":      true,
			"requires_plan":  false,
			"days_remaining": 0,
		})
		return
	}

	var (
		status       string
		planName     sql.NullString
		planDisplay  sql.NullString
		trialEndsAt  sql.NullTime
		periodEndsAt sql.NullTime
	)

	err := config.DB.QueryRow(`
		SELECT s.status,
		       p.name, p.display_name,
		       s.trial_ends_at, s.current_period_end
		FROM subscriptions s
		LEFT JOIN plans p ON s.plan_id = p.id
		WHERE s.firm_id = $1::uuid
		ORDER BY s.created_at DESC
		LIMIT 1
	`, firmID).Scan(&status, &planName, &planDisplay, &trialEndsAt, &periodEndsAt)

	if err == sql.ErrNoRows {
		utils.Success(c, http.StatusOK, "Subscription fetched", gin.H{
			"status":         "none",
			"is_active":      false,
			"requires_plan":  true,
			"days_remaining": 0,
		})
		return
	}
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to read subscription", err.Error())
		return
	}

	now := time.Now()
	daysRemaining := 0
	isActive := false

	switch status {
	case "active":
		isActive = periodEndsAt.Valid && periodEndsAt.Time.After(now)
		if !isActive {
			// The period lapsed and nothing has renewed it.
			status = "expired"
		} else {
			daysRemaining = int(time.Until(periodEndsAt.Time).Hours() / 24)
		}
	case "trial":
		isActive = trialEndsAt.Valid && trialEndsAt.Time.After(now)
		if isActive {
			daysRemaining = int(time.Until(trialEndsAt.Time).Hours() / 24)
		} else {
			status = "trial_expired"
		}
	case "cancelled":
		// A cancelled subscription still runs to the end of the paid period.
		isActive = periodEndsAt.Valid && periodEndsAt.Time.After(now)
		if isActive {
			daysRemaining = int(time.Until(periodEndsAt.Time).Hours() / 24)
		}
	}

	resp := gin.H{
		"status":         status,
		"is_active":      isActive,
		"requires_plan":  !isActive,
		"days_remaining": daysRemaining,
		"plan":           planName.String,
		"plan_name":      planDisplay.String,
	}
	if trialEndsAt.Valid {
		resp["trial_ends_at"] = trialEndsAt.Time
	}
	if periodEndsAt.Valid {
		resp["current_period_end"] = periodEndsAt.Time
	}

	utils.Success(c, http.StatusOK, "Subscription fetched", resp)
}
