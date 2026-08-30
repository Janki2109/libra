package utils

import (
	"os"
	"testing"
)

func TestGenerateOTPShape(t *testing.T) {
	seen := map[string]int{}
	for i := 0; i < 500; i++ {
		otp, err := GenerateOTP()
		if err != nil {
			t.Fatalf("GenerateOTP: %v", err)
		}
		if len(otp) != 6 {
			t.Fatalf("GenerateOTP = %q, want 6 digits", otp)
		}
		for _, ch := range otp {
			if ch < '0' || ch > '9' {
				t.Fatalf("GenerateOTP = %q, want digits only", otp)
			}
		}
		seen[otp]++
	}

	// The previous implementation used the default math/rand source, which is
	// deterministic — 500 draws would have produced a short, repeating cycle.
	if len(seen) < 400 {
		t.Errorf("only %d distinct codes in 500 draws; the source looks predictable", len(seen))
	}
}

func TestHashOTPIsSaltedByEmail(t *testing.T) {
	// The same code for two different addresses must not hash alike, or a
	// leaked hash would be replayable against another account.
	a := HashOTP("a@example.com", "123456")
	b := HashOTP("b@example.com", "123456")
	if a == b {
		t.Error("HashOTP collides across addresses")
	}
	if a == "123456" || len(a) != 64 {
		t.Errorf("HashOTP = %q, want a 64-char sha256 hex digest", a)
	}
}

func TestCompareOTPHash(t *testing.T) {
	h := HashOTP("a@example.com", "123456")
	if !CompareOTPHash(h, HashOTP("a@example.com", "123456")) {
		t.Error("CompareOTPHash rejected a matching hash")
	}
	if CompareOTPHash(h, HashOTP("a@example.com", "123457")) {
		t.Error("CompareOTPHash accepted a mismatched hash")
	}
	if CompareOTPHash(h, "") {
		t.Error("CompareOTPHash accepted an empty hash")
	}
}

func TestPasswordHashRoundTrip(t *testing.T) {
	hash, err := HashPassword("correct horse battery staple")
	if err != nil {
		t.Fatalf("HashPassword: %v", err)
	}
	if !CheckPassword("correct horse battery staple", hash) {
		t.Error("CheckPassword rejected the correct password")
	}
	if CheckPassword("wrong", hash) {
		t.Error("CheckPassword accepted the wrong password")
	}
}

func TestGenerateTokenRejectsEmptyUserID(t *testing.T) {
	// VerifyOTP used to scan a missing user into zero values and mint a token
	// for "" — a session that passed the auth middleware with no user behind
	// it.
	if _, err := GenerateToken("", "a@example.com", "admin", "firm"); err == nil {
		t.Error("GenerateToken issued a token with no user id")
	}
}

func TestTokenRoundTrip(t *testing.T) {
	t.Setenv("JWT_SECRET", "test-secret-that-is-long-enough-to-use-here")

	token, err := GenerateToken("user-1", "a@example.com", "admin", "firm-1")
	if err != nil {
		t.Fatalf("GenerateToken: %v", err)
	}

	claims, err := ValidateToken(token)
	if err != nil {
		t.Fatalf("ValidateToken: %v", err)
	}
	if claims.UserID != "user-1" || claims.Role != "admin" || claims.FirmID != "firm-1" {
		t.Errorf("claims round-tripped as %+v", claims)
	}
}

func TestValidateTokenRejectsForeignSecret(t *testing.T) {
	t.Setenv("JWT_SECRET", "secret-one-that-is-long-enough-for-a-test")
	token, err := GenerateToken("user-1", "a@example.com", "admin", "firm-1")
	if err != nil {
		t.Fatalf("GenerateToken: %v", err)
	}

	t.Setenv("JWT_SECRET", "secret-two-that-is-long-enough-for-a-test")
	if _, err := ValidateToken(token); err == nil {
		t.Error("ValidateToken accepted a token signed with a different secret")
	}
}

func TestValidateTokenRejectsGarbage(t *testing.T) {
	t.Setenv("JWT_SECRET", "test-secret-that-is-long-enough-to-use-here")
	for _, s := range []string{"", "not.a.token", "a.b.c"} {
		if _, err := ValidateToken(s); err == nil {
			t.Errorf("ValidateToken(%q) succeeded", s)
		}
	}
}

func TestIsProduction(t *testing.T) {
	defer os.Unsetenv("APP_ENV")

	for _, v := range []string{"production", "PRODUCTION", "prod"} {
		t.Setenv("APP_ENV", v)
		if !IsProduction() {
			t.Errorf("IsProduction() = false for APP_ENV=%q", v)
		}
	}
	for _, v := range []string{"development", "staging", ""} {
		t.Setenv("APP_ENV", v)
		t.Setenv("ENV", "")
		if IsProduction() {
			t.Errorf("IsProduction() = true for APP_ENV=%q", v)
		}
	}
}
