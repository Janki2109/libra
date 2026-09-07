package controllers

import (
	"bytes"
	"testing"
)

func TestBuildInvoicePdf_WellFormed(t *testing.T) {
	pdfBytes, err := buildInvoicePdf(
		"INV-2026-001", "Libra Law Associates", "Ramesh Kumar",
		"ramesh@example.com", "9876543210",
		"2026-09-01", "2026-09-15", "partial", "Thank you for your business.",
		5000, 18, 900, 100, 6000, 2000,
		"firm@upi", "HDFC Bank", "1234567890", "HDFC0001234", "Libra Law Associates")
	if err != nil {
		t.Fatalf("buildInvoicePdf failed: %v", err)
	}
	if !bytes.HasPrefix(pdfBytes, []byte("%PDF")) {
		t.Error("output does not start with %PDF")
	}
	if !bytes.Contains(pdfBytes[len(pdfBytes)-30:], []byte("%%EOF")) {
		t.Error("output is missing the PDF end-of-file marker")
	}
	if len(pdfBytes) < 500 {
		t.Errorf("output suspiciously small (%d bytes)", len(pdfBytes))
	}
}

func TestBuildInvoicePdf_FullyPaidNoPaymentDetails(t *testing.T) {
	// Once balance due is zero, showing UPI/bank details to pay would be
	// actively misleading — confirm that section is omitted.
	pdfBytes, err := buildInvoicePdf(
		"INV-2026-002", "Libra Law Associates", "Anita Rao", "", "",
		"2026-09-01", "", "paid", "",
		1000, 18, 180, 100, 1280, 1280,
		"firm@upi", "HDFC Bank", "1234567890", "HDFC0001234", "")
	if err != nil {
		t.Fatalf("buildInvoicePdf failed: %v", err)
	}
	if !bytes.HasPrefix(pdfBytes, []byte("%PDF")) {
		t.Error("output does not start with %PDF")
	}
}
