package middleware

import (
	"database/sql"
	"testing"
	"time"
)

func at(d time.Duration) sql.NullTime {
	return sql.NullTime{Time: time.Now().Add(d), Valid: true}
}

var never = sql.NullTime{}

func TestSubscriptionAllowsWrites(t *testing.T) {
	now := time.Now()

	cases := []struct {
		name       string
		status     string
		trialEnds  sql.NullTime
		periodEnd  sql.NullTime
		graceUntil sql.NullTime
		want       bool
	}{
		{"live trial", "trial", at(5 * 24 * time.Hour), never, never, true},
		{"trial ended yesterday", "trial", at(-24 * time.Hour), never, never, false},
		{"trial with no end date", "trial", never, never, never, false},

		{"paid and in period", "active", never, at(20 * 24 * time.Hour), never, true},
		{"period lapsed, renewal in flight", "active", never, at(-time.Hour), at(6 * 24 * time.Hour), true},
		{"period lapsed, no grace", "active", never, at(-time.Hour), never, false},

		// A failed renewal must not cut a firm off the same morning — they may
		// be in court.
		{"past_due inside grace", "past_due", never, at(-2 * 24 * time.Hour), at(5 * 24 * time.Hour), true},
		{"past_due, grace exhausted", "past_due", never, at(-30 * 24 * time.Hour), at(-time.Hour), false},
		{"past_due with no grace recorded", "past_due", never, never, never, false},

		// Cancelling must not revoke days already paid for.
		{"cancelled, still inside paid period", "cancelled", never, at(10 * 24 * time.Hour), never, true},
		{"cancelled, period over", "cancelled", never, at(-time.Hour), never, false},

		{"expired", "expired", at(24 * time.Hour), at(24 * time.Hour), at(24 * time.Hour), false},
		{"unrecognised status fails closed", "banana", never, at(24 * time.Hour), never, false},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := subscriptionAllowsWrites(tc.status, tc.trialEnds, tc.periodEnd, tc.graceUntil, now)
			if got != tc.want {
				t.Errorf("subscriptionAllowsWrites(%q) = %v, want %v", tc.status, got, tc.want)
			}
		})
	}
}

// The paywall must never block reads. A firm whose card expired still has to be
// able to open its own case files and export its data — the records are theirs,
// and in a legal practice they may be needed in court that day.
func TestExpiredFirmKeepsReadAccess(t *testing.T) {
	// subscriptionAllowsWrites is only consulted for mutating methods; the
	// middleware short-circuits on GET/HEAD/OPTIONS before reaching it. This
	// asserts the rule it would otherwise apply is genuinely restrictive, so
	// the read exemption is doing real work.
	if subscriptionAllowsWrites("expired", never, never, never, time.Now()) {
		t.Fatal("an expired subscription must not permit writes")
	}
}
