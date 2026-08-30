package middleware

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

// BodyLimit caps how much of a request body the server will read.
//
// Nothing bounded request size before. UploadDocument accepts a base64 payload
// in a JSON field, so a single POST could stream an arbitrarily large string
// into memory and then into a Postgres row — enough to exhaust the process
// from one connection.
func BodyLimit(maxBytes int64) gin.HandlerFunc {
	return func(c *gin.Context) {
		// MaxBytesReader makes the read itself fail past the limit, so an
		// oversized body is rejected as it arrives rather than after being
		// buffered.
		c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, maxBytes)
		c.Next()
	}
}
