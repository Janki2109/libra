package middleware

import (
	"libra/config"
	"libra/utils"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
)

// presenceThrottle tracks, per user, when last_active_at was last written —
// touching it on literally every request would mean a write per API call
// across the whole app. Chat polls every 3s, so a 20s throttle window still
// keeps "online" (see chat_controller.go's presence handler, which treats
// anyone active within the last 2 minutes as online) comfortably fresh while
// cutting the write rate by more than 6x.
var (
	presenceMu   sync.Mutex
	presenceSeen = map[string]time.Time{}
)

const presenceThrottleWindow = 20 * time.Second

func touchPresence(userID string) {
	if userID == "" {
		return
	}
	presenceMu.Lock()
	last, ok := presenceSeen[userID]
	now := time.Now()
	if ok && now.Sub(last) < presenceThrottleWindow {
		presenceMu.Unlock()
		return
	}
	presenceSeen[userID] = now
	presenceMu.Unlock()

	go func() {
		if config.DB != nil {
			config.DB.Exec(`UPDATE users SET last_active_at = NOW() WHERE id = $1::uuid`, userID)
		}
	}()
}

func AuthMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			c.JSON(http.StatusUnauthorized, gin.H{
				"success": false,
				"message": "Authorization header required",
			})
			c.Abort()
			return
		}

		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) != 2 || parts[0] != "Bearer" {
			c.JSON(http.StatusUnauthorized, gin.H{
				"success": false,
				"message": "Invalid authorization format",
			})
			c.Abort()
			return
		}

		claims, err := utils.ValidateToken(parts[1])
		if err != nil {
			c.JSON(http.StatusUnauthorized, gin.H{
				"success": false,
				"message": "Invalid or expired token",
			})
			c.Abort()
			return
		}

		c.Set("user_id", claims.UserID)
		c.Set("email", claims.Email)
		c.Set("role", claims.Role)
		c.Set("firm_id", claims.FirmID)
		touchPresence(claims.UserID)
		c.Next()
	}
}

func RoleMiddleware(allowedRoles ...string) gin.HandlerFunc {
	return func(c *gin.Context) {
		role, exists := c.Get("role")
		if !exists {
			c.JSON(http.StatusForbidden, gin.H{
				"success": false,
				"message": "Role not found",
			})
			c.Abort()
			return
		}

		roleStr := role.(string)
		for _, allowed := range allowedRoles {
			if roleStr == allowed {
				c.Next()
				return
			}
		}

		c.JSON(http.StatusForbidden, gin.H{
			"success": false,
			"message": "Access denied",
		})
		c.Abort()
	}
}
