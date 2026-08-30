package middleware

import (
	"libra/config"
	"libra/utils"
	"net/http"

	"github.com/gin-gonic/gin"
)

// RequirePlanTier blocks a route unless the caller's firm is subscribed to
// one of the given plan names. Used for features that only some paid tiers
// include (e.g. e-Court access is Lawyer Pro / Lawyer Premium only, not the
// base Lawyer plan) — separate from RequireActiveSubscription, which only
// checks subscription *status*, never which plan.
//
// Reads are gated here too, unlike RequireActiveSubscription: an unpaid tier
// simply does not have this feature, the same way a route that doesn't exist
// for that role would not have it.
func RequirePlanTier(allowedPlans ...string) gin.HandlerFunc {
	allowed := map[string]bool{}
	for _, p := range allowedPlans {
		allowed[p] = true
	}
	return func(c *gin.Context) {
		firmID := utils.FirmID(c)
		if firmID == "" {
			// No firm (client/student/platform-admin) — nothing to gate by plan.
			c.Next()
			return
		}
		if utils.IsPlatformAdmin(c) {
			c.Next()
			return
		}

		var planName string
		err := config.DB.QueryRow(`
			SELECT p.name FROM subscriptions s
			JOIN plans p ON s.plan_id = p.id
			WHERE s.firm_id = $1::uuid
		`, firmID).Scan(&planName)
		if err != nil || !allowed[planName] {
			utils.Error(c, http.StatusForbidden,
				"This feature requires a Lawyer Pro or Lawyer Premium plan",
				"plan does not include this feature")
			c.Abort()
			return
		}
		c.Next()
	}
}
