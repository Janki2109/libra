package config

import "testing"

// clearAll unsets every env var Validate/IsProduction look at, so each test
// starts from a blank slate instead of inheriting whatever is set in the
// process running the test suite.
func clearAll(t *testing.T) {
	t.Helper()
	for _, k := range []string{
		"APP_ENV", "ENV", "RENDER",
		"JWT_SECRET",
		"DB_PASSWORD", "DATABASE_URL", "DB_SSLMODE", "DB_HOST",
		"CORS_ORIGINS",
		"RAZORPAY_KEY_ID", "RAZORPAY_KEY_SECRET", "RAZORPAY_WEBHOOK_SECRET",
		"SMTP_USER", "SMTP_USERNAME", "SMTP_PASS", "SMTP_PASSWORD",
	} {
		t.Setenv(k, "")
	}
}

func baseValidProductionEnv(t *testing.T) {
	t.Helper()
	t.Setenv("APP_ENV", "production")
	t.Setenv("JWT_SECRET", "a-sufficiently-long-generated-secret-value-1234567890")
	t.Setenv("DATABASE_URL", "postgres://user:pass@db.example.com:5432/libra?sslmode=require")
}

// Render deploys used to exit on startup solely because SMTP_USER/SMTP_PASS
// were unset — email is optional, so a production process with every other
// setting correct must still start without them.
func TestValidate_ProductionStartsWithoutSMTP(t *testing.T) {
	clearAll(t)
	baseValidProductionEnv(t)

	if err := Validate(); err != nil {
		t.Fatalf("Validate() should not fail production startup when SMTP is unset, got: %v", err)
	}
}

// A placeholder SMTP_USER (left over from the committed .env) must be treated
// the same as unset — a warning, never fatal.
func TestValidate_ProductionStartsWithPlaceholderSMTP(t *testing.T) {
	clearAll(t)
	baseValidProductionEnv(t)
	t.Setenv("SMTP_USER", "your_email@example.com")
	t.Setenv("SMTP_PASS", "your_password")

	if err := Validate(); err != nil {
		t.Fatalf("Validate() should not fail production startup over a placeholder SMTP_USER, got: %v", err)
	}
}

// With real-looking SMTP credentials set, startup still succeeds — confirming
// the configured case was never the one at risk.
func TestValidate_ProductionStartsWithSMTPConfigured(t *testing.T) {
	clearAll(t)
	baseValidProductionEnv(t)
	t.Setenv("SMTP_USER", "notifications@libra.example.com")
	t.Setenv("SMTP_PASS", "a-real-app-password")

	if err := Validate(); err != nil {
		t.Fatalf("Validate() should not fail production startup with SMTP configured, got: %v", err)
	}
}

// A genuine security problem (weak JWT secret) must still block startup —
// making SMTP optional must not have weakened anything else.
func TestValidate_ProductionStillFailsOnWeakJWTSecret(t *testing.T) {
	clearAll(t)
	baseValidProductionEnv(t)
	t.Setenv("JWT_SECRET", "too-short")

	if err := Validate(); err == nil {
		t.Fatal("Validate() should still fail production startup on a weak JWT_SECRET")
	}
}

// A production DATABASE_URL pointed at localhost must still block startup —
// the SMTP change must not have touched this unrelated check.
func TestValidate_ProductionStillFailsOnLocalhostDatabase(t *testing.T) {
	clearAll(t)
	baseValidProductionEnv(t)
	t.Setenv("DATABASE_URL", "postgres://user:pass@127.0.0.1:5432/libra")

	if err := Validate(); err == nil {
		t.Fatal("Validate() should still fail production startup when DATABASE_URL points at localhost")
	}
}
