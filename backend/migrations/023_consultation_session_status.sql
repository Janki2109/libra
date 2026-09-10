-- Tracks the communication SESSION separately from the booking's own status
-- (pending/confirmed/rejected/cancelled/completed). A confirmed booking can
-- sit "waiting for lawyer" for a while before the lawyer actually starts the
-- chat/call — session_status is what the client's app checks to know whether
-- it may join yet. Only the assigned lawyer may move this to 'started' (see
-- InitiateConsultationCall), and the client-facing API never exposes a way to
-- set it directly.
ALTER TABLE consultations
    ADD COLUMN IF NOT EXISTS session_status VARCHAR(20) NOT NULL DEFAULT 'not_started';

ALTER TABLE consultations DROP CONSTRAINT IF EXISTS chk_consultations_session_status;
ALTER TABLE consultations ADD CONSTRAINT chk_consultations_session_status
    CHECK (session_status IN ('not_started', 'started', 'ended'));
