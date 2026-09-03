-- Chat's "Online" status was a hardcoded literal in the Flutter UI, not
-- backed by anything real. last_active_at is touched by AuthMiddleware on
-- every authenticated request (throttled — see auth_middleware.go), so a
-- user's presence reflects genuine app activity: online while the app is in
-- active use, "last seen" once requests stop arriving.
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_active_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_users_last_active ON users(last_active_at);
