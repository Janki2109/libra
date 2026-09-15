-- =============================================
-- Migration 031: Super Admin Notifications Center
--
-- notifications + device_tokens already existed (migrations 007, 012) and
-- utils.SendPushToUser (utils/push.go) already sends real Firebase pushes —
-- this migration only adds what a Super Admin "campaign" needs on top of
-- that real per-user infrastructure:
--   - notification_batches: one row per Super Admin send/schedule action
--     (title, message, audience, schedule, aggregate counts).
--   - notifications.batch_id / push_status / push_error: links each
--     already-existing per-user notification row back to the batch that
--     created it, and records the real FCM outcome for that one user —
--     no separate notification_recipients table needed since notifications
--     already IS the per-recipient row.
--   - users.push_enabled: the "user disabled push" preference the spec
--     requires respecting; no UI toggle exists yet anywhere in the app, so
--     this defaults true for everyone and simply becomes real the day a
--     toggle is added — never fabricated as already-wired-up.
-- =============================================

ALTER TABLE users ADD COLUMN IF NOT EXISTS push_enabled BOOLEAN NOT NULL DEFAULT true;

CREATE TABLE IF NOT EXISTS notification_batches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    image_url TEXT,
    deep_link VARCHAR(300),
    target_type VARCHAR(20) NOT NULL
        CHECK (target_type IN ('everyone','client','lawyer','student','selected')),
    target_user_ids UUID[],
    status VARCHAR(20) NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft','scheduled','processing','sent','partially_sent','failed','cancelled')),
    recipient_count INT NOT NULL DEFAULT 0,
    sent_count INT NOT NULL DEFAULT 0,
    failed_count INT NOT NULL DEFAULT 0,
    -- Client-supplied, unique: a duplicate "Send Now" click or a retried
    -- request reuses the same key, so the second attempt reuses this row
    -- instead of creating (and sending) a second batch.
    idempotency_key VARCHAR(100) NOT NULL UNIQUE,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    scheduled_at TIMESTAMP,
    sent_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notification_batches_status ON notification_batches(status);
CREATE INDEX IF NOT EXISTS idx_notification_batches_target ON notification_batches(target_type);
CREATE INDEX IF NOT EXISTS idx_notification_batches_created_at ON notification_batches(created_at);
CREATE INDEX IF NOT EXISTS idx_notification_batches_scheduled_at ON notification_batches(scheduled_at);

ALTER TABLE notifications
    ADD COLUMN IF NOT EXISTS batch_id UUID REFERENCES notification_batches(id) ON DELETE SET NULL,
    -- 'sent' = a push was accepted by FCM; 'no_token' = user has no
    -- registered device (the in-app row still exists, just no push channel
    -- available); 'failed' = FCM returned a real error for that token.
    -- NULL means this row was not created by a Notifications Center batch.
    ADD COLUMN IF NOT EXISTS push_status VARCHAR(20)
        CHECK (push_status IS NULL OR push_status IN ('sent','no_token','failed')),
    ADD COLUMN IF NOT EXISTS push_error TEXT;

CREATE INDEX IF NOT EXISTS idx_notifications_batch_id ON notifications(batch_id);
