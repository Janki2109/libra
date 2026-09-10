-- Prevents two different clients from ever holding an active booking for the
-- same lawyer at the same date+time at once. This is enforced here, at the
-- database level, rather than only by the app hiding an "unavailable" slot —
-- a partial unique index means Postgres itself rejects the losing side of a
-- race between two clients confirming the same slot at the same instant,
-- atomically, regardless of what either client's app happened to read a
-- moment earlier. Rejected/cancelled bookings free the slot back up.
CREATE UNIQUE INDEX IF NOT EXISTS uq_consultations_active_slot
    ON consultations (lawyer_id, consultation_date, consultation_time)
    WHERE status NOT IN ('rejected', 'cancelled');
