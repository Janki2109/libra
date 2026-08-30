package utils

import (
	"log"
	"os"
	"strings"

	"github.com/gin-gonic/gin"
)

type Response struct {
	Success bool        `json:"success"`
	Message string      `json:"message"`
	Data    interface{} `json:"data,omitempty"`
	// Meta carries paging information for list endpoints. It sits alongside
	// Data rather than wrapping it, so adding pagination did not change the
	// shape every existing screen already parses.
	Meta  interface{} `json:"meta,omitempty"`
	Error string      `json:"error,omitempty"`
}

func Success(c *gin.Context, statusCode int, message string, data interface{}) {
	c.JSON(statusCode, Response{
		Success: true,
		Message: message,
		Data:    data,
	})
}

// SuccessWithMeta writes a paged list response.
func SuccessWithMeta(c *gin.Context, statusCode int, message string, data, meta interface{}) {
	c.JSON(statusCode, Response{
		Success: true,
		Message: message,
		Data:    data,
		Meta:    meta,
	})
}

// Error writes a failure response. The detail argument is only echoed back to
// the caller outside production: it routinely carries raw driver text such as
// `pq: relation "users" does not exist`, which hands an attacker the schema.
// In production the detail is logged server-side and the client sees only the
// human-readable message.
func Error(c *gin.Context, statusCode int, message string, detail string) {
	if detail != "" {
		log.Printf("[error] %s %s -> %d: %s | %s",
			c.Request.Method, c.Request.URL.Path, statusCode, message, detail)
	}

	resp := Response{Success: false, Message: message}
	if !IsProduction() {
		resp.Error = detail
	}
	c.JSON(statusCode, resp)
}

// IsProduction reports whether the process is running with production
// hardening enabled. Startup checks and middleware use it too.
func IsProduction() bool {
	env := strings.ToLower(os.Getenv("APP_ENV"))
	if env == "" {
		env = strings.ToLower(os.Getenv("ENV"))
	}
	return env == "production" || env == "prod"
}
