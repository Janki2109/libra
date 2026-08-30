-- =============================================
-- Migration 009: Columns and constraints the
-- application code depends on but that were
-- never added to the schema.
--
-- Each of these caused a live SQL error at
-- runtime: UpdateCase writes won_feedback,
-- UploadDocument writes file_content and
-- mime_type, VerifyPayment writes
-- verification_status — none of which existed.
-- =============================================

-- ─── CASES ───────────────────────────────────
ALTER TABLE cases
    ADD COLUMN IF NOT EXISTS cnr_number VARCHAR(30),          -- eCourts CNR, 16 chars
    ADD COLUMN IF NOT EXISTS won_feedback TEXT,
    ADD COLUMN IF NOT EXISTS lost_reason TEXT,
    ADD COLUMN IF NOT EXISTS closed_reason TEXT,
    ADD COLUMN IF NOT EXISTS last_activity_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_cases_cnr ON cases(cnr_number) WHERE cnr_number IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_cases_firm_status ON cases(firm_id, status);

-- ─── HEARINGS ────────────────────────────────
ALTER TABLE hearings
    ADD COLUMN IF NOT EXISTS order_summary TEXT,
    ADD COLUMN IF NOT EXISTS remarks TEXT;

CREATE INDEX IF NOT EXISTS idx_hearings_firm_date ON hearings(firm_id, hearing_date);

-- ─── DOCUMENTS ───────────────────────────────
ALTER TABLE documents
    ADD COLUMN IF NOT EXISTS file_content TEXT,               -- inline base64 payload
    ADD COLUMN IF NOT EXISTS mime_type VARCHAR(120),
    ADD COLUMN IF NOT EXISTS uploaded_by_role VARCHAR(50);

CREATE INDEX IF NOT EXISTS idx_documents_firm_live
    ON documents(firm_id, created_at) WHERE is_archived = FALSE;

-- ─── INVOICES ────────────────────────────────
ALTER TABLE invoices
    ADD COLUMN IF NOT EXISTS transaction_id VARCHAR(100),
    ADD COLUMN IF NOT EXISTS payment_slip_url TEXT,
    ADD COLUMN IF NOT EXISTS upi_id VARCHAR(100),
    ADD COLUMN IF NOT EXISTS bank_account_name VARCHAR(150),
    ADD COLUMN IF NOT EXISTS bank_account_number VARCHAR(50),
    ADD COLUMN IF NOT EXISTS bank_ifsc VARCHAR(20),
    ADD COLUMN IF NOT EXISTS bank_name VARCHAR(100);

-- invoice_number was globally UNIQUE, so the moment one firm issued
-- "INV-001" no other firm on the platform could ever use that number.
-- Uniqueness belongs per tenant.
ALTER TABLE invoices DROP CONSTRAINT IF EXISTS invoices_invoice_number_key;
CREATE UNIQUE INDEX IF NOT EXISTS uq_invoices_firm_number
    ON invoices(firm_id, invoice_number);

-- paid_amount must never exceed the invoice or go negative.
ALTER TABLE invoices DROP CONSTRAINT IF EXISTS chk_invoices_paid_range;
ALTER TABLE invoices ADD CONSTRAINT chk_invoices_paid_range
    CHECK (paid_amount >= 0 AND paid_amount <= total_amount + 0.01);

ALTER TABLE invoices DROP CONSTRAINT IF EXISTS chk_invoices_total_positive;
ALTER TABLE invoices ADD CONSTRAINT chk_invoices_total_positive
    CHECK (total_amount >= 0);

-- ─── PAYMENTS ────────────────────────────────
ALTER TABLE payments
    ADD COLUMN IF NOT EXISTS payment_slip_url TEXT,
    ADD COLUMN IF NOT EXISTS verification_status VARCHAR(20) DEFAULT 'pending',
    ADD COLUMN IF NOT EXISTS rejection_reason TEXT,
    ADD COLUMN IF NOT EXISTS verified_by UUID REFERENCES users(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS verified_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

ALTER TABLE payments DROP CONSTRAINT IF EXISTS chk_payments_amount_positive;
ALTER TABLE payments ADD CONSTRAINT chk_payments_amount_positive
    CHECK (amount > 0);

-- Replaying a gateway callback must not credit an invoice twice. The
-- Razorpay verify handler relies on this index for its ON CONFLICT clause.
CREATE UNIQUE INDEX IF NOT EXISTS uq_payments_firm_txn
    ON payments(firm_id, transaction_id) WHERE transaction_id IS NOT NULL;

-- ─── USERS ───────────────────────────────────
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS must_change_password BOOLEAN DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS city VARCHAR(50),
    ADD COLUMN IF NOT EXISTS state VARCHAR(50);

-- Email uniqueness was case-sensitive, so "A@x.com" and "a@x.com" could both
-- register and only one of them could ever log in.
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_email_key;
CREATE UNIQUE INDEX IF NOT EXISTS uq_users_email_lower ON users(lower(email));

-- These were declared as bare UUIDs with no foreign key, so a firm_id could
-- point at a firm that does not exist — which is exactly what the old
-- client and student signup paths wrote.
ALTER TABLE users DROP CONSTRAINT IF EXISTS fk_users_firm;
ALTER TABLE users ADD CONSTRAINT fk_users_firm
    FOREIGN KEY (firm_id) REFERENCES firms(id) ON DELETE SET NULL;

-- ─── TENANT FOREIGN KEYS ─────────────────────
ALTER TABLE clients DROP CONSTRAINT IF EXISTS fk_clients_firm;
ALTER TABLE clients ADD CONSTRAINT fk_clients_firm
    FOREIGN KEY (firm_id) REFERENCES firms(id) ON DELETE CASCADE;

ALTER TABLE cases DROP CONSTRAINT IF EXISTS fk_cases_firm;
ALTER TABLE cases ADD CONSTRAINT fk_cases_firm
    FOREIGN KEY (firm_id) REFERENCES firms(id) ON DELETE CASCADE;

ALTER TABLE hearings DROP CONSTRAINT IF EXISTS fk_hearings_firm;
ALTER TABLE hearings ADD CONSTRAINT fk_hearings_firm
    FOREIGN KEY (firm_id) REFERENCES firms(id) ON DELETE CASCADE;

ALTER TABLE documents DROP CONSTRAINT IF EXISTS fk_documents_firm;
ALTER TABLE documents ADD CONSTRAINT fk_documents_firm
    FOREIGN KEY (firm_id) REFERENCES firms(id) ON DELETE CASCADE;

ALTER TABLE invoices DROP CONSTRAINT IF EXISTS fk_invoices_firm;
ALTER TABLE invoices ADD CONSTRAINT fk_invoices_firm
    FOREIGN KEY (firm_id) REFERENCES firms(id) ON DELETE CASCADE;

ALTER TABLE payments DROP CONSTRAINT IF EXISTS fk_payments_firm;
ALTER TABLE payments ADD CONSTRAINT fk_payments_firm
    FOREIGN KEY (firm_id) REFERENCES firms(id) ON DELETE CASCADE;

-- ─── COURT DATA ──────────────────────────────
-- GetCourtHolidays uses ON CONFLICT DO NOTHING against this table, which is a
-- no-op without a unique constraint to conflict on — so every call appended
-- another copy of all eleven holidays.
ALTER TABLE court_data
    ADD COLUMN IF NOT EXISTS cnr_number VARCHAR(30),
    ADD COLUMN IF NOT EXISTS record_type VARCHAR(30) DEFAULT 'case_status',
    ADD COLUMN IF NOT EXISTS record_date DATE,
    ADD COLUMN IF NOT EXISTS payload JSONB,
    ADD COLUMN IF NOT EXISTS source VARCHAR(50);

CREATE UNIQUE INDEX IF NOT EXISTS uq_court_data_holiday
    ON court_data(record_type, record_date)
    WHERE record_type = 'holiday';

CREATE UNIQUE INDEX IF NOT EXISTS uq_court_data_cnr
    ON court_data(cnr_number)
    WHERE cnr_number IS NOT NULL AND record_type = 'case_status';

CREATE INDEX IF NOT EXISTS idx_court_data_fetched ON court_data(fetched_at);

-- ─── NOTIFICATIONS ───────────────────────────
CREATE INDEX IF NOT EXISTS idx_notifications_user_unread
    ON notifications(user_id, created_at) WHERE is_read = FALSE;
