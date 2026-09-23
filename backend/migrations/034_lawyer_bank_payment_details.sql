-- =============================================
-- Migration 034: Lawyer payout bank details + payment breakdown snapshot
-- =============================================
--
-- Part 1 — Lawyer bank details for payout/settlement only. These are never
-- shown to a client as a payment destination (clients pay via Razorpay
-- Checkout, or the firm's own upi_id/bank_* columns on invoices/firms for
-- the manual-transfer flow); they exist purely so Super Admin can settle a
-- lawyer's payout to the right account. account_number is a full value at
-- rest (needed to actually pay the lawyer) — the API layer is responsible
-- for masking it to last 4 digits for every reader except the owning lawyer
-- and Super Admin.
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS bank_account_holder_name VARCHAR(150),
    ADD COLUMN IF NOT EXISTS bank_name VARCHAR(150),
    ADD COLUMN IF NOT EXISTS bank_account_number VARCHAR(50),
    ADD COLUMN IF NOT EXISTS bank_ifsc VARCHAR(20),
    ADD COLUMN IF NOT EXISTS bank_passbook_document_id UUID REFERENCES documents(id) ON DELETE SET NULL;

-- Part 2 — Snapshot of the money breakdown at the moment a payment is
-- recorded, so a receipt (client/lawyer/Super Admin) never has to
-- reconstruct it from the invoice's current state, which could since have
-- changed. razorpay_order_id is duplicated here from payment_orders purely
-- for a one-table receipt read; payment_orders remains the source of truth
-- used by CreateRazorpayOrder/VerifyRazorpayPayment for order matching.
ALTER TABLE payments
    ADD COLUMN IF NOT EXISTS razorpay_order_id VARCHAR(100),
    ADD COLUMN IF NOT EXISTS gst_amount DECIMAL(12,2),
    ADD COLUMN IF NOT EXISTS platform_fee DECIMAL(12,2),
    ADD COLUMN IF NOT EXISTS lawyer_payable_amount DECIMAL(12,2);
