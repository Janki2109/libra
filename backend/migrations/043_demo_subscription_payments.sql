-- Real payment gateway integration is not available yet, so subscription
-- checkout was dead-ended at a "Payment Coming Soon" dialog that never
-- called any backend at all. This adds a payment_mode column so a demo
-- payment is clearly distinguishable from a real Razorpay one in the same
-- existing payment_orders/subscription_payments tables (no new tables, no
-- change to the real gateway path) -- the architecture this sets up lets a
-- real gateway slot in later as just another payment_mode value.
ALTER TABLE payment_orders
    ADD COLUMN IF NOT EXISTS payment_mode VARCHAR(20) NOT NULL DEFAULT 'razorpay';

ALTER TABLE subscription_payments
    ADD COLUMN IF NOT EXISTS payment_mode VARCHAR(20) NOT NULL DEFAULT 'razorpay';

ALTER TABLE payment_orders DROP CONSTRAINT IF EXISTS chk_payment_orders_mode;
ALTER TABLE payment_orders ADD CONSTRAINT chk_payment_orders_mode
    CHECK (payment_mode IN ('razorpay', 'demo', 'test'));

ALTER TABLE subscription_payments DROP CONSTRAINT IF EXISTS chk_subscription_payments_mode;
ALTER TABLE subscription_payments ADD CONSTRAINT chk_subscription_payments_mode
    CHECK (payment_mode IN ('razorpay', 'demo', 'test'));
