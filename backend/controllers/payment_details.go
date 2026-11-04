package controllers

import (
	"regexp"
	"strings"
)

// Shared validation for the UPI/bank payment details a lawyer enters so a
// client knows where to send money — used by CreateInvoice (mandatory on
// every new invoice), UpdateFirmBankDetails (the firm-wide default these
// fields are pre-filled from), and callOwnsInvoice-adjacent payment-eligibility
// checks before a client can pay. One place for the rule, instead of each
// handler re-deciding what "a valid UPI ID" means.
var (
	// Standard UPI VPA shape: handle@bank, e.g. "lawyer@okaxis". Case
	// sensitivity varies by provider, so this accepts both.
	upiIDPattern = regexp.MustCompile(`^[a-zA-Z0-9.\-_]{2,256}@[a-zA-Z]{2,64}$`)
	// Standard Indian IFSC shape: 4 letters (bank code) + literal 0 (reserved
	// for future use) + 6 alphanumeric (branch code).
	ifscPattern = regexp.MustCompile(`^[A-Z]{4}0[A-Z0-9]{6}$`)
	// Indian bank account numbers vary by bank but are conventionally
	// 9–18 digits; this is the same reasonable-length/charset check every
	// major Indian payment form uses, not a per-bank verifier (there is no
	// way to actually confirm a bank account is real without a penny-drop
	// or similar bank-side verification, which is out of scope here).
	accountNumberPattern = regexp.MustCompile(`^[0-9]{9,18}$`)
)

// nonEmptyName reports whether s is a real, non-whitespace-only value of at
// least 2 characters once trimmed — rejects "", "   ", and single-char junk
// without being so strict it rejects legitimate short names/branches.
func nonEmptyName(s string) bool {
	return len(strings.TrimSpace(s)) >= 2
}

// validatePaymentDetails checks all six mandatory payment fields together
// and returns the first problem found as a user-facing message, or "" if
// every field is present and well-formed. It never claims the account is
// real/active — only that the submitted values are plausible, well-formed
// payment instructions. "Verified" in the business sense (the bank account
// actually exists and belongs to this lawyer) is explicitly out of scope:
// there is no bank-side verification call anywhere in this codebase, and
// this function must never be read as providing one.
func validatePaymentDetails(upiID, accountName, accountNumber, ifsc, bankName, branch string) string {
	upiID = strings.TrimSpace(upiID)
	accountName = strings.TrimSpace(accountName)
	accountNumber = strings.TrimSpace(accountNumber)
	ifsc = strings.ToUpper(strings.TrimSpace(ifsc))
	bankName = strings.TrimSpace(bankName)
	branch = strings.TrimSpace(branch)

	if upiID == "" {
		return "UPI ID is required"
	}
	if !upiIDPattern.MatchString(upiID) {
		return "Enter a valid UPI ID (e.g. yourname@upi)"
	}
	if !nonEmptyName(accountName) {
		return "Account holder name is required"
	}
	if accountNumber == "" {
		return "Bank account number is required"
	}
	if !accountNumberPattern.MatchString(accountNumber) {
		return "Enter a valid bank account number (9–18 digits)"
	}
	if ifsc == "" {
		return "IFSC code is required"
	}
	if !ifscPattern.MatchString(ifsc) {
		return "Enter a valid IFSC code (e.g. SBIN0001234)"
	}
	if !nonEmptyName(bankName) {
		return "Bank name is required"
	}
	if !nonEmptyName(branch) {
		return "Branch name is required"
	}
	return ""
}

// maskAccountNumber keeps only the last 4 digits visible — same convention
// banks/payment apps use on statements — for anywhere a bank account number
// reaches a reader other than the owning lawyer or Super Admin (invoice
// PDFs, the client-facing invoice view). A number too short to meaningfully
// mask is returned unchanged rather than over-redacted into uselessness.
func maskAccountNumber(accountNumber string) string {
	n := len(accountNumber)
	if n <= 4 {
		return accountNumber
	}
	return strings.Repeat("X", n-4) + accountNumber[n-4:]
}
