-- =============================================
-- Migration 014: Consultation payments (Razorpay)
--
-- Booking a lawyer consultation used to be free and instant —
-- BookConsultation inserted a 'pending' row with no charge, and the lawyer
-- alone decided whether to confirm it. Consultations are now paid: a booking
-- is only created once Razorpay verifies payment, so `status` moves straight
-- to 'confirmed' at that point instead of waiting on manual lawyer approval.
--
-- payment_orders already grew a `kind` discriminator once, for subscription
-- checkout (migration 010) on top of invoice payment. This does the same for
-- a third kind rather than inventing a parallel table.
-- =============================================

-- ─── CONSULTATIONS ───────────────────────────
ALTER TABLE consultations
    ADD COLUMN IF NOT EXISTS payment_status VARCHAR(20) NOT NULL DEFAULT 'pending',
    ADD COLUMN IF NOT EXISTS amount_paise BIGINT,
    ADD COLUMN IF NOT EXISTS razorpay_payment_id VARCHAR(100),
    ADD COLUMN IF NOT EXISTS paid_at TIMESTAMPTZ;

ALTER TABLE consultations DROP CONSTRAINT IF EXISTS chk_consultations_payment_status;
ALTER TABLE consultations ADD CONSTRAINT chk_consultations_payment_status
    CHECK (payment_status IN ('pending', 'paid', 'failed'));

-- Lawyer-facing queries filter on this — an unpaid consultation must never
-- reach the lawyer's booking list.
CREATE INDEX IF NOT EXISTS idx_consultations_lawyer_payment
    ON consultations(lawyer_id, payment_status);

-- ─── PAYMENT ORDERS ──────────────────────────
-- firm_id was NOT NULL because both existing kinds (invoice, subscription)
-- are firm-tenant concepts. A consultation is a direct client-lawyer booking
-- with no firm involved — client and lawyer users are not always in the same
-- firm, and a client-portal account often has no firm at all.
ALTER TABLE payment_orders ALTER COLUMN firm_id DROP NOT NULL;

ALTER TABLE payment_orders
    ADD COLUMN IF NOT EXISTS consultation_id UUID REFERENCES consultations(id) ON DELETE CASCADE;

ALTER TABLE payment_orders DROP CONSTRAINT IF EXISTS chk_payment_orders_kind;
ALTER TABLE payment_orders ADD CONSTRAINT chk_payment_orders_kind
    CHECK (kind IN ('invoice', 'subscription', 'consultation'));

ALTER TABLE payment_orders DROP CONSTRAINT IF EXISTS chk_payment_orders_target;
ALTER TABLE payment_orders ADD CONSTRAINT chk_payment_orders_target
    CHECK (
        (kind = 'invoice'      AND invoice_id      IS NOT NULL) OR
        (kind = 'subscription' AND plan_id         IS NOT NULL) OR
        (kind = 'consultation' AND consultation_id IS NOT NULL)
    );

CREATE INDEX IF NOT EXISTS idx_payment_orders_consultation
    ON payment_orders(consultation_id) WHERE kind = 'consultation';
