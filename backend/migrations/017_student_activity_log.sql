-- Certificates on the student panel were always shown as locked — nothing
-- ever recorded a quiz score, a mock court result, or an AI advisor session,
-- so there was no data to check a certificate's requirement against. This
-- table is the one place all of that now gets logged.
CREATE TABLE IF NOT EXISTS student_activity_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    activity_type VARCHAR(50) NOT NULL,   -- 'quiz' | 'mock_court' | 'ai_advisor'
    category VARCHAR(100),                -- quiz subject (matches a certificate's requirement)
    score INT,                            -- quiz percentage score, 0-100
    result VARCHAR(20),                   -- mock court: won | lost | partial
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_student_activity_user
    ON student_activity_log(user_id, activity_type);
