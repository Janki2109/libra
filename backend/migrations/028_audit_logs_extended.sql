-- =============================================
-- Migration 028: Extend audit_logs for the Super Admin Audit Logs module
--
-- audit_logs already existed (migration 007) with the core columns this
-- feature needs (user_id, action, module, reference_id, old_values,
-- new_values as JSONB, ip_address, user_agent, created_at) — this migration
-- only adds the columns that table genuinely lacked, rather than creating a
-- second audit table.
-- =============================================

ALTER TABLE audit_logs
    -- The actor's role AT THE TIME of the action — a user's role can change
    -- later (or the actor row can be deleted), so this must be captured at
    -- write time rather than joined from users.role_id at read time. NULL
    -- user_id + actor_role='system' identifies an automated/background
    -- action, never falsely attributed to a human.
    ADD COLUMN IF NOT EXISTS actor_role VARCHAR(30),
    ADD COLUMN IF NOT EXISTS target_type VARCHAR(50),
    ADD COLUMN IF NOT EXISTS device_type VARCHAR(20),
    ADD COLUMN IF NOT EXISTS request_id UUID DEFAULT gen_random_uuid(),
    -- The outcome of the action itself (success/failed), not a workflow
    -- status of the target — e.g. a failed refund attempt is still a real,
    -- important audit event to keep.
    ADD COLUMN IF NOT EXISTS status VARCHAR(20) NOT NULL DEFAULT 'success',
    ADD COLUMN IF NOT EXISTS description TEXT;

CREATE INDEX IF NOT EXISTS idx_audit_logs_module ON audit_logs(module);
CREATE INDEX IF NOT EXISTS idx_audit_logs_reference_id ON audit_logs(reference_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_actor_role ON audit_logs(actor_role);

-- Append-only: no application code path may UPDATE or DELETE an audit_logs
-- row. Enforced here at the database level too, so a direct SQL client or a
-- future bug in application code cannot silently tamper with the trail.
CREATE OR REPLACE FUNCTION reject_audit_log_mutation() RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION 'audit_logs is append-only: % is not permitted', TG_OP;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_audit_logs_no_update ON audit_logs;
CREATE TRIGGER trg_audit_logs_no_update
    BEFORE UPDATE OR DELETE ON audit_logs
    FOR EACH ROW EXECUTE FUNCTION reject_audit_log_mutation();
