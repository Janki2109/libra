-- Real, persistent certificate records. GetCertificates previously only
-- ever computed "earned/progress/target" live against student_activity_log
-- and case_challenges on every call -- there was no certificate ID, no
-- issue date, nothing a PDF or a verification lookup could reference, and
-- "earned" could in principle flicker if the underlying activity rows were
-- ever edited/deleted. The first time a student is found to have earned a
-- given certificate, a real row is written here and never recomputed
-- afterward -- the certificate, once issued, is a fact about the past, not
-- a live re-evaluation.
CREATE TABLE IF NOT EXISTS student_certificates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    certificate_number VARCHAR(30) NOT NULL UNIQUE,
    student_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    certificate_key VARCHAR(50) NOT NULL,
    course_name VARCHAR(200) NOT NULL,
    student_name VARCHAR(200) NOT NULL,
    instructor_name VARCHAR(150) NOT NULL DEFAULT 'OneLegal Faculty',
    director_name VARCHAR(150) NOT NULL DEFAULT 'OneLegal Directorate',
    status VARCHAR(20) NOT NULL DEFAULT 'valid' CHECK (status IN ('valid', 'revoked')),
    completed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    issued_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- One certificate per student per achievement -- re-earning the same
-- badge (impossible today since progress only ever counts up, but kept as
-- an explicit guarantee rather than an accident of current activity logic)
-- must never create a second row.
CREATE UNIQUE INDEX IF NOT EXISTS uq_student_certificates_student_key
    ON student_certificates(student_id, certificate_key);

CREATE INDEX IF NOT EXISTS idx_student_certificates_student
    ON student_certificates(student_id);

-- certificate_number values look like OL-2026-000001 -- the sequence gives
-- the always-unique, always-increasing tail number; the year prefix is
-- applied at insert time from the DB's own clock, not trusted from the app.
CREATE SEQUENCE IF NOT EXISTS student_certificate_number_seq START 1;
