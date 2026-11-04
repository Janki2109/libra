-- Makes the invoice GST rate and flat platform fee a configurable setting
-- instead of a hardcoded Go constant (services.InvoiceGSTRatePercent /
-- InvoicePlatformFeeRupees). Single-row table (id is pinned to 1 by the
-- CHECK) rather than a generic key-value settings table, since these are
-- the only two values this needs right now and a pinned row is simpler to
-- read/update correctly than a key-value pair that could be typo'd.
--
-- Seeded with the exact values the old hardcoded constants used, so this
-- migration changes nothing about existing invoice totals on its own.
CREATE TABLE IF NOT EXISTS billing_settings (
    id SMALLINT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    gst_rate_percent NUMERIC(5,2) NOT NULL DEFAULT 18.00,
    platform_fee_rupees NUMERIC(10,2) NOT NULL DEFAULT 100.00,
    updated_at TIMESTAMP DEFAULT NOW()
);

INSERT INTO billing_settings (id, gst_rate_percent, platform_fee_rupees)
VALUES (1, 18.00, 100.00)
ON CONFLICT (id) DO NOTHING;
