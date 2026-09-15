-- =============================================
-- Migration 029: Support / Complaints ticket system
--
-- No support/ticket system existed anywhere in this codebase — this adds
-- the minimum three tables needed: the ticket itself, its conversation
-- thread, and an append-only activity history (mirroring the audit_logs
-- append-only pattern from migration 028, since ticket history is itself a
-- trust record). "Assigned Super Admin" is always a users.id whose role is
-- super_admin — there is no separate admin role or table to assign to.
-- =============================================

CREATE SEQUENCE IF NOT EXISTS support_ticket_number_seq START 1024;

CREATE TABLE IF NOT EXISTS support_tickets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_number VARCHAR(20) NOT NULL UNIQUE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    subject VARCHAR(200) NOT NULL,
    description TEXT NOT NULL,
    category VARCHAR(30) NOT NULL DEFAULT 'other'
        CHECK (category IN ('booking','payment','refund','payout','subscription','account',
                             'lawyer','client','student','documents','technical','other')),
    priority VARCHAR(10) NOT NULL DEFAULT 'medium'
        CHECK (priority IN ('low','medium','high','urgent')),
    status VARCHAR(20) NOT NULL DEFAULT 'open'
        CHECK (status IN ('open','in_progress','waiting_for_user','resolved','closed')),
    assigned_super_admin_id UUID REFERENCES users(id) ON DELETE SET NULL,
    assigned_at TIMESTAMP,
    resolution_note TEXT,
    resolved_by UUID REFERENCES users(id) ON DELETE SET NULL,
    resolved_at TIMESTAMP,
    closed_by UUID REFERENCES users(id) ON DELETE SET NULL,
    closed_at TIMESTAMP,
    -- Set whenever the user sends a message the assigned admin has not yet
    -- seen, cleared when an admin views/replies — backs the "new reply"
    -- unread indicator with a real flag instead of a guess.
    has_unread_user_reply BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_support_tickets_status ON support_tickets(status);
CREATE INDEX IF NOT EXISTS idx_support_tickets_priority ON support_tickets(priority);
CREATE INDEX IF NOT EXISTS idx_support_tickets_category ON support_tickets(category);
CREATE INDEX IF NOT EXISTS idx_support_tickets_user_id ON support_tickets(user_id);
CREATE INDEX IF NOT EXISTS idx_support_tickets_assigned ON support_tickets(assigned_super_admin_id);
CREATE INDEX IF NOT EXISTS idx_support_tickets_created_at ON support_tickets(created_at);
CREATE INDEX IF NOT EXISTS idx_support_tickets_updated_at ON support_tickets(updated_at);

CREATE TABLE IF NOT EXISTS support_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id UUID NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
    sender_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    -- Captured at write time, same rationale as audit_logs.actor_role: a
    -- user's role can change later, but who they were when they sent this
    -- message must not.
    sender_role VARCHAR(30) NOT NULL,
    message TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_support_messages_ticket_id ON support_messages(ticket_id);

CREATE TABLE IF NOT EXISTS support_ticket_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id UUID NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
    actor_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    actor_role VARCHAR(30) NOT NULL,
    action VARCHAR(50) NOT NULL,
    before_value TEXT,
    after_value TEXT,
    metadata JSONB,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_support_ticket_history_ticket_id ON support_ticket_history(ticket_id);

-- Append-only, same protection as audit_logs (migration 028) — a ticket's
-- activity timeline is itself a trust record that must not be editable.
DROP TRIGGER IF EXISTS trg_support_history_no_update ON support_ticket_history;
CREATE TRIGGER trg_support_history_no_update
    BEFORE UPDATE OR DELETE ON support_ticket_history
    FOR EACH ROW EXECUTE FUNCTION reject_audit_log_mutation();
