package services

import (
	"strings"
	"testing"
)

func testGateway(t *testing.T) *Razorpay {
	t.Helper()
	t.Setenv("RAZORPAY_KEY_ID", "rzp_test_key")
	t.Setenv("RAZORPAY_KEY_SECRET", "test_secret")
	t.Setenv("RAZORPAY_WEBHOOK_SECRET", "webhook_secret")
	return NewRazorpay()
}

func TestVerifyPaymentSignature(t *testing.T) {
	r := testGateway(t)

	order, payment := "order_ABC123", "pay_XYZ789"
	valid := hmacSHA256Hex(order+"|"+payment, "test_secret")

	if err := r.VerifyPaymentSignature(order, payment, valid); err != nil {
		t.Errorf("rejected a valid signature: %v", err)
	}

	bad := []string{
		"",
		"deadbeef",
		valid[:len(valid)-1] + "0", // one byte off
		hmacSHA256Hex(order+"|"+payment, "different_secret"), // wrong key
		hmacSHA256Hex(order+"|pay_OTHER", "test_secret"),     // different payment
	}
	for _, sig := range bad {
		if err := r.VerifyPaymentSignature(order, payment, sig); err == nil {
			t.Errorf("accepted an invalid signature %q", sig)
		}
	}
}

// A deployment with no gateway keys must refuse rather than wave payments
// through. The original code skipped verification entirely when the secret was
// empty — the exact state a fresh deploy starts in — so anyone could POST three
// arbitrary strings and have an invoice marked paid.
func TestUnconfiguredGatewayRefuses(t *testing.T) {
	t.Setenv("RAZORPAY_KEY_ID", "")
	t.Setenv("RAZORPAY_KEY_SECRET", "")
	r := NewRazorpay()

	if r.Configured() {
		t.Fatal("Configured() true with no keys")
	}
	if err := r.VerifyPaymentSignature("o", "p", "anything"); err == nil {
		t.Fatal("an unconfigured gateway accepted a payment signature")
	}
	if _, err := r.CreateOrder(t.Context(), 100, "INR", "r", nil); err == nil {
		t.Fatal("an unconfigured gateway created an order")
	}
}

func TestVerifyWebhookSignature(t *testing.T) {
	r := testGateway(t)
	body := []byte(`{"event":"payment.captured","payload":{}}`)

	valid := hmacSHA256HexBytes(body, "webhook_secret")
	if err := r.VerifyWebhookSignature(body, valid); err != nil {
		t.Errorf("rejected a valid webhook signature: %v", err)
	}

	// The signature covers the body. A tampered payload must not verify, or
	// anyone could rewrite the amount or the order id in transit.
	tampered := []byte(`{"event":"payment.captured","payload":{"evil":true}}`)
	if err := r.VerifyWebhookSignature(tampered, valid); err == nil {
		t.Error("accepted a signature computed over different bytes")
	}

	if err := r.VerifyWebhookSignature(body, ""); err == nil {
		t.Error("accepted an empty webhook signature")
	}
	if err := r.VerifyWebhookSignature(body, hmacSHA256HexBytes(body, "wrong")); err == nil {
		t.Error("accepted a webhook signature made with the wrong key")
	}
}

func TestWebhookRefusedWithoutSecret(t *testing.T) {
	t.Setenv("RAZORPAY_WEBHOOK_SECRET", "")
	r := NewRazorpay()

	if r.WebhookConfigured() {
		t.Fatal("WebhookConfigured() true with no secret")
	}
	// Without this, an unconfigured deployment would accept any POST to the
	// webhook URL as a genuine payment notification.
	if err := r.VerifyWebhookSignature([]byte("{}"), "anything"); err == nil {
		t.Fatal("verified a webhook with no secret configured")
	}
}

func TestToPaise(t *testing.T) {
	cases := map[float64]int64{
		499:     49900,
		1234.35: 123435, // int(x*100) truncated this to 123434
		0.01:    1,
		4999.99: 499999,
		0:       0,
		-5:      0, // never bill a negative amount
	}
	for in, want := range cases {
		if got := ToPaise(in); got != want {
			t.Errorf("ToPaise(%v) = %d, want %d", in, got, want)
		}
	}
}

func TestCreateOrderRejectsNonPositiveAmount(t *testing.T) {
	r := testGateway(t)
	for _, amount := range []int64{0, -1} {
		if _, err := r.CreateOrder(t.Context(), amount, "INR", "r", nil); err == nil {
			t.Errorf("created an order for %d paise", amount)
		} else if !strings.Contains(err.Error(), "positive") {
			t.Errorf("unexpected error for %d: %v", amount, err)
		}
	}
}
