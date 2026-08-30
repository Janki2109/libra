-- Lawyer document verification. Dashboard access does NOT depend on this
-- status — it only drives the admin verification panel and the notification
-- sent to the lawyer. Defaulting to 'verified' keeps the column inert for
-- every existing row and every other role; Register() sets it to 'pending'
-- explicitly for newly signed-up lawyers.
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS verification_status VARCHAR(20) NOT NULL DEFAULT 'verified',
    ADD COLUMN IF NOT EXISTS rejection_reason TEXT,
    ADD COLUMN IF NOT EXISTS verified_by UUID REFERENCES users(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS verified_at TIMESTAMPTZ;
