-- =============================================
-- Migration 010: Subscription billing
--
-- Nothing previously moved a subscription from
-- 'trial' to 'active'. Every firm's trial simply
-- expired and the product could not take money.
-- =============================================

-- ─── PAYMENT ORDERS ──────────────────────────
-- payment_orders was invoice-only. Subscription checkouts reuse it so there is
-- one place that records "an amount was agreed with the gateway", which is what
-- verification settles against.
ALTER TABLE payment_orders
    ADD COLUMN IF NOT EXISTS kind VARCHAR(20) NOT NULL DEFAULT 'invoice',
    ADD COLUMN IF NOT EXISTS plan_id UUID REFERENCES plans(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS billing_cycle VARCHAR(20);

-- invoice_id must be nullable now: a subscription order has no invoice.
ALTER TABLE payment_orders ALTER COLUMN invoice_id DROP NOT NULL;

ALTER TABLE payment_orders DROP CONSTRAINT IF EXISTS chk_payment_orders_kind;
ALTER TABLE payment_orders ADD CONSTRAINT chk_payment_orders_kind
    CHECK (kind IN ('invoice', 'subscription'));

-- An invoice order must name an invoice; a subscription order must name a plan.
ALTER TABLE payment_orders DROP CONSTRAINT IF EXISTS chk_payment_orders_target;
ALTER TABLE payment_orders ADD CONSTRAINT chk_payment_orders_target
    CHECK (
        (kind = 'invoice'      AND invoice_id IS NOT NULL) OR
        (kind = 'subscription' AND plan_id    IS NOT NULL)
    );

CREATE INDEX IF NOT EXISTS idx_payment_orders_firm_kind
    ON payment_orders(firm_id, kind, status);

-- ─── SUBSCRIPTIONS ───────────────────────────
ALTER TABLE subscriptions
    ADD COLUMN IF NOT EXISTS started_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS last_payment_id VARCHAR(100),
    ADD COLUMN IF NOT EXISTS last_payment_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS grace_until TIMESTAMPTZ;

ALTER TABLE subscriptions DROP CONSTRAINT IF EXISTS chk_subscriptions_status;
ALTER TABLE subscriptions ADD CONSTRAINT chk_subscriptions_status
    CHECK (status IN ('trial', 'active', 'past_due', 'cancelled', 'expired'));

ALTER TABLE subscriptions DROP CONSTRAINT IF EXISTS chk_subscriptions_cycle;
ALTER TABLE subscriptions ADD CONSTRAINT chk_subscriptions_cycle
    CHECK (billing_cycle IN ('monthly', 'yearly'));

-- One live subscription per firm. Without this, a double-submitted checkout
-- creates two rows and GetMySubscription's ORDER BY picks an arbitrary one.
CREATE UNIQUE INDEX IF NOT EXISTS uq_subscriptions_firm
    ON subscriptions(firm_id);

CREATE INDEX IF NOT EXISTS idx_subscriptions_expiry
    ON subscriptions(current_period_end)
    WHERE status IN ('active', 'past_due');

-- ─── WEBHOOK EVENTS ──────────────────────────
-- Gateways retry aggressively and deliver out of order. Recording every event
-- id makes replay a no-op instead of a second month of subscription granted
-- for one payment.
CREATE TABLE IF NOT EXISTS webhook_events (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider     VARCHAR(30)  NOT NULL DEFAULT 'razorpay',
    event_id     VARCHAR(120) NOT NULL,
    event_type   VARCHAR(80),
    payload      JSONB,
    processed_at TIMESTAMPTZ,
    error        TEXT,
    received_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_webhook_events_provider_event
    ON webhook_events(provider, event_id);

CREATE INDEX IF NOT EXISTS idx_webhook_events_unprocessed
    ON webhook_events(received_at) WHERE processed_at IS NULL;

-- ─── SUBSCRIPTION PAYMENTS ───────────────────
-- Kept apart from the `payments` table, which records what a firm's CLIENTS pay
-- the firm. This records what the firm pays us. Mixing them would corrupt every
-- revenue report a firm sees.
CREATE TABLE IF NOT EXISTS subscription_payments (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    firm_id         UUID NOT NULL REFERENCES firms(id) ON DELETE CASCADE,
    subscription_id UUID REFERENCES subscriptions(id) ON DELETE SET NULL,
    plan_id         UUID REFERENCES plans(id) ON DELETE SET NULL,
    amount          DECIMAL(12,2) NOT NULL CHECK (amount >= 0),
    currency        VARCHAR(10) DEFAULT 'INR',
    billing_cycle   VARCHAR(20),
    order_id        VARCHAR(100),
    payment_id      VARCHAR(100) NOT NULL,
    status          VARCHAR(20) DEFAULT 'captured',
    period_start    TIMESTAMPTZ,
    period_end      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- The idempotency key for activation: the same gateway payment can never grant
-- two billing periods.
CREATE UNIQUE INDEX IF NOT EXISTS uq_subscription_payments_payment_id
    ON subscription_payments(payment_id);

CREATE INDEX IF NOT EXISTS idx_subscription_payments_firm
    ON subscription_payments(firm_id, created_at DESC);

-- ─── BACKFILL ────────────────────────────────
-- Firms created before this migration have a subscription row with a NULL
-- trial_ends_at, which GetMySubscription reads as "trial not active" and would
-- lock them out on deploy. Give them the trial they were promised at signup.
UPDATE subscriptions s
SET trial_ends_at = COALESCE(
        s.trial_ends_at,
        (SELECT f.trial_ends_at FROM firms f WHERE f.id = s.firm_id),
        s.created_at + INTERVAL '14 days'
    ),
    started_at = COALESCE(s.started_at, s.created_at)
WHERE s.status = 'trial';

-- Firms with no subscription row at all (the old signup path could leave one
-- behind on a partial failure) get a trial dated from when they signed up.
INSERT INTO subscriptions (id, firm_id, plan_id, billing_cycle, amount, status, trial_ends_at, started_at)
SELECT gen_random_uuid(), f.id,
       (SELECT id FROM plans WHERE name = 'free' LIMIT 1),
       'monthly', 0, 'trial',
       COALESCE(f.trial_ends_at, f.created_at + INTERVAL '14 days'),
       f.created_at
FROM firms f
WHERE NOT EXISTS (SELECT 1 FROM subscriptions s WHERE s.firm_id = f.id)
ON CONFLICT DO NOTHING;
