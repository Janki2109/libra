package services

import (
	"context"
	"database/sql"
	"log"
	"time"
)

// ContentSweeper advances scheduled content to published at its publish_at
// time, and expires published content past its expire_at time — real
// server-side scheduling per the Content Management spec ("do not depend
// only on the Flutter app being open"), following the same
// sweep-on-an-interval pattern as SubscriptionSweeper/ConsultationSweeper.
// Expired content is archived, never deleted — its row stays for history.
type ContentSweeper struct {
	db       *sql.DB
	interval time.Duration
}

func NewContentSweeper(db *sql.DB) *ContentSweeper {
	return &ContentSweeper{db: db, interval: time.Minute}
}

func (s *ContentSweeper) Start(ctx context.Context) {
	go func() {
		s.Sweep(ctx)
		ticker := time.NewTicker(s.interval)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				log.Println("[content] sweeper stopped")
				return
			case <-ticker.C:
				s.Sweep(ctx)
			}
		}
	}()
}

func (s *ContentSweeper) Sweep(ctx context.Context) {
	if s.db == nil {
		return
	}
	if n := s.exec(ctx, `
		UPDATE content_items
		SET status = 'published', published_at = COALESCE(published_at, publish_at), updated_at = NOW()
		WHERE status = 'scheduled' AND publish_at IS NOT NULL AND publish_at <= NOW()
	`); n > 0 {
		log.Printf("[content] %d item(s) auto-published", n)
	}
	if n := s.exec(ctx, `
		UPDATE content_items
		SET status = 'archived', updated_at = NOW()
		WHERE status = 'published' AND expire_at IS NOT NULL AND expire_at <= NOW()
	`); n > 0 {
		log.Printf("[content] %d item(s) auto-expired", n)
	}
}

func (s *ContentSweeper) exec(ctx context.Context, query string) int64 {
	res, err := s.db.ExecContext(ctx, query)
	if err != nil {
		log.Printf("[content] sweep step failed: %v", err)
		return 0
	}
	n, _ := res.RowsAffected()
	return n
}
