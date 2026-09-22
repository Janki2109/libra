-- =============================================
-- Migration 033: Email uniqueness scoped to role, not global
-- =============================================
--
-- users(email) was unique app-wide (see migration 009's uq_users_email_lower),
-- so one address could only ever back a single account, regardless of role.
-- The product requirement is that the same person may hold one LAWYER, one
-- CLIENT and one STUDENT account under the same email — only a second
-- account of the *same* role for the same email must be rejected. Existing
-- rows are untouched by this migration; it only changes which combination of
-- columns must be unique going forward.
--
-- role_id is nullable in the schema (ON DELETE SET NULL) even though every
-- register handler always sets it, so the expression index coalesces NULL to
-- a fixed sentinel — otherwise two NULL role_id rows for the same email
-- would both be allowed to exist since NULL <> NULL in a uniqueness check,
-- silently reopening a duplicate-account gap.
DROP INDEX IF EXISTS uq_users_email_lower;

CREATE UNIQUE INDEX IF NOT EXISTS uq_users_email_role
    ON users (lower(email), COALESCE(role_id, '00000000-0000-0000-0000-000000000000'::uuid));

-- Forgot/Reset Password must also resolve to one specific role-scoped
-- account rather than "whichever row matches this email" now that an email
-- can have more than one. ForgotPassword records which account the code was
-- issued for; ResetPassword/verifyPasswordResetOTP re-check it before
-- touching a password, same as they already re-check the code itself.
ALTER TABLE otps ADD COLUMN IF NOT EXISTS role VARCHAR(30) DEFAULT '';
