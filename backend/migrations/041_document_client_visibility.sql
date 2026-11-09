-- A lawyer uploading a document into a case had no way to keep it off the
-- client's portal (e.g. internal notes, a draft not ready to share) — every
-- document was always visible to the client's case the moment it was linked.
-- Mirrors 036_hearing_client_visibility.sql's approach: the column defaults
-- to TRUE so no existing document a client could already see disappears
-- from under them. New uploads set this explicitly at the application layer
-- instead of relying on the column default — a client's own upload is
-- always inserted as TRUE (visible to their own lawyer and themselves), and
-- a lawyer's new upload is inserted as FALSE unless the lawyer opts it in,
-- per product requirement that new lawyer uploads default to NOT visible.
ALTER TABLE documents
    ADD COLUMN IF NOT EXISTS visible_to_client BOOLEAN NOT NULL DEFAULT TRUE;

CREATE INDEX IF NOT EXISTS idx_documents_visible_to_client
    ON documents(case_id, visible_to_client) WHERE is_archived = FALSE;
