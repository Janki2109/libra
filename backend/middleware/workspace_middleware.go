package middleware

import (
	"libra/utils"
	"net/http"

	"github.com/gin-gonic/gin"
)

// firmStaffRoles are the roles that work inside a firm's case management
// workspace. Clients and law students are deliberately absent.
var firmStaffRoles = map[string]bool{
	"super_admin": true,
	"admin":       true,
	"lawyer":      true,
	"staff":       true,
	"clerk":       true,
}

// RequireFirmStaff restricts the firm workspace to people who work at the firm.
//
// The workspace routes previously gated on "does this token carry a firm id",
// which every client portal account also satisfies: when a lawyer adds a
// client, provisionPortalUser attaches that client's login to the lawyer's
// firm so the portal can find their matters. The side effect was that a signed-
// in client passed the firm check and could call GET /clients, /staff, /cases
// and /invoices — reading the names, email addresses and phone numbers of every
// other client of that firm, its full staff directory, and its whole case and
// billing list.
//
// For a legal practice that is a privilege breach: one client must never learn
// who else the firm acts for. Clients reach their own records through
// /portal/*, which scopes on their verified email address instead.
func RequireFirmStaff() gin.HandlerFunc {
	return func(c *gin.Context) {
		if firmStaffRoles[utils.Role(c)] {
			c.Next()
			return
		}

		c.JSON(http.StatusForbidden, gin.H{
			"success": false,
			"message": "This area is for firm staff. Use the client portal for your own records.",
			"code":    "firm_staff_only",
		})
		c.Abort()
	}
}
