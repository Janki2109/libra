package services

import (
	"errors"
	"testing"
)

func clearMailerEnv(t *testing.T) {
	t.Helper()
	for _, k := range []string{
		"SMTP_HOST", "SMTP_PORT", "SMTP_USER", "SMTP_USERNAME",
		"SMTP_PASS", "SMTP_PASSWORD", "SMTP_FROM", "SMTP_FROM_NAME",
	} {
		t.Setenv(k, "")
	}
}

// With no SMTP env vars at all, Send must refuse to pretend delivery
// happened — never silently succeed, never attempt a network call.
func TestMailer_SendWithoutConfigReturnsErrMailNotConfigured(t *testing.T) {
	clearMailerEnv(t)
	m := NewMailer()

	if m.Configured() {
		t.Fatal("Configured() should be false with no SMTP env vars set")
	}

	err := m.Send("user@example.com", "subject", "body")
	if !errors.Is(err, ErrMailNotConfigured) {
		t.Fatalf("Send() = %v, want ErrMailNotConfigured", err)
	}
}

// SendOTP and SendPasswordResetOTP must propagate the same refusal rather
// than reporting success.
func TestMailer_SendOTPWithoutConfigReturnsErrMailNotConfigured(t *testing.T) {
	clearMailerEnv(t)
	m := NewMailer()

	if err := m.SendOTP("user@example.com", "123456", 10); !errors.Is(err, ErrMailNotConfigured) {
		t.Fatalf("SendOTP() = %v, want ErrMailNotConfigured", err)
	}
	if err := m.SendPasswordResetOTP("user@example.com", "123456", 10); !errors.Is(err, ErrMailNotConfigured) {
		t.Fatalf("SendPasswordResetOTP() = %v, want ErrMailNotConfigured", err)
	}
}

// Once real-looking credentials are present, Configured() must report true
// so callers take the delivery path instead of the "not configured" one —
// this is what "SMTP works normally once configured" depends on.
func TestMailer_ConfiguredWithCredentials(t *testing.T) {
	clearMailerEnv(t)
	t.Setenv("SMTP_HOST", "smtp.example.com")
	t.Setenv("SMTP_USER", "notifications@libra.example.com")
	t.Setenv("SMTP_PASS", "a-real-app-password")

	m := NewMailer()
	if !m.Configured() {
		t.Fatal("Configured() should be true once host/user/pass/from are all set")
	}
}

// Provider dashboards (e.g. Render) often default to SMTP_USERNAME/
// SMTP_PASSWORD rather than this codebase's SMTP_USER/SMTP_PASS — both must
// be honored.
func TestMailer_ConfiguredWithAliasedEnvVars(t *testing.T) {
	clearMailerEnv(t)
	t.Setenv("SMTP_HOST", "smtp.example.com")
	t.Setenv("SMTP_USERNAME", "notifications@libra.example.com")
	t.Setenv("SMTP_PASSWORD", "a-real-app-password")

	m := NewMailer()
	if !m.Configured() {
		t.Fatal("Configured() should be true when only the SMTP_USERNAME/SMTP_PASSWORD aliases are set")
	}
}
