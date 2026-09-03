package services

import "math"

// Centralized billing configuration for firm invoices — the single place a
// bill's mandatory GST and platform fee are decided. Every caller that
// touches invoice money (CreateInvoice, and anywhere that re-validates it)
// goes through ComputeInvoiceBreakdown rather than each computing its own
// copy, so a future rate change is a one-line edit here instead of a hunt
// through every handler that touches money.
//
// Fixed today at 18% GST / ₹100 flat platform fee, as required. Kept as Go
// constants rather than a database-editable setting for now — "system
// configuration" in the sense that this is the one place they live, not
// that they're user-editable yet.
const (
	InvoiceGSTRatePercent    = 18.0
	InvoicePlatformFeeRupees = 100.0
)

// ComputeInvoiceBreakdown turns a lawyer's entered service amount into the
// full mandatory breakdown. The caller must never accept gstAmount/total
// from anywhere else (a request body, a stored draft) — this is the only
// place they are computed, and every value returned here is what gets
// persisted and charged.
func ComputeInvoiceBreakdown(subtotal float64) (gstRate, gstAmount, platformFee, total float64) {
	if subtotal < 0 {
		subtotal = 0
	}
	gstRate = InvoiceGSTRatePercent
	gstAmount = RoundMoney(subtotal * gstRate / 100)
	platformFee = InvoicePlatformFeeRupees
	total = RoundMoney(subtotal + gstAmount + platformFee)
	return
}

// RoundMoney rounds to 2 decimal places using round-half-up, matching
// services.ToPaise's reasoning: naive float truncation loses a paisa on a
// large share of amounts.
func RoundMoney(v float64) float64 {
	return math.Round(v*100) / 100
}
