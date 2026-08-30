-- Replaces the plan list shown to new signups (Student Pro / Lawyer / Lawyer
-- Pro / Lawyer Premium) without touching existing subscribers: the old plans
-- (free/solo/firm/scale) are kept as rows — subscriptions.plan_id and
-- firms.plan_id still reference them by id — just deactivated so they no
-- longer appear in GET /auth/plans or are selectable by new signups.
UPDATE plans SET is_active = false WHERE name IN ('free', 'solo', 'firm', 'scale');

INSERT INTO plans (name, display_name, price_monthly, price_yearly, max_cases, max_staff, max_clients, features)
VALUES
  ('student_pro',     'Student Pro',     99,  990,   0, 0, 0,
   'Case Studies, Court Mock Assignments, Draft Practice, Legal Research Practice, Lawyer Activity / Practice Learning'),
  ('lawyer',           'Lawyer',          199, 1990,  0, 0, 0,
   'Multiple Cases, Client Management, Client Documents, Case Documents, Case Management'),
  ('lawyer_pro',       'Lawyer Pro',      299, 2990,  0, 0, 0,
   'Everything in Lawyer, e-Court Access, e-Court Case Details, e-Court Documents, Hearing List, Advanced Case Information'),
  ('lawyer_premium',   'Lawyer Premium',  499, 4990,  0, 0, 0,
   'Everything in Lawyer Pro, full access to all case, client, document and e-Court features, advanced and premium tools')
ON CONFLICT (name) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  price_monthly = EXCLUDED.price_monthly,
  price_yearly = EXCLUDED.price_yearly,
  features = EXCLUDED.features,
  is_active = true;
