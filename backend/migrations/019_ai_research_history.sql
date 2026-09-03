-- The AI Legal Research screen (/ai/research) was entirely stateless — every
-- query and its result vanished the moment the screen closed, with no way to
-- come back to a past answer after logging out or restarting the app. This
-- table is what LegalResearch now writes to on every successful query.
CREATE TABLE IF NOT EXISTS ai_research_history (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    firm_id UUID NOT NULL REFERENCES firms(id) ON DELETE CASCADE,
    query TEXT NOT NULL,
    response TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ai_research_history_user
    ON ai_research_history(user_id, created_at DESC);
