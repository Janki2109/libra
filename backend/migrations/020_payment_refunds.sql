-- "Verify Payment" had no way to pay a client back — there was no refund
-- state on a payment row at all, and no Razorpay refund call anywhere in the
-- codebase. These columns record the outcome regardless of whether the
-- refund went through Razorpay's API (online payments) or was a manual
-- bookkeeping adjustment (cash/bank-transfer/UPI-proof payments, which have
-- no gateway transaction to reverse).
ALTER TABLE payments ADD COLUMN IF NOT EXISTS refund_status VARCHAR(20);
ALTER TABLE payments ADD COLUMN IF NOT EXISTS refunded_amount DECIMAL(12,2);
ALTER TABLE payments ADD COLUMN IF NOT EXISTS refunded_at TIMESTAMPTZ;
ALTER TABLE payments ADD COLUMN IF NOT EXISTS refunded_by UUID REFERENCES users(id) ON DELETE SET NULL;
-- The Razorpay refund id for an online payment, or the literal 'manual' for
-- a bookkeeping-only refund of a cash/bank-transfer/UPI-proof payment.
ALTER TABLE payments ADD COLUMN IF NOT EXISTS refund_reference VARCHAR(100);
