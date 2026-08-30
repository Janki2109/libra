package services

import (
	"context"
	"database/sql"
	"log"
	"strconv"
	"time"

	"libra/utils"
)

// SubscriptionSweeper moves lapsed subscriptions through their lifecycle.
//
// Without it, `status` only ever changes when someone pays. A trial that ran
// out last month still reads 'trial', an unrenewed subscription still reads
// 'active', and every entitlement check has to re-derive the truth from
// timestamps. Worse, nothing would ever notify a firm that their plan lapsed.
type SubscriptionSweeper struct {
	db       *sql.DB
	interval time.Duration
	grace    time.Duration
}

func NewSubscriptionSweeper(db *sql.DB, grace time.Duration) *SubscriptionSweeper {
	return &SubscriptionSweeper{
		db: db,
		// Hourly is ample: billing periods are measured in days, and a tighter
		// loop just adds writes.
		interval: time.Hour,
		grace:    grace,
	}
}

// Start runs the sweep now and then on the interval until ctx is cancelled.
func (s *SubscriptionSweeper) Start(ctx context.Context) {
	go func() {
		// Sweep once at boot so a process that was down over a period boundary
		// catches up immediately.
		s.Sweep(ctx)

		ticker := time.NewTicker(s.interval)
		defer ticker.Stop()

		for {
			select {
			case <-ctx.Done():
				log.Println("[billing] subscription sweeper stopped")
				return
			case <-ticker.C:
				s.Sweep(ctx)
			}
		}
	}()
}

// Sweep advances expired trials and lapsed subscriptions.
func (s *SubscriptionSweeper) Sweep(ctx context.Context) {
	if s.db == nil {
		return
	}

	// Trials that ran out.
	if n := s.exec(ctx, `
		UPDATE subscriptions
		SET status='expired', updated_at=NOW()
		WHERE status='trial' AND trial_ends_at IS NOT NULL AND trial_ends_at < NOW()
	`); n > 0 {
		log.Printf("[billing] %d trial(s) expired", n)
	}

	// Active subscriptions whose period ended without a renewal enter a grace
	// window rather than being cut off outright.
	if n := s.exec(ctx, `
		UPDATE subscriptions
		SET status='past_due',
		    grace_until = COALESCE(grace_until, current_period_end + $1::interval),
		    updated_at=NOW()
		WHERE status='active'
		  AND current_period_end IS NOT NULL
		  AND current_period_end < NOW()
	`, s.graceInterval()); n > 0 {
		log.Printf("[billing] %d subscription(s) moved to past_due", n)
	}

	// Grace exhausted.
	if n := s.exec(ctx, `
		UPDATE subscriptions
		SET status='expired', updated_at=NOW()
		WHERE status='past_due' AND grace_until IS NOT NULL AND grace_until < NOW()
	`); n > 0 {
		log.Printf("[billing] %d subscription(s) expired after grace", n)
	}

	// Cancelled subscriptions that have run out their paid period.
	s.exec(ctx, `
		UPDATE subscriptions
		SET status='expired', updated_at=NOW()
		WHERE status='cancelled'
		  AND current_period_end IS NOT NULL
		  AND current_period_end < NOW()
	`)

	s.notifyExpiringTrials(ctx)
}

// notifyExpiringTrials warns firm admins three days out, once.
//
// Letting a trial lapse in silence is the most avoidable way to lose a customer
// who was otherwise ready to pay.
func (s *SubscriptionSweeper) notifyExpiringTrials(ctx context.Context) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT u.id, s.firm_id::text,
		       to_char(s.trial_ends_at, 'DD Mon YYYY')
		FROM subscriptions s
		JOIN users u ON u.firm_id = s.firm_id AND u.is_active = true
		JOIN roles r ON u.role_id = r.id AND r.name = 'admin'
		WHERE s.status = 'trial'
		  AND s.trial_ends_at BETWEEN NOW() AND NOW() + INTERVAL '3 days'
		  AND NOT EXISTS (
		      -- Once per firm, not once per sweep.
		      SELECT 1 FROM notifications n
		      WHERE n.user_id = u.id
		        AND n.reference_type = 'subscription'
		        AND n.created_at > NOW() - INTERVAL '7 days'
		  )
	`)
	if err != nil {
		log.Printf("[billing] trial reminder failed: %v", err)
		return
	}
	defer rows.Close()

	type recipient struct{ userID, firmID, endsAt string }
	var recipients []recipient
	for rows.Next() {
		var r recipient
		if rows.Scan(&r.userID, &r.firmID, &r.endsAt) == nil {
			recipients = append(recipients, r)
		}
	}

	for _, r := range recipients {
		utils.NotifyWithRef(r.userID, r.firmID, "Your trial ends soon",
			"Your free trial ends on "+r.endsAt+". Choose a plan to keep access.",
			"general", "", "subscription")
	}
}

// graceInterval renders the grace window as a Postgres interval literal.
func (s *SubscriptionSweeper) graceInterval() string {
	days := int(s.grace.Hours() / 24)
	if days < 1 {
		days = 1
	}
	return strconv.Itoa(days) + " days"
}

func (s *SubscriptionSweeper) exec(ctx context.Context, query string, args ...interface{}) int64 {
	res, err := s.db.ExecContext(ctx, query, args...)
	if err != nil {
		log.Printf("[billing] sweep step failed: %v", err)
		return 0
	}
	n, _ := res.RowsAffected()
	return n
}
