package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

// A client portal account carries its lawyer's firm id — that is how the portal
// finds the client's own matters. Gating the workspace on "has a firm id" alone
// therefore let a signed-in client read the firm's entire client list, staff
// directory, cases and invoices. One client learning who else a firm acts for
// is a privilege breach, so this stays pinned by a test.
func TestRequireFirmStaff(t *testing.T) {
	cases := map[string]int{
		"admin":       http.StatusOK,
		"lawyer":      http.StatusOK,
		"staff":       http.StatusOK,
		"clerk":       http.StatusOK,
		"super_admin": http.StatusOK,

		"client":      http.StatusForbidden,
		"law_student": http.StatusForbidden,
		"":            http.StatusForbidden,
		"unknown":     http.StatusForbidden,
	}

	for role, want := range cases {
		t.Run("role="+role, func(t *testing.T) {
			gin.SetMode(gin.TestMode)
			r := gin.New()
			r.Use(func(c *gin.Context) {
				// Every one of these has a firm id — that is the point.
				c.Set("firm_id", "11111111-1111-1111-1111-111111111111")
				c.Set("role", role)
				c.Next()
			})
			r.Use(RequireFirmStaff())
			r.GET("/clients", func(c *gin.Context) { c.Status(http.StatusOK) })

			w := httptest.NewRecorder()
			r.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/clients", nil))

			if w.Code != want {
				t.Errorf("role %q got %d, want %d", role, w.Code, want)
			}
		})
	}
}
