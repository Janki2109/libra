-- =============================================
-- Migration 032: Advanced Lawyer Management
--
-- Enhances existing tables rather than creating parallel ones:
--   - documents: gains a real verification workflow (it had none — a
--     lawyer's verification document could be viewed but never explicitly
--     approved/rejected as its own record, only the user row's overall
--     verification_status could change).
--   - users: gains suspension/reactivation provenance. is_active already
--     existed and already meant "activity status" (kept fully distinct from
--     verification_status, per the spec) — this only adds who/when/why.
-- No new tables: lawyer-wise earnings reuse lawyer_payouts (migration 027),
-- bookings/consultation history reuse consultations, cases reuse cases,
-- and activity reuses audit_logs (migration 028) — all already real.
-- =============================================

ALTER TABLE documents
    ADD COLUMN IF NOT EXISTS verification_status VARCHAR(20)
        CHECK (verification_status IS NULL OR verification_status IN ('pending','approved','rejected')),
    ADD COLUMN IF NOT EXISTS verified_by UUID REFERENCES users(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS verified_at TIMESTAMP,
    ADD COLUMN IF NOT EXISTS rejection_reason TEXT;

-- Only lawyer_verification documents go through this workflow; every other
-- category (case documents, etc.) keeps verification_status NULL, meaning
-- "not applicable" rather than a fabricated "pending".
UPDATE documents SET verification_status = 'pending'
WHERE category = 'lawyer_verification' AND verification_status IS NULL;

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS suspension_reason TEXT,
    ADD COLUMN IF NOT EXISTS suspended_by UUID REFERENCES users(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS suspended_at TIMESTAMP,
    ADD COLUMN IF NOT EXISTS reactivated_by UUID REFERENCES users(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS reactivated_at TIMESTAMP;

CREATE INDEX IF NOT EXISTS idx_documents_verification_status ON documents(verification_status);
CREATE INDEX IF NOT EXISTS idx_cases_assigned_lawyer ON cases(assigned_lawyer_id);
