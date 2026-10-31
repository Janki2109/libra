-- A lawyer adding a hearing date had no way to keep it off the client's
-- portal (e.g. an internal strategy hearing, or a date not yet confirmed) —
-- every hearing was always shown to the client the moment it was linked to
-- their case. Defaults to TRUE so every existing hearing keeps behaving
-- exactly as it already does today; a lawyer opts a specific hearing OUT,
-- rather than every past hearing silently disappearing from the client's view.
ALTER TABLE hearings
    ADD COLUMN IF NOT EXISTS visible_to_client BOOLEAN NOT NULL DEFAULT TRUE;
