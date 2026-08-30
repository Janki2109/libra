package middleware

import (
	"database/sql"
	"libra/config"
	"libra/utils"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

// RequireActiveSubscription blocks write operations for firms whose trial or
// subscription has lapsed.
//
// Entitlement was previously enforced only in the Flutter app, which decided it
// from local storage. Even after moving the decision to the server, a client
// that simply does not call GET /subscription — or an HTTP client that never
// runs the app's code at all — kept full access to every write endpoint. A
// paywall the server does not enforce is not a paywall.
//
// Reads stay open deliberately: a firm whose card expired must still be able to
// open its own case files and export its data. Only creating new work is gated.
func RequireActiveSubscription() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Reads are never gated.
		switch c.Request.Method {
		case http.MethodGet, http.MethodHead, http.MethodOptions:
			c.Next()
			return
		}

		firmID := utils.FirmID(c)
		if firmID == "" {
			// Clients and law students are not billed; their own handlers
			// enforce what they may reach.
			c.Next()
			return
		}

		// The platform owner is never billed.
		if utils.IsPlatformAdmin(c) {
			c.Next()
			return
		}

		var status string
		var trialEnds, periodEnd, graceUntil sql.NullTime
		err := config.DB.QueryRow(`
			SELECT status, trial_ends_at, current_period_end, grace_until
			FROM subscriptions WHERE firm_id = $1::uuid
		`, firmID).Scan(&status, &trialEnds, &periodEnd, &graceUntil)

		if err == sql.ErrNoRows {
			// No subscription row at all. Migration 010 backfills one for
			// every existing firm, so this means something is wrong with the
			// firm's setup rather than that they have not paid — let them
			// work and surface it in the logs rather than blocking a lawyer
			// mid-hearing.
			c.Next()
			return
		}
		if err != nil {
			// Never let a database hiccup lock a paying firm out of its files.
			c.Next()
			return
		}

		if subscriptionAllowsWrites(status, trialEnds, periodEnd, graceUntil, time.Now()) {
			c.Next()
			return
		}

		c.JSON(http.StatusPaymentRequired, gin.H{
			"success":       false,
			"message":       "Your plan has expired. Renew to continue adding new records.",
			"code":          "subscription_required",
			"read_only":     true,
			"requires_plan": true,
		})
		c.Abort()
	}
}

// subscriptionAllowsWrites is the entitlement rule, kept as a pure function so
// it is testable without a database.
func subscriptionAllowsWrites(
	status string,
	trialEnds, periodEnd, graceUntil sql.NullTime,
	now time.Time,
) bool {
	switch status {
	case "trial":
		return trialEnds.Valid && trialEnds.Time.After(now)

	case "active":
		if periodEnd.Valid && periodEnd.Time.After(now) {
			return true
		}
		// The period lapsed but the renewal webhook may still be in flight.
		return graceUntil.Valid && graceUntil.Time.After(now)

	case "past_due":
		// A failed renewal buys a grace window rather than an instant cutoff —
		// a firm may be in court the morning their card expires.
		return graceUntil.Valid && graceUntil.Time.After(now)

	case "cancelled":
		// Cancelled but paid through the end of the period.
		return periodEnd.Valid && periodEnd.Time.After(now)

	default: // "expired" or anything unrecognised
		return false
	}
}
