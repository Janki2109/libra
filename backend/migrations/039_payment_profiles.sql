-- Saved lawyer/firm payment profiles, so a lawyer doesn't have to retype
-- the same UPI/bank details on every invoice. Each invoice still stores its
-- own snapshot of whichever fields it used (see migration 009/038) --
-- selecting a profile here only pre-fills the Create Invoice form; it is
-- never a foreign key an invoice depends on, so editing or deleting a
-- profile can never change an invoice that already went out.
CREATE TABLE IF NOT EXISTS payment_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    firm_id UUID NOT NULL REFERENCES firms(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    upi_id VARCHAR(256) DEFAULT '',
    bank_account_name VARCHAR(200) DEFAULT '',
    bank_account_number VARCHAR(32) DEFAULT '',
    bank_ifsc VARCHAR(16) DEFAULT '',
    bank_name VARCHAR(150) DEFAULT '',
    bank_branch VARCHAR(100) DEFAULT '',
    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_payment_profiles_firm ON payment_profiles(firm_id);

-- Only one default profile per firm, enforced at the DB level rather than
-- relying on the application always remembering to unset the previous
-- default first.
CREATE UNIQUE INDEX IF NOT EXISTS idx_payment_profiles_one_default
    ON payment_profiles(firm_id) WHERE is_default;
