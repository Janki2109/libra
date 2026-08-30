-- =============================================
-- Seed: roles + the platform owner account
--
-- Migration 001 already inserts the base roles.
-- This file is idempotent, so it is safe to run
-- against an existing database and covers the
-- case where 001 was applied before law_student
-- existed.
-- =============================================

INSERT INTO roles (name, description) VALUES
  ('super_admin',  'Platform owner with full access across all firms'),
  ('admin',        'Law firm admin with full access to their own firm'),
  ('lawyer',       'Lawyer with assigned case access'),
  ('staff',        'Staff with limited access'),
  ('clerk',        'Clerk with document access only'),
  ('client',       'Client portal access only'),
  ('law_student',  'Law student with learning module access')
ON CONFLICT (name) DO NOTHING;

-- ─── PLATFORM OWNER ──────────────────────────
--
-- The /api/v1/admin/* routes are restricted to super_admin, and nothing in the
-- signup flow can create one — by design, since those endpoints act across
-- every firm on the platform.
--
-- Create the first one deliberately, with a password hash you generate
-- yourself. Do NOT commit a real hash to this file.
--
--   go run ./cmd/hashpw -password 'your-strong-password'
--
-- then run, substituting the values:
--
--   INSERT INTO users (id, name, email, password_hash, role_id, is_active, email_verified)
--   SELECT gen_random_uuid(), 'Platform Owner', 'owner@example.com',
--          '<paste-hash-here>', r.id, true, true
--   FROM roles r WHERE r.name = 'super_admin'
--   ON CONFLICT DO NOTHING;
