-- =============================================
-- Migration 015: Lawyer consultation earnings
--
-- Supports the lawyer-side Billing tab: a read-only ledger of what a lawyer
-- has earned from paid consultations. No new payment table — this reuses
-- consultations/payment_orders exactly as migration 014 set them up; it only
-- adds two columns those earlier endpoints had no reason to carry.
-- =============================================

-- payment_method: Razorpay's checkout handler callback carries only
-- order/payment id + signature, never the method used — so this stays NULL
-- until something calls Razorpay's Payment Fetch API or a webhook payload is
-- wired up to populate it. Nullable and simply omitted in the UI until then.
ALTER TABLE consultations
    ADD COLUMN IF NOT EXISTS payment_method VARCHAR(30);

-- 'refunded' extends the existing pending/paid/failed lifecycle so the
-- Billing screen's filter and the schema agree on what's possible, even
-- though nothing in the app can issue a refund yet (see report).
ALTER TABLE consultations DROP CONSTRAINT IF EXISTS chk_consultations_payment_status;
ALTER TABLE consultations ADD CONSTRAINT chk_consultations_payment_status
    CHECK (payment_status IN ('pending', 'paid', 'failed', 'refunded'));
