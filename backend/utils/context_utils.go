package utils

import (
	"errors"

	"github.com/gin-gonic/gin"
)

// ErrNoTenant is returned when the request context carries no usable firm id.
var ErrNoTenant = errors.New("no firm context on request")

// CtxString pulls a string value out of the gin context without panicking on a
// missing key or a non-string value. Every caller used to do
// `c.Get("firm_id")` followed by an unchecked `.(string)` assertion, which
// panics and 500s the whole request whenever the claim is absent.
func CtxString(c *gin.Context, key string) string {
	v, ok := c.Get(key)
	if !ok {
		return ""
	}
	s, ok := v.(string)
	if !ok {
		return ""
	}
	return s
}

// UserID returns the authenticated user's id.
func UserID(c *gin.Context) string { return CtxString(c, "user_id") }

// Role returns the authenticated user's role name.
func Role(c *gin.Context) string { return CtxString(c, "role") }

// FirmID returns the tenant the request belongs to.
func FirmID(c *gin.Context) string { return CtxString(c, "firm_id") }

// RequireFirm returns the caller's firm id, or writes a 403 and reports false.
// Tenant-scoped handlers must use this rather than inventing a firm id: the old
// code fell back to `uuid.New()` when the claim was empty, which silently wrote
// rows into a tenant that does not exist.
func RequireFirm(c *gin.Context) (string, bool) {
	firmID := FirmID(c)
	if firmID == "" {
		Error(c, 403, "No firm associated with this account", "missing firm context")
		c.Abort()
		return "", false
	}
	return firmID, true
}

// IsAdmin reports whether the caller may act across an entire firm.
func IsAdmin(c *gin.Context) bool {
	switch Role(c) {
	case "admin", "super_admin":
		return true
	}
	return false
}

// IsPlatformAdmin reports whether the caller may act across all firms.
func IsPlatformAdmin(c *gin.Context) bool {
	return Role(c) == "super_admin"
}
