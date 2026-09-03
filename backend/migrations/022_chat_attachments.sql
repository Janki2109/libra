-- Chat had columns for an attachment's message_type/file_url/file_name but
-- nowhere to actually put the file's bytes, and no frontend UI ever sent
-- one. file_content holds the base64 payload inline on the message row —
-- the same pattern the documents table already uses — rather than coupling
-- chat (room-membership authorization, including law students, who have no
-- firm_id and so can never pass the documents endpoints' firm-scoped
-- authorization) to the firm-scoped documents system.
ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS file_content TEXT;
ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS mime_type VARCHAR(100);
