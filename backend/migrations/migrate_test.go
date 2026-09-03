package migrations

import (
	"strings"
	"testing"
)

// TestAllMigrationsAreEmbedded guards against a migration file that exists on
// disk but never reaches a compiled binary. The //go:embed pattern fails
// silently in that case: the server starts, reports "schema is up to date",
// and then 500s on the first query against the missing table.
func TestAllMigrationsAreEmbedded(t *testing.T) {
	names, err := List()
	if err != nil {
		t.Fatalf("List: %v", err)
	}

	want := []string{
		"001_create_users_roles.sql",
		"002_create_clients.sql",
		"003_create_cases.sql",
		"004_create_hearings.sql",
		"005_create_documents.sql",
		"006_create_billing.sql",
		"007_create_remaining_tables.sql",
		"008_create_missing_tables.sql",
		"009_add_missing_columns.sql",
		"010_subscription_billing.sql",
		"011_lawyer_verification.sql",
		"012_device_tokens.sql",
		"013_new_lawyer_student_plans.sql",
		"014_consultation_payments.sql",
		"015_consultation_earnings.sql",
		"016_invoice_gst_platform_fee.sql",
		"017_student_activity_log.sql",
		"018_consultation_call_duration.sql",
		"019_ai_research_history.sql",
		"020_payment_refunds.sql",
		"021_user_presence.sql",
		"022_chat_attachments.sql",
	}

	if len(names) != len(want) {
		t.Fatalf("embedded %d migrations %v, want %d", len(names), names, len(want))
	}
	for i := range want {
		if names[i] != want[i] {
			t.Errorf("migration %d = %q, want %q", i, names[i], want[i])
		}
	}
}

// TestMigrationsAreOrdered confirms the zero-padded prefixes keep lexical order
// equal to execution order — 009 must not run before 010 once a tenth exists.
func TestMigrationsAreOrdered(t *testing.T) {
	names, err := List()
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	for i, n := range names {
		if len(n) < 4 || n[3] != '_' {
			t.Errorf("migration %q does not start with a 3-digit zero-padded prefix", n)
		}
		if i > 0 && names[i-1] >= n {
			t.Errorf("migrations out of order: %q then %q", names[i-1], n)
		}
	}
}

// TestMigrationsAreNonEmpty catches a file that was created but never written —
// the repository shipped several such placeholders.
func TestMigrationsAreNonEmpty(t *testing.T) {
	names, err := List()
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	for _, n := range names {
		body, err := migrationFS.ReadFile(n)
		if err != nil {
			t.Fatalf("ReadFile(%q): %v", n, err)
		}
		if len(strings.TrimSpace(string(body))) == 0 {
			t.Errorf("migration %q is empty", n)
		}
	}
}

// TestSchemaCoversTablesTheCodeQueries pins the tables that migrations 001-007
// omitted. Every one of these caused a live SQL error: the controllers query
// them, but nothing created them.
func TestSchemaCoversTablesTheCodeQueries(t *testing.T) {
	names, err := List()
	if err != nil {
		t.Fatalf("List: %v", err)
	}

	var all strings.Builder
	for _, n := range names {
		body, err := migrationFS.ReadFile(n)
		if err != nil {
			t.Fatalf("ReadFile(%q): %v", n, err)
		}
		all.Write(body)
	}
	schema := strings.ToLower(all.String())

	tables := []string{
		"firms", "plans", "subscriptions", "otps", "consultations",
		"chat_rooms", "chat_messages", "case_challenges", "student_progress",
		"payment_orders", "users", "roles", "clients", "cases", "hearings",
		"documents", "invoices", "payments", "notifications", "audit_logs",
		"court_data", "case_notes", "case_timeline",
		// Billing (010): without these, a trial can never become a paid plan.
		"webhook_events", "subscription_payments",
	}
	for _, tbl := range tables {
		if !strings.Contains(schema, "create table "+tbl) &&
			!strings.Contains(schema, "create table if not exists "+tbl) {
			t.Errorf("no CREATE TABLE for %q, but the controllers query it", tbl)
		}
	}

	// Columns added in 009 that the code writes to.
	columns := []string{
		"won_feedback", "lost_reason", "closed_reason", "last_activity_at",
		"cnr_number", "file_content", "mime_type", "uploaded_by_role",
		"verification_status", "verified_by", "must_change_password",
		"otp_hash", "payment_slip_url",
		// Billing (010).
		"grace_until", "current_period_end", "last_payment_id", "billing_cycle",
	}
	for _, col := range columns {
		if !strings.Contains(schema, col) {
			t.Errorf("column %q is written by the controllers but absent from the schema", col)
		}
	}
}
