-- =============================================
-- Migration 027: Lawyer payout settlements
--
-- No payout/settlement system exists anywhere in this codebase (see the
-- accounting note on AdminGetRevenue): a consultation payment is booked
-- 100% as lawyer earnings the moment the client pays, with no commission or
-- GST ever deducted, and no record of the platform actually transferring
-- that money to the lawyer's bank account. This migration adds exactly that
-- missing settlement record — nothing about the existing booking/payment
-- flow changes.
--
-- A settlement (lawyer_payouts) is created by a Super Admin when they
-- actually pay a lawyer; lawyer_payout_items links it to the specific paid
-- consultations it covers, so "pending" for a lawyer is simply "their paid
-- consultations not yet linked to any settlement" — never a guessed number.
-- =============================================

CREATE TABLE IF NOT EXISTS lawyer_payouts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lawyer_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    gross_amount DECIMAL(12,2) NOT NULL DEFAULT 0,
    -- No commission/GST calculation exists for consultation earnings today
    -- (the whole amount is booked to the lawyer) — these columns exist so a
    -- real deduction can be recorded the day one is introduced, and read as
    -- 0 honestly until then, rather than being invented here.
    platform_commission DECIMAL(12,2) NOT NULL DEFAULT 0,
    gst_amount DECIMAL(12,2) NOT NULL DEFAULT 0,
    net_amount DECIMAL(12,2) NOT NULL DEFAULT 0,
    transaction_count INT NOT NULL DEFAULT 0,
    status VARCHAR(20) NOT NULL DEFAULT 'paid'
        CHECK (status IN ('pending', 'processing', 'paid', 'failed', 'cancelled')),
    payout_date TIMESTAMP,
    payment_method VARCHAR(50),
    reference VARCHAR(120),
    notes TEXT,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS lawyer_payout_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payout_id UUID NOT NULL REFERENCES lawyer_payouts(id) ON DELETE CASCADE,
    consultation_id UUID NOT NULL REFERENCES consultations(id) ON DELETE RESTRICT,
    amount DECIMAL(12,2) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (consultation_id)
);

CREATE INDEX IF NOT EXISTS idx_lawyer_payouts_lawyer ON lawyer_payouts(lawyer_id);
CREATE INDEX IF NOT EXISTS idx_lawyer_payouts_status ON lawyer_payouts(status);
CREATE INDEX IF NOT EXISTS idx_lawyer_payout_items_payout ON lawyer_payout_items(payout_id);
