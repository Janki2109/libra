package services

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"libra/config"
	"net/http"
	"time"
)

// ErrGatewayNotConfigured is returned when Razorpay credentials are absent.
var ErrGatewayNotConfigured = errors.New("payment gateway is not configured")

// Razorpay wraps the gateway's REST API.
//
// Pulled out of the controller so subscription checkout and invoice payment
// share one implementation — the previous inline version was about to be
// copy-pasted, and a signature check that exists in two places is a signature
// check that will eventually differ in one of them.
type Razorpay struct {
	keyID      string
	keySecret  string
	webhookKey string
	http       *http.Client
}

func NewRazorpay() *Razorpay {
	return &Razorpay{
		keyID:      config.GetEnv("RAZORPAY_KEY_ID", ""),
		keySecret:  config.GetEnv("RAZORPAY_KEY_SECRET", ""),
		webhookKey: config.GetEnv("RAZORPAY_WEBHOOK_SECRET", ""),
		http:       &http.Client{Timeout: 15 * time.Second},
	}
}

// Configured reports whether orders can be created and payments verified.
func (r *Razorpay) Configured() bool {
	return r.keyID != "" && r.keySecret != ""
}

// WebhookConfigured reports whether inbound webhooks can be authenticated.
func (r *Razorpay) WebhookConfigured() bool { return r.webhookKey != "" }

// KeyID is the publishable key the app needs to open the checkout sheet.
func (r *Razorpay) KeyID() string { return r.keyID }

// Order is a created gateway order.
type Order struct {
	ID       string `json:"id"`
	Amount   int64  `json:"amount"`
	Currency string `json:"currency"`
	Status   string `json:"status"`
}

// CreateOrder opens an order for the given amount in the minor unit (paise).
func (r *Razorpay) CreateOrder(
	ctx context.Context, amountPaise int64, currency, receipt string, notes map[string]string,
) (*Order, error) {
	if !r.Configured() {
		return nil, ErrGatewayNotConfigured
	}
	if amountPaise <= 0 {
		return nil, errors.New("order amount must be positive")
	}

	body, err := json.Marshal(map[string]interface{}{
		"amount":   amountPaise,
		"currency": currency,
		"receipt":  receipt,
		"notes":    notes,
	})
	if err != nil {
		return nil, err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		"https://api.razorpay.com/v1/orders", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.SetBasicAuth(r.keyID, r.keySecret)
	req.Header.Set("Content-Type", "application/json")

	resp, err := r.http.Do(req)
	if err != nil {
		return nil, fmt.Errorf("gateway unreachable: %w", err)
	}
	defer resp.Body.Close()

	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))

	// Razorpay answers 200 here but the API family also uses 201; treating
	// anything but 200 as failure would reject valid orders.
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("gateway returned %d: %s", resp.StatusCode, string(raw))
	}

	var order Order
	if err := json.Unmarshal(raw, &order); err != nil {
		return nil, fmt.Errorf("unexpected gateway response: %w", err)
	}
	if order.ID == "" {
		return nil, errors.New("gateway returned no order id")
	}
	return &order, nil
}

// VerifyPaymentSignature checks the handshake the checkout sheet returns.
//
// hmac.Equal, not string comparison: `==` on strings short-circuits at the
// first differing byte, which leaks the expected signature one character at a
// time to anyone who can time the endpoint.
func (r *Razorpay) VerifyPaymentSignature(orderID, paymentID, signature string) error {
	if !r.Configured() {
		return ErrGatewayNotConfigured
	}
	expected := hmacSHA256Hex(orderID+"|"+paymentID, r.keySecret)
	if !hmac.Equal([]byte(expected), []byte(signature)) {
		return errors.New("payment signature mismatch")
	}
	return nil
}

// VerifyWebhookSignature authenticates an inbound webhook body.
//
// Webhooks are unauthenticated by definition — anyone on the internet can POST
// to the URL. This signature is the only thing separating a real Razorpay
// callback from someone granting themselves a paid subscription with curl, so
// the handler must refuse to process anything that fails it.
func (r *Razorpay) VerifyWebhookSignature(body []byte, signature string) error {
	if r.webhookKey == "" {
		return errors.New("RAZORPAY_WEBHOOK_SECRET is not set")
	}
	expected := hmacSHA256HexBytes(body, r.webhookKey)
	if !hmac.Equal([]byte(expected), []byte(signature)) {
		return errors.New("webhook signature mismatch")
	}
	return nil
}

func hmacSHA256Hex(data, secret string) string {
	return hmacSHA256HexBytes([]byte(data), secret)
}

func hmacSHA256HexBytes(data []byte, secret string) string {
	h := hmac.New(sha256.New, []byte(secret))
	h.Write(data)
	return hex.EncodeToString(h.Sum(nil))
}

// ToPaise converts rupees to the integer minor unit the gateway expects.
//
// int(amount*100) truncates: 1234.35 is 1234.3499… in float64, so the old
// conversion charged a paisa less than the invoice on a large share of amounts.
func ToPaise(rupees float64) int64 {
	if rupees < 0 {
		return 0
	}
	// +0.5 then truncate is round-half-up without importing math for one call.
	return int64(rupees*100 + 0.5)
}
