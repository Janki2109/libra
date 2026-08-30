package middleware

import (
	"libra/config"
	"log"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
)

// CorsMiddleware reflects only origins present in the CORS_ORIGINS allowlist.
//
// The previous version sent `Access-Control-Allow-Origin: *` together with
// `Access-Control-Allow-Credentials: true`. That pairing is rejected outright
// by every browser, so credentialed browser calls were failing; and where a
// client did honour it, any website on the internet could call the API with
// the user's session attached.
func CorsMiddleware() gin.HandlerFunc {
	raw := config.GetEnv("CORS_ORIGINS", "")
	allowed := map[string]bool{}
	for _, o := range strings.Split(raw, ",") {
		if o = strings.TrimSpace(o); o != "" {
			allowed[o] = true
		}
	}

	// Mobile apps send no Origin header at all, so an empty allowlist is fine
	// for an API that only serves the Flutter client. It only matters once a
	// browser front-end exists.
	if len(allowed) == 0 {
		log.Println("[cors] CORS_ORIGINS is empty — browser cross-origin requests will be refused")
	}

	return func(c *gin.Context) {
		origin := c.GetHeader("Origin")

		if origin != "" && allowed[origin] {
			h := c.Writer.Header()
			h.Set("Access-Control-Allow-Origin", origin)
			h.Set("Access-Control-Allow-Credentials", "true")
			h.Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
			h.Set("Access-Control-Allow-Headers", "Accept, Authorization, Content-Type, X-Requested-With")
			h.Set("Access-Control-Max-Age", "86400")
			// Caches must not serve one origin's response to another.
			h.Add("Vary", "Origin")
		}

		if c.Request.Method == http.MethodOptions {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}

		c.Next()
	}
}

// SecurityHeaders sets the baseline response headers an API should always send.
func SecurityHeaders() gin.HandlerFunc {
	forceHTTPS := strings.EqualFold(config.GetEnv("FORCE_HTTPS", "false"), "true")

	return func(c *gin.Context) {
		h := c.Writer.Header()
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("X-Frame-Options", "DENY")
		h.Set("Referrer-Policy", "no-referrer")
		h.Set("Cross-Origin-Resource-Policy", "same-site")
		// Responses carry case files and invoices; never let a shared cache
		// hold on to them.
		h.Set("Cache-Control", "no-store")
		if forceHTTPS {
			h.Set("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
		}
		c.Next()
	}
}
