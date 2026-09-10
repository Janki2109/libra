package services

import (
	"context"
	"database/sql"
	"fmt"
	"log"
	"time"

	"libra/utils"
)

// ConsultationSweeper automatically expires a confirmed, paid consultation
// that the lawyer never started within its booking window. Without this, an
// accepted booking the lawyer simply never acted on sat as 'confirmed'
// forever — bookable-looking, but with a call/chat session that could never
// actually start (InitiateConsultationCall has no time window check of its
// own), so nothing ever told either side it was effectively dead.
//
// Runs frequently (unlike the billing sweeper) since a session window is
// measured in minutes, not days, and uses the database server's own clock
// (NOW()) throughout — never a client device's clock — so expiry can't be
// gamed or missed by a wrong device time.
type ConsultationSweeper struct {
	db       *sql.DB
	interval time.Duration
	grace    time.Duration
}

func NewConsultationSweeper(db *sql.DB, grace time.Duration) *ConsultationSweeper {
	return &ConsultationSweeper{db: db, interval: time.Minute, grace: grace}
}

func (s *ConsultationSweeper) Start(ctx context.Context) {
	go func() {
		s.Sweep(ctx)
		ticker := time.NewTicker(s.interval)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				log.Println("[consultations] sweeper stopped")
				return
			case <-ticker.C:
				s.Sweep(ctx)
			}
		}
	}()
}

// Sweep expires any confirmed, paid, not-yet-started consultation whose
// scheduled slot (date + time, parsed with the server's own clock) plus the
// grace window has passed. consultation_time is free text like "10:00 AM" —
// always exactly that shape, since it only ever comes from the fixed slot
// list the booking screen offers — so to_timestamp's HH12:MI AM format
// parses it reliably; a row that somehow doesn't match is simply skipped by
// the WHERE clause rather than erroring the whole sweep.
func (s *ConsultationSweeper) Sweep(ctx context.Context) {
	if s.db == nil {
		return
	}
	rows, err := s.db.QueryContext(ctx, `
		SELECT id::text, lawyer_id::text, client_id::text, consultation_type,
		       consultation_date::text, consultation_time
		FROM consultations
		WHERE status = 'confirmed'
		  AND payment_status = 'paid'
		  AND session_status = 'not_started'
		  AND consultation_time ~ '^[0-9]{1,2}:[0-9]{2} ?(AM|PM|am|pm)$'
		  AND to_timestamp(
		        consultation_date::text || ' ' || consultation_time,
		        'YYYY-MM-DD HH12:MI AM'
		      ) + $1::interval < NOW()
	`, s.graceInterval())
	if err != nil {
		log.Printf("[consultations] sweep query failed: %v", err)
		return
	}
	type expiring struct {
		id, lawyerID, clientID, consultType, date, timeStr string
	}
	var list []expiring
	for rows.Next() {
		var e expiring
		if rows.Scan(&e.id, &e.lawyerID, &e.clientID, &e.consultType, &e.date, &e.timeStr) == nil {
			list = append(list, e)
		}
	}
	rows.Close()
	if len(list) == 0 {
		return
	}

	for _, e := range list {
		// Same guard as the SELECT (status/payment_status/session_status) so
		// a lawyer starting the session in the instant between the SELECT
		// and this UPDATE isn't overwritten back to expired.
		res, err := s.db.ExecContext(ctx, `
			UPDATE consultations
			SET status='expired', updated_at=NOW()
			WHERE id=$1::uuid AND status='confirmed' AND session_status='not_started'
		`, e.id)
		if err != nil {
			log.Printf("[consultations] failed to expire %s: %v", e.id, err)
			continue
		}
		if n, _ := res.RowsAffected(); n == 0 {
			continue
		}
		msg := fmt.Sprintf("Your %s consultation on %s at %s expired because it was not started in time.",
			e.consultType, e.date, e.timeStr)
		utils.NotifyWithRef(e.clientID, "", "Booking expired", msg, "booking_expired", e.id, "consultation")
		utils.NotifyWithRef(e.lawyerID, "", "Booking expired",
			fmt.Sprintf("A %s consultation on %s at %s expired — it was not started in time.",
				e.consultType, e.date, e.timeStr),
			"booking_expired", e.id, "consultation")
	}
	log.Printf("[consultations] %d booking(s) expired", len(list))
}

func (s *ConsultationSweeper) graceInterval() string {
	mins := int(s.grace.Minutes())
	if mins < 1 {
		mins = 1
	}
	return fmt.Sprintf("%d minutes", mins)
}
