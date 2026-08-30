package services

import "testing"

func TestValidateCNR(t *testing.T) {
	// A CNR is 4 letters (establishment code) + 12 digits.
	valid := []string{
		"MHAU010012342024",
		"DLCT010000012023",
		"KAHC010099991999",
	}
	for _, s := range valid {
		if err := ValidateCNR(s); err != nil {
			t.Errorf("ValidateCNR(%q) = %v, want nil", s, err)
		}
	}

	invalid := []string{
		"",
		"MHAU01001234202",   // 15 chars
		"MHAU0100123420244", // 17 chars
		"MHA1010012342024",  // digit in the establishment code
		"MHAU01001234202X",  // letter in the numeric tail
	}
	for _, s := range invalid {
		if err := ValidateCNR(s); err == nil {
			t.Errorf("ValidateCNR(%q) = nil, want an error", s)
		}
	}

	// Lower case and surrounding whitespace are accepted — the CNR on a filing
	// receipt is usually typed in by hand or pasted from a PDF.
	for _, s := range []string{"mhau010012342024", "  MHAU010012342024 "} {
		if err := ValidateCNR(s); err != nil {
			t.Errorf("ValidateCNR(%q) = %v, want nil", s, err)
		}
	}
}

func TestNormalizeCNR(t *testing.T) {
	if got := NormalizeCNR("  mhau010012342024 "); got != "MHAU010012342024" {
		t.Errorf("NormalizeCNR = %q, want MHAU010012342024", got)
	}
}

func TestSplitParties(t *testing.T) {
	cases := map[string][]string{
		"A Kumar, B Singh":    {"A Kumar", "B Singh"},
		"A Kumar and B Singh": {"A Kumar", "B Singh"},
		"Solo Petitioner":     {"Solo Petitioner"},
		"":                    {},
		"  ,  ":               {},
	}
	for in, want := range cases {
		got := splitParties(in)
		if len(got) != len(want) {
			t.Errorf("splitParties(%q) = %v, want %v", in, got, want)
			continue
		}
		for i := range got {
			if got[i] != want[i] {
				t.Errorf("splitParties(%q)[%d] = %q, want %q", in, i, got[i], want[i])
			}
		}
	}
}

func TestToCaseStatusNormalizesAliases(t *testing.T) {
	// Gateways disagree on field names; the normalizer must not leak that.
	raw := ecourtsCaseResponse{
		CaseStatus:     "Pending",          // rather than "status"
		PetitionerName: "A Kumar, B Singh", // rather than the array form
		RespondentName: "State of Maharashtra",
	}

	got := raw.toCaseStatus("MHAU010012342024")

	if got.Status != "Pending" {
		t.Errorf("Status = %q, want Pending", got.Status)
	}
	if len(got.Petitioners) != 2 {
		t.Errorf("Petitioners = %v, want 2 entries", got.Petitioners)
	}
	if got.CNR != "MHAU010012342024" {
		t.Errorf("CNR = %q, want the queried CNR to be filled in", got.CNR)
	}
	if got.AttributionNote == "" {
		t.Error("AttributionNote is empty; reuse of eCourts data requires attribution")
	}
}
