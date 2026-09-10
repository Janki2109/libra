-- Call History showed only a cumulative duration, computed by adding up
-- however many times SaveCallDuration was called — never an actual start or
-- end time. These record the real moments the lawyer started the session
-- (InitiateConsultationCall) and the session actually ended
-- (SaveCallDuration, once it closes the booking out to 'completed'), so
-- History can show real Start Time / End Time, not just a duration number.
ALTER TABLE consultations
    ADD COLUMN IF NOT EXISTS session_started_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS session_ended_at TIMESTAMPTZ;
