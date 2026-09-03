-- =============================================
-- Migration 016: Mandatory GST + platform fee on invoices
--
-- invoices already had subtotal/tax_percent/tax_amount columns (migration
-- 006) — CreateInvoice just never populated them, trusting whatever
-- total_amount the Flutter app computed instead. This migration adds the
-- one genuinely missing piece (platform_fee) and reuses the rest, per the
-- "reuse existing fields" instruction.
-- =============================================

ALTER TABLE invoices
    ADD COLUMN IF NOT EXISTS platform_fee DECIMAL(12,2) NOT NULL DEFAULT 100;

-- Backfill: invoices created before this feature existed never had GST or a
-- platform fee applied, and their total_amount is a real historical figure
-- that must not be rewritten. Recording them as subtotal = total_amount,
-- tax = 0, platform_fee = 0 keeps that total exactly as it was while making
-- the new "total = subtotal + tax + platform_fee" identity hold for them
-- too, so the CHECK constraint below can apply uniformly to old and new
-- rows without touching a single historical total_amount value.
UPDATE invoices
SET subtotal = total_amount,
    tax_percent = 0,
    tax_amount = 0,
    platform_fee = 0
WHERE subtotal = 0 AND tax_amount = 0 AND platform_fee = 100;

ALTER TABLE invoices DROP CONSTRAINT IF EXISTS chk_invoices_breakdown_consistent;
ALTER TABLE invoices ADD CONSTRAINT chk_invoices_breakdown_consistent
    CHECK (total_amount = subtotal + tax_amount + platform_fee);
