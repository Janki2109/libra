-- Smart Draft had zero persistence before this -- every research query,
-- file analysis and generated draft lived only in Flutter State and was
-- lost the moment the lawyer navigated away. ai_research_history
-- (migration 019) already covers the separate "AI Legal Research" screen;
-- this is Smart Draft's own equivalent, covering its three activity types
-- (drafting templates, the AI Tools panel, and file-upload analysis).
--
-- Versions of the same draft share one thread_id with an incrementing
-- version number rather than overwriting in place, so "continue editing"
-- never destroys what was there before and an earlier version stays
-- retrievable.
CREATE TABLE IF NOT EXISTS smart_draft_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    thread_id UUID NOT NULL,
    version INT NOT NULL DEFAULT 1,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    firm_id UUID REFERENCES firms(id) ON DELETE SET NULL,
    activity_type VARCHAR(20) NOT NULL, -- 'draft' | 'tool' | 'file_analysis' | 'research'
    title VARCHAR(255) NOT NULL,
    case_id UUID REFERENCES cases(id) ON DELETE SET NULL,
    input_text TEXT DEFAULT '',
    output_text TEXT NOT NULL,
    file_name VARCHAR(255) DEFAULT '',
    file_content TEXT DEFAULT '', -- base64 of the original uploaded file, if any
    mime_type VARCHAR(100) DEFAULT '',
    status VARCHAR(20) NOT NULL DEFAULT 'completed',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_smart_draft_history_user ON smart_draft_history(user_id);
CREATE INDEX IF NOT EXISTS idx_smart_draft_history_thread ON smart_draft_history(thread_id);
