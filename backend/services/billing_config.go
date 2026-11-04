package services

import (
	"libra/config"
	"math"
)

// Centralized billing configuration for firm invoices — the single place a
// bill's mandatory GST and platform fee are decided. Every caller that
// touches invoice money (CreateInvoice, and anywhere that re-validates it)
// goes through ComputeInvoiceBreakdown rather than each computing its own
// copy, so a future rate change is a one-line edit here instead of a hunt
// through every handler that touches money.
//
// These used to be hardcoded Go constants. They're now read from the
// billing_settings table (migration 037) — a single configurable row,
// seeded with these exact same values, so an operator can change the rate
// without a code deploy/redeploy. These two remain only as the fallback if
// that row is somehow missing (e.g. migration not yet applied), which keeps
// behavior identical to before this became configurable.
const (
	defaultGSTRatePercent    = 18.0
	defaultPlatformFeeRupees = 100.0
)

// CurrentBillingRates reads the live GST rate and flat platform fee. Never
// errors outward — a missing table/row/DB hiccup falls back to the defaults
// above rather than failing invoice creation.
func CurrentBillingRates() (gstRate, platformFee float64) {
	gstRate, platformFee = defaultGSTRatePercent, defaultPlatformFeeRupees
	config.DB.QueryRow(`
		SELECT gst_rate_percent, platform_fee_rupees FROM billing_settings WHERE id = 1
	`).Scan(&gstRate, &platformFee)
	return
}

// ComputeInvoiceBreakdown turns a lawyer's entered service amount into the
// full mandatory breakdown. The caller must never accept gstAmount/total
// from anywhere else (a request body, a stored draft) — this is the only
// place they are computed, and every value returned here is what gets
// persisted and charged.
func ComputeInvoiceBreakdown(subtotal float64) (gstRate, gstAmount, platformFee, total float64) {
	if subtotal < 0 {
		subtotal = 0
	}
	gstRate, platformFee = CurrentBillingRates()
	gstAmount = RoundMoney(subtotal * gstRate / 100)
	total = RoundMoney(subtotal + gstAmount + platformFee)
	return
}

// RoundMoney rounds to 2 decimal places using round-half-up, matching
// services.ToPaise's reasoning: naive float truncation loses a paisa on a
// large share of amounts.
func RoundMoney(v float64) float64 {
	return math.Round(v*100) / 100
}
