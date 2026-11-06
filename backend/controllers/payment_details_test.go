package controllers

import "testing"

func TestValidatePaymentDetails(t *testing.T) {
	valid := func() (string, string, string, string, string, string) {
		return "lawyer@okaxis", "Ramesh Kumar", "123456789012", "SBIN0001234", "SBI", "MG Road"
	}

	// All valid -> no error.
	upi, name, acc, ifsc, bank, branch := valid()
	if msg := validatePaymentDetails(upi, name, acc, ifsc, bank, branch); msg != "" {
		t.Errorf("expected no error for fully valid details, got %q", msg)
	}

	// Malformed-UPI and incomplete-bank-field cases: these stay errors
	// regardless of the "only one method required" rule below, because a
	// value that *was* entered must still be well-formed/complete -- the
	// rule only excuses a method that was left entirely blank.
	cases := []struct {
		name   string
		mutate func(upi, acc, ifsc, holder, bank, branch *string)
	}{
		{"malformed UPI (no @)", func(upi, acc, ifsc, holder, bank, branch *string) { *upi = "lawyerokaxis" }},
		{"malformed UPI (no handle)", func(upi, acc, ifsc, holder, bank, branch *string) { *upi = "@okaxis" }},
		{"whitespace-only account holder name", func(upi, acc, ifsc, holder, bank, branch *string) { *holder = "   " }},
		{"empty account number", func(upi, acc, ifsc, holder, bank, branch *string) { *acc = "" }},
		{"too-short account number", func(upi, acc, ifsc, holder, bank, branch *string) { *acc = "12345" }},
		{"non-numeric account number", func(upi, acc, ifsc, holder, bank, branch *string) { *acc = "12345abc9012" }},
		{"empty IFSC", func(upi, acc, ifsc, holder, bank, branch *string) { *ifsc = "" }},
		{"malformed IFSC (missing 0)", func(upi, acc, ifsc, holder, bank, branch *string) { *ifsc = "SBIN1001234" }},
		{"malformed IFSC (too short)", func(upi, acc, ifsc, holder, bank, branch *string) { *ifsc = "SBIN000123" }},
		{"empty bank name", func(upi, acc, ifsc, holder, bank, branch *string) { *bank = "" }},
		{"empty branch name", func(upi, acc, ifsc, holder, bank, branch *string) { *branch = "" }},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			u, n, a, i, b, br := valid()
			tc.mutate(&u, &a, &i, &n, &b, &br)
			if msg := validatePaymentDetails(u, n, a, i, b, br); msg == "" {
				t.Errorf("%s: expected a validation error, got none", tc.name)
			}
		})
	}
}

// Exactly one method is required, not both -- a lawyer who only takes UPI
// shouldn't be forced to also fill in bank details, and vice versa.
func TestValidatePaymentDetails_EitherMethodAlone(t *testing.T) {
	if msg := validatePaymentDetails("lawyer@okaxis", "", "", "", "", ""); msg != "" {
		t.Errorf("UPI alone should be sufficient, got error %q", msg)
	}
	if msg := validatePaymentDetails("", "Ramesh Kumar", "123456789012", "SBIN0001234", "SBI", "MG Road"); msg != "" {
		t.Errorf("complete bank details alone should be sufficient, got error %q", msg)
	}
}

// Neither method present at all is still rejected.
func TestValidatePaymentDetails_NeitherMethod(t *testing.T) {
	if msg := validatePaymentDetails("", "", "", "", "", ""); msg == "" {
		t.Error("expected an error when no payment method is provided at all")
	}
}

// Lowercase IFSC is normalized to uppercase before the regex check, so a
// lawyer typing "sbin0001234" should still pass — case alone isn't a format
// error, only the shape matters.
func TestValidatePaymentDetails_IFSCCaseInsensitive(t *testing.T) {
	if msg := validatePaymentDetails("lawyer@okaxis", "Ramesh Kumar",
		"123456789012", "sbin0001234", "SBI", "MG Road"); msg != "" {
		t.Errorf("expected lowercase IFSC to be accepted (normalized), got %q", msg)
	}
}

func TestMaskAccountNumber(t *testing.T) {
	cases := map[string]string{
		"1234567890": "XXXXXX7890",
		"12345":      "X2345",
		"1234":       "1234", // too short to meaningfully mask — returned as-is
		"":           "",
	}
	for in, want := range cases {
		if got := maskAccountNumber(in); got != want {
			t.Errorf("maskAccountNumber(%q) = %q, want %q", in, got, want)
		}
	}
}
