-- =============================================
-- Migration 035: Fix Student Case Challenge / Progress / Leaderboard schema
-- =============================================
--
-- controllers/challenge_controller.go (GenerateChallenge, SubmitChallenge,
-- GetStudentProgress, GetChallenge, GetLeaderboard) reads/writes columns
-- that 008_create_missing_tables.sql never created, so every one of those
-- calls has always failed at the database. This brings the schema in line
-- with what the already-shipped controller code (and the Flutter screens
-- that already expect this exact response shape — xp, case_title,
-- total_cases_completed, etc.) actually needs, without changing any
-- controller logic or API response shape.

ALTER TABLE case_challenges
    ADD COLUMN IF NOT EXISTS case_title TEXT,
    ADD COLUMN IF NOT EXISTS case_story TEXT,
    ADD COLUMN IF NOT EXISTS suspects JSONB,
    ADD COLUMN IF NOT EXISTS witnesses JSONB,
    ADD COLUMN IF NOT EXISTS evidence JSONB,
    ADD COLUMN IF NOT EXISTS status VARCHAR(20) DEFAULT 'in_progress',
    ADD COLUMN IF NOT EXISTS xp_earned INT DEFAULT 0,
    ADD COLUMN IF NOT EXISTS stars_earned INT DEFAULT 0,
    ADD COLUMN IF NOT EXISTS accuracy DECIMAL(5,2) DEFAULT 0,
    ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;

ALTER TABLE student_progress
    ADD COLUMN IF NOT EXISTS xp INT DEFAULT 0,
    ADD COLUMN IF NOT EXISTS level INT DEFAULT 1,
    ADD COLUMN IF NOT EXISTS total_cases_completed INT DEFAULT 0,
    ADD COLUMN IF NOT EXISTS current_streak INT DEFAULT 0;

-- student_leaderboard was a derived VIEW with a RANK() OVER window function,
-- which Postgres can never treat as updatable — SubmitChallenge's
-- INSERT ... ON CONFLICT DO UPDATE against it was guaranteed to fail on
-- every single challenge completion. Replaced with a real table that the
-- controller upserts into directly; rank can still be computed with
-- RANK() OVER at read time in GetLeaderboard if ever needed.
DROP VIEW IF EXISTS student_leaderboard;

CREATE TABLE IF NOT EXISTS student_leaderboard (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    user_name VARCHAR(100),
    xp INT DEFAULT 0,
    level INT DEFAULT 1,
    cases_won INT DEFAULT 0,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_student_leaderboard_xp ON student_leaderboard(xp DESC);
