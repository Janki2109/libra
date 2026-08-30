package controllers

import "testing"

func TestIsUUID(t *testing.T) {
	valid := []string{
		"123e4567-e89b-12d3-a456-426614174000",
		"00000000-0000-0000-0000-000000000000",
		"FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF",
	}
	for _, s := range valid {
		if !isUUID(s) {
			t.Errorf("isUUID(%q) = false, want true", s)
		}
	}

	invalid := []string{
		"",
		"today",                                 // the literal that /hearings/today would supply if the
		"pending",                               // route ordering were wrong
		"123e4567-e89b-12d3-a456-42661417400",   // one char short
		"123e4567-e89b-12d3-a456-4266141740000", // one char long
		"123e4567e89b12d3a456426614174000",      // no dashes
		"123e4567-e89b-12d3-a456-42661417400g",  // non-hex
		"123e4567-e89b-12d3-a456_426614174000",  // wrong separator
		"'; DROP TABLE cases; --",
	}
	for _, s := range invalid {
		if isUUID(s) {
			t.Errorf("isUUID(%q) = true, want false", s)
		}
	}
}

func TestNullIfEmpty(t *testing.T) {
	// An empty optional id must reach the driver as NULL, not as "", which
	// fails every ::uuid cast.
	if got := nullIfEmpty(""); got != nil {
		t.Errorf("nullIfEmpty(\"\") = %v, want nil", got)
	}
	if got := nullIfEmpty("abc"); got != "abc" {
		t.Errorf("nullIfEmpty(\"abc\") = %v, want \"abc\"", got)
	}
}

func TestValidCaseStatus(t *testing.T) {
	for _, s := range []string{"active", "pending", "closed", "won", "lost", "settled"} {
		if !validCaseStatus(s) {
			t.Errorf("validCaseStatus(%q) = false, want true", s)
		}
	}
	for _, s := range []string{"", "Active", "paid", "deleted", "won "} {
		if validCaseStatus(s) {
			t.Errorf("validCaseStatus(%q) = true, want false", s)
		}
	}
}

func TestValidConsultationStatus(t *testing.T) {
	for _, s := range []string{"pending", "confirmed", "completed", "cancelled"} {
		if !validConsultationStatus(s) {
			t.Errorf("validConsultationStatus(%q) = false, want true", s)
		}
	}
	for _, s := range []string{"", "Pending", "approved"} {
		if validConsultationStatus(s) {
			t.Errorf("validConsultationStatus(%q) = true, want false", s)
		}
	}
}

func TestNormalizeEmail(t *testing.T) {
	cases := map[string]string{
		"  Foo@Example.COM ": "foo@example.com",
		"foo@example.com":    "foo@example.com",
		"":                   "",
	}
	for in, want := range cases {
		if got := normalizeEmail(in); got != want {
			t.Errorf("normalizeEmail(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestToPaise(t *testing.T) {
	// int(amount*100) truncated: 1234.35*100 is 1234.3499... in float64, so
	// the old conversion charged a paisa less than the invoice.
	cases := map[float64]int64{
		1234.35: 123435,
		0.01:    1,
		999.99:  99999,
		12345.6: 1234560,
		0:       0,
	}
	for in, want := range cases {
		if got := toPaise(in); got != want {
			t.Errorf("toPaise(%v) = %d, want %d", in, got, want)
		}
	}
}
