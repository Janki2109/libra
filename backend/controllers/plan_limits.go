package controllers

import (
	"database/sql"
	"fmt"
	"libra/config"
	"libra/utils"
	"net/http"

	"github.com/gin-gonic/gin"
)

// Resources whose count a plan caps.
const (
	limitCases   = "cases"
	limitClients = "clients"
	limitStaff   = "staff"
)

// enforcePlanLimit refuses to create a record once the firm's plan is full.
//
// max_cases, max_staff and max_clients were stored on every plan, displayed on
// the paywall, and checked by nothing — a firm on the cheapest tier could
// create unlimited cases, which made the pricing ladder decorative. A limit
// nobody enforces is a discount nobody asked for.
//
// Returns true when the caller may proceed; writes the response and aborts
// otherwise.
func enforcePlanLimit(c *gin.Context, firmID, resource string) bool {
	limit, ok := planLimitFor(firmID, resource)
	if !ok {
		// No plan row, or the plan does not cap this resource. Never block a
		// firm because of a lookup problem on our side.
		return true
	}
	if limit <= 0 {
		// 0 means unlimited in the plans table.
		return true
	}

	used, err := countFirmResource(firmID, resource)
	if err != nil {
		// Same reasoning: a database hiccup must not stop a lawyer filing a
		// case.
		return true
	}

	if used < limit {
		return true
	}

	utils.Error(c, http.StatusPaymentRequired,
		fmt.Sprintf("Your plan allows %d %s. Upgrade to add more.", limit, resource),
		"plan limit reached")
	c.Abort()
	return false
}

// planLimitFor reads the cap for one resource from the firm's current plan.
func planLimitFor(firmID, resource string) (int, bool) {
	var column string
	switch resource {
	case limitCases:
		column = "p.max_cases"
	case limitClients:
		column = "p.max_clients"
	case limitStaff:
		column = "p.max_staff"
	default:
		return 0, false
	}

	// The column name comes from the switch above, never from user input.
	query := fmt.Sprintf(`
		SELECT COALESCE(%s, 0)
		FROM subscriptions s
		JOIN plans p ON s.plan_id = p.id
		WHERE s.firm_id = $1::uuid
	`, column)

	var limit int
	if err := config.DB.QueryRow(query, firmID).Scan(&limit); err != nil {
		return 0, false
	}
	return limit, true
}

// countFirmResource counts what the firm already has, ignoring soft-deleted
// rows — a firm that archived a client should get that slot back.
func countFirmResource(firmID, resource string) (int, error) {
	var query string
	switch resource {
	case limitCases:
		// Closed matters still occupy a slot; they remain in the workspace.
		query = `SELECT COUNT(*) FROM cases WHERE firm_id = $1::uuid`
	case limitClients:
		query = `SELECT COUNT(*) FROM clients WHERE firm_id = $1::uuid AND is_active = true`
	case limitStaff:
		query = `SELECT COUNT(*) FROM users WHERE firm_id = $1::uuid AND is_active = true`
	default:
		return 0, sql.ErrNoRows
	}

	var n int
	err := config.DB.QueryRow(query, firmID).Scan(&n)
	return n, err
}

// PlanUsage reports how much of the plan the firm has consumed, so the app can
// warn before a limit is hit rather than only at the moment of refusal.
//
// GET /subscription/usage
func GetPlanUsage(c *gin.Context) {
	firmID, ok := utils.RequireFirm(c)
	if !ok {
		return
	}

	type usage struct {
		Used      int  `json:"used"`
		Limit     int  `json:"limit"` // 0 = unlimited
		Unlimited bool `json:"unlimited"`
	}

	out := gin.H{}
	for _, resource := range []string{limitCases, limitClients, limitStaff} {
		limit, _ := planLimitFor(firmID, resource)
		used, _ := countFirmResource(firmID, resource)
		out[resource] = usage{
			Used:      used,
			Limit:     limit,
			Unlimited: limit <= 0,
		}
	}

	utils.Success(c, http.StatusOK, "Plan usage fetched", out)
}
