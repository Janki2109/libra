-- Call duration was never recorded anywhere — consultation history had no
-- way to show how long a call actually lasted. Cumulative in case a
-- consultation involves more than one call attempt (a dropped call redialed).
ALTER TABLE consultations
    ADD COLUMN IF NOT EXISTS call_duration_seconds INT NOT NULL DEFAULT 0;
