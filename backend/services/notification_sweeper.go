package services

import (
	"context"
	"database/sql"
	"log"
	"time"
)

// NotificationSweeper fires scheduled Notifications Center batches at their
// scheduled_at time — real server-side scheduling per the spec ("must not
// depend on the Flutter admin panel remaining open"), same
// sweep-on-an-interval pattern as the other sweepers in this package.
type NotificationSweeper struct {
	db      *sql.DB
	process func(batchID string)
}

// NewNotificationSweeper takes the same batch-processing function the
// immediate-send path uses (controllers.processNotificationBatch), so a
// scheduled notification is sent through the exact same real
// resolve-recipients-and-push logic, not a second copy of it.
func NewNotificationSweeper(db *sql.DB, process func(batchID string)) *NotificationSweeper {
	return &NotificationSweeper{db: db, process: process}
}

func (s *NotificationSweeper) Start(ctx context.Context) {
	go func() {
		s.Sweep(ctx)
		ticker := time.NewTicker(30 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				log.Println("[notifications] sweeper stopped")
				return
			case <-ticker.C:
				s.Sweep(ctx)
			}
		}
	}()
}

func (s *NotificationSweeper) Sweep(ctx context.Context) {
	if s.db == nil {
		return
	}
	rows, err := s.db.QueryContext(ctx, `
		SELECT id FROM notification_batches
		WHERE status = 'scheduled' AND scheduled_at IS NOT NULL AND scheduled_at <= NOW()
	`)
	if err != nil {
		log.Printf("[notifications] sweep query failed: %v", err)
		return
	}
	var due []string
	for rows.Next() {
		var id string
		if rows.Scan(&id) == nil {
			due = append(due, id)
		}
	}
	rows.Close()

	for _, id := range due {
		// Claim it first so a slow send this tick can't be picked up again
		// by the next tick before it finishes.
		res, err := s.db.ExecContext(ctx, `
			UPDATE notification_batches SET status = 'processing', updated_at = NOW()
			WHERE id = $1::uuid AND status = 'scheduled'
		`, id)
		if err != nil {
			continue
		}
		if n, _ := res.RowsAffected(); n == 0 {
			continue
		}
		log.Printf("[notifications] sending scheduled batch %s", id)
		s.process(id)
	}
}
