package middleware

import (
	"net/http"
	"strconv"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
)

// RateLimiter is a fixed-capacity token bucket keyed by client IP.
//
// Login, OTP and registration were completely unthrottled, so the API was wide
// open to credential stuffing and to OTP brute force (a 6-digit code falls in
// well under a minute at HTTP speeds).
//
// This is an in-process limiter: it protects a single instance. Once the API
// runs more than one replica, move the counter to Redis or put the limit on the
// load balancer, otherwise the effective limit multiplies by the replica count.
type RateLimiter struct {
	mu       sync.Mutex
	buckets  map[string]*bucket
	capacity int
	window   time.Duration
}

type bucket struct {
	count    int
	resetsAt time.Time
	lastSeen time.Time
}

func NewRateLimiter(capacity int, window time.Duration) *RateLimiter {
	rl := &RateLimiter{
		buckets:  make(map[string]*bucket),
		capacity: capacity,
		window:   window,
	}
	go rl.reap()
	return rl
}

// reap drops idle buckets so a flood of unique IPs cannot grow the map forever.
func (rl *RateLimiter) reap() {
	ticker := time.NewTicker(10 * time.Minute)
	defer ticker.Stop()
	for range ticker.C {
		cutoff := time.Now().Add(-30 * time.Minute)
		rl.mu.Lock()
		for k, b := range rl.buckets {
			if b.lastSeen.Before(cutoff) {
				delete(rl.buckets, k)
			}
		}
		rl.mu.Unlock()
	}
}

// Allow reports whether key may perform another action, and how long until the
// window resets if it may not.
func (rl *RateLimiter) Allow(key string) (bool, time.Duration) {
	now := time.Now()

	rl.mu.Lock()
	defer rl.mu.Unlock()

	b, ok := rl.buckets[key]
	if !ok || now.After(b.resetsAt) {
		rl.buckets[key] = &bucket{count: 1, resetsAt: now.Add(rl.window), lastSeen: now}
		return true, 0
	}

	b.lastSeen = now
	if b.count >= rl.capacity {
		return false, time.Until(b.resetsAt)
	}
	b.count++
	return true, 0
}

// Middleware throttles by client IP.
func (rl *RateLimiter) Middleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		ok, retryAfter := rl.Allow(c.ClientIP())
		if !ok {
			c.Header("Retry-After", formatSeconds(retryAfter))
			c.JSON(http.StatusTooManyRequests, gin.H{
				"success": false,
				"message": "Too many requests. Please try again shortly.",
			})
			c.Abort()
			return
		}
		c.Next()
	}
}

// formatSeconds renders a Retry-After value, which HTTP defines as a whole
// number of seconds — not a Go duration string like "1m0s".
func formatSeconds(d time.Duration) string {
	secs := int(d.Seconds())
	if secs < 1 {
		secs = 1
	}
	return strconv.Itoa(secs)
}
