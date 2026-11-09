-- The lawyer registration flow sent its verification document's
-- file_content as a full "data:<mime>;base64,<...>" string instead of raw
-- base64 (fixed at the application layer in register_screen.dart /
-- auth_provider.dart). UploadDocument stores file_content verbatim and
-- every open/preview/download path decodes it straight with base64Decode(),
-- which the ':' ';' ',' characters in that prefix break -- so every
-- registration document already stored this way fails to open, even though
-- it still appears correctly in the documents list by name/date (those are
-- separate metadata columns, never decoded).
--
-- One-time, idempotent cleanup: strip everything up through the first
-- comma for any existing row that was stored with this prefix. No file is
-- lost -- this only removes the prefix that was never part of the actual
-- file content to begin with. Safe to run multiple times: a row without
-- the prefix is left untouched (the WHERE clause only matches rows that
-- still have it).
UPDATE documents
SET file_content = substring(file_content FROM position(',' IN file_content) + 1)
WHERE file_content LIKE 'data:%;base64,%';
