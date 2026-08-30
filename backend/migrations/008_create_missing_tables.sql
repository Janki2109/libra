-- =============================================
-- Migration 008: Tables the application code
-- queries but that were never created.
--
-- Migrations 001-007 stop at audit_logs and
-- court_data. The Go controllers additionally
-- read and write firms, plans, subscriptions,
-- otps, consultations, chat_rooms,
-- chat_messages, case_challenges,
-- student_progress and payment_orders — so a
-- freshly migrated database could not serve
-- signup, login-by-OTP, billing, chat, the
-- client portal or the student module at all.
-- =============================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";  -- gen_random_uuid(), used by several INSERTs

-- ─── PLANS ───────────────────────────────────
CREATE TABLE IF NOT EXISTS plans (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(50) UNIQUE NOT NULL,
    display_name VARCHAR(100) NOT NULL,
    price_monthly DECIMAL(10,2) DEFAULT 0,
    price_yearly DECIMAL(10,2) DEFAULT 0,
    max_cases INT DEFAULT 0,        -- 0 = unlimited
    max_staff INT DEFAULT 0,
    max_clients INT DEFAULT 0,
    features TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ─── FIRMS ───────────────────────────────────
-- Every tenant-scoped table keys off firms.id.
CREATE TABLE IF NOT EXISTS firms (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(150) NOT NULL,
    email VARCHAR(150),
    phone VARCHAR(20),
    address TEXT,
    city VARCHAR(50),
    state VARCHAR(50),
    pincode VARCHAR(10),
    bar_council_number VARCHAR(50),
    plan_id UUID REFERENCES plans(id) ON DELETE SET NULL,
    trial_ends_at TIMESTAMPTZ,

    -- Payout details shown on invoices.
    upi_id VARCHAR(100),
    bank_account_name VARCHAR(150),
    bank_account_number VARCHAR(50),
    bank_ifsc VARCHAR(20),
    bank_name VARCHAR(100),
    bank_branch VARCHAR(100),

    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_firms_is_active ON firms(is_active);

-- ─── SUBSCRIPTIONS ───────────────────────────
CREATE TABLE IF NOT EXISTS subscriptions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    firm_id UUID NOT NULL REFERENCES firms(id) ON DELETE CASCADE,
    plan_id UUID REFERENCES plans(id) ON DELETE SET NULL,
    billing_cycle VARCHAR(20) DEFAULT 'monthly',   -- monthly | yearly
    amount DECIMAL(10,2) DEFAULT 0,
    status VARCHAR(20) DEFAULT 'trial',            -- trial | active | past_due | cancelled
    trial_ends_at TIMESTAMPTZ,
    current_period_end TIMESTAMPTZ,
    cancelled_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_subscriptions_firm_id ON subscriptions(firm_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_status ON subscriptions(status);

-- ─── OTPS ────────────────────────────────────
-- otp_hash, never the code itself: a read-only leak of this table would
-- otherwise be an account-takeover kit for every login in flight.
CREATE TABLE IF NOT EXISTS otps (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(150) NOT NULL,
    otp_hash TEXT NOT NULL,
    purpose VARCHAR(30) DEFAULT 'login',
    attempts INT DEFAULT 0,
    is_used BOOLEAN DEFAULT FALSE,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_otps_email_live
    ON otps(email, expires_at) WHERE is_used = FALSE;

-- ─── CONSULTATIONS ───────────────────────────
CREATE TABLE IF NOT EXISTS consultations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    client_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    lawyer_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    consultation_type VARCHAR(50) NOT NULL,        -- call | video | in_person
    consultation_date DATE NOT NULL,
    consultation_time VARCHAR(20) NOT NULL,
    status VARCHAR(20) DEFAULT 'pending',          -- pending | confirmed | completed | cancelled
    notes TEXT,
    lawyer_notes TEXT,
    meeting_link TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_consultations_lawyer ON consultations(lawyer_id, status);
CREATE INDEX IF NOT EXISTS idx_consultations_client ON consultations(client_id, status);

-- ─── CHAT ────────────────────────────────────
CREATE TABLE IF NOT EXISTS chat_rooms (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    firm_id UUID REFERENCES firms(id) ON DELETE CASCADE,
    client_id UUID REFERENCES clients(id) ON DELETE CASCADE,
    lawyer_id UUID REFERENCES users(id) ON DELETE CASCADE,
    student_id UUID REFERENCES users(id) ON DELETE CASCADE,
    case_id UUID REFERENCES cases(id) ON DELETE SET NULL,
    room_name VARCHAR(150),
    last_message TEXT,
    last_message_at TIMESTAMPTZ,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_chat_rooms_firm ON chat_rooms(firm_id) WHERE is_active;
CREATE INDEX IF NOT EXISTS idx_chat_rooms_lawyer ON chat_rooms(lawyer_id) WHERE is_active;
CREATE INDEX IF NOT EXISTS idx_chat_rooms_client ON chat_rooms(client_id) WHERE is_active;

-- One live room per lawyer/client pair, and one per lawyer/student pair.
-- CreateChatRoom checks for an existing room first, but two concurrent
-- requests would both pass that check and create duplicates.
CREATE UNIQUE INDEX IF NOT EXISTS uq_chat_rooms_lawyer_client
    ON chat_rooms(lawyer_id, client_id) WHERE is_active AND client_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_chat_rooms_lawyer_student
    ON chat_rooms(lawyer_id, student_id) WHERE is_active AND student_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS chat_messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    room_id UUID NOT NULL REFERENCES chat_rooms(id) ON DELETE CASCADE,
    sender_id UUID REFERENCES users(id) ON DELETE SET NULL,
    sender_name VARCHAR(100),
    sender_role VARCHAR(50),
    message TEXT NOT NULL,
    message_type VARCHAR(20) DEFAULT 'text',       -- text | file | image
    file_url TEXT,
    file_name VARCHAR(255),
    is_read BOOLEAN DEFAULT FALSE,
    is_deleted_by_sender BOOLEAN DEFAULT FALSE,
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_chat_messages_room ON chat_messages(room_id, created_at);
CREATE INDEX IF NOT EXISTS idx_chat_messages_unread
    ON chat_messages(room_id) WHERE is_read = FALSE;

-- ─── STUDENT MODULE ──────────────────────────
CREATE TABLE IF NOT EXISTS case_challenges (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(255),
    difficulty VARCHAR(20),                        -- easy | medium | hard
    category VARCHAR(100),
    scenario TEXT,
    questions JSONB,
    answers JSONB,
    submitted_answers JSONB,
    score INT DEFAULT 0,
    max_score INT DEFAULT 0,
    is_submitted BOOLEAN DEFAULT FALSE,
    submitted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_case_challenges_user ON case_challenges(user_id, created_at);

CREATE TABLE IF NOT EXISTS student_progress (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    total_challenges INT DEFAULT 0,
    completed_challenges INT DEFAULT 0,
    total_score INT DEFAULT 0,
    streak_days INT DEFAULT 0,
    last_activity_date DATE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- The leaderboard is derived, not stored: a table would drift out of sync with
-- student_progress on every score change.
CREATE OR REPLACE VIEW student_leaderboard AS
SELECT
    sp.user_id,
    u.name,
    COALESCE(u.designation, '') AS designation,
    sp.total_score,
    sp.completed_challenges,
    sp.streak_days,
    RANK() OVER (ORDER BY sp.total_score DESC, sp.completed_challenges DESC) AS rank
FROM student_progress sp
JOIN users u ON u.id = sp.user_id
WHERE u.is_active = TRUE;

-- ─── PAYMENT ORDERS ──────────────────────────
-- Records the amount agreed when a gateway order is opened, so verification
-- can settle against that figure instead of an amount supplied by the client.
CREATE TABLE IF NOT EXISTS payment_orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    firm_id UUID NOT NULL REFERENCES firms(id) ON DELETE CASCADE,
    invoice_id UUID NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
    order_id VARCHAR(100) NOT NULL UNIQUE,
    payment_id VARCHAR(100),
    amount_paise BIGINT NOT NULL,
    currency VARCHAR(10) DEFAULT 'INR',
    status VARCHAR(20) DEFAULT 'created',          -- created | paid | failed
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payment_orders_invoice ON payment_orders(invoice_id);

-- ─── SEED PLANS ──────────────────────────────
INSERT INTO plans (name, display_name, price_monthly, price_yearly,
                   max_cases, max_staff, max_clients, features)
VALUES
  ('free',  'Free Trial', 0,    0,     25,  2,  25,  'Up to 25 cases, 2 staff, client portal'),
  ('solo',  'Solo',       499,  4990,  200, 3,  200, 'Everything in Free, plus billing and court tracking'),
  ('firm',  'Firm',       1999, 19990, 0,   15, 0,   'Unlimited cases and clients, staff roles, reports'),
  ('scale', 'Scale',      4999, 49990, 0,   0,  0,   'Unlimited everything, priority support')
ON CONFLICT (name) DO NOTHING;

-- The student role is created here so StudentRegister does not have to invent
-- it at request time.
INSERT INTO roles (name, description)
VALUES ('law_student', 'Law student with learning module access')
ON CONFLICT (name) DO NOTHING;
