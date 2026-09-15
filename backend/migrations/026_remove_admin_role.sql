-- =============================================
-- Migration 026: Remove the "admin" role
-- =============================================
--
-- The system is only ever meant to have 4 roles: super_admin, lawyer,
-- client, law_student. "admin" was never a distinct real-world role — it
-- was the role RegisterFirm (auth_controller.go) assigned to whichever
-- lawyer registered a new firm (the "Create Firm Account" signup path),
-- while a lawyer added afterwards via Add Staff got role='lawyer'. Every
-- permission check in the codebase already treated 'admin' and 'lawyer'
-- as equivalent (see firmStaffRoles / firmStaffRole) — the only visible
-- effect was the Admin Panel's Users page mislabeling every self-registered
-- firm founder as "ADMIN" instead of "LAWYER".
--
-- Every user who has ever been assigned 'admin' got there through that one
-- code path, so the correct role for all of them is 'lawyer' — this is not
-- a guess, it's how the application actually used the role.
UPDATE users
SET role_id = (SELECT id FROM roles WHERE name = 'lawyer')
WHERE role_id = (SELECT id FROM roles WHERE name = 'admin');

DELETE FROM roles WHERE name = 'admin';
