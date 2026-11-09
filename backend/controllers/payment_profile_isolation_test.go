package controllers

// GetPaymentProfile (added to prefill Create Invoice with a lawyer's real,
// unmasked saved bank details) must stay scoped to the authenticated
// caller's own firm — a lawyer must never fetch another firm's profile by
// guessing/enumerating its id.

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/gin-gonic/gin"
)

func ginContextWithFirm(userID, firmID, role string) (*gin.Context, *httptest.ResponseRecorder) {
	gin.SetMode(gin.TestMode)
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest(http.MethodGet, "/", nil)
	c.Set("user_id", userID)
	c.Set("firm_id", firmID)
	c.Set("role", role)
	return c, w
}

func TestGetPaymentProfile_ScopesToCallersOwnFirm(t *testing.T) {
	profileID := "33333333-3333-3333-3333-333333333333"
	firmAID := "11111111-1111-1111-1111-111111111111"
	mock := withMockDB(t)

	mock.ExpectQuery(`SELECT id, name, upi_id, bank_account_name, bank_account_number,\s*` +
		`bank_ifsc, bank_name, bank_branch, is_default, created_at\s*` +
		`FROM payment_profiles\s*WHERE id = \$1::uuid AND firm_id = \$2`).
		WithArgs(profileID, firmAID).
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "name", "upi_id", "bank_account_name", "bank_account_number",
			"bank_ifsc", "bank_name", "bank_branch", "is_default", "created_at",
		}).AddRow(profileID, "Primary", "lawyer@upi", "Lawyer A", "1234567890",
			"HDFC0001", "HDFC", "Main Branch", true, "2026-01-01"))

	c, w := ginContextWithFirm("u1", firmAID, "lawyer")
	c.Params = gin.Params{{Key: "id", Value: profileID}}
	GetPaymentProfile(c)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200 for the profile's own firm, got %d: %s", w.Code, w.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Errorf("query did not scope to the authenticated firm as expected: %v", err)
	}
}

func TestGetPaymentProfile_CannotBeFetchedByAnotherFirm(t *testing.T) {
	profileID := "33333333-3333-3333-3333-333333333333"
	firmBID := "22222222-2222-2222-2222-222222222222"
	mock := withMockDB(t)

	// Only firm A's id is ever a valid expectation -- Lawyer B's firm_id
	// never matches, so the mock returns no rows for it.
	mock.ExpectQuery(`FROM payment_profiles\s*WHERE id = \$1::uuid AND firm_id = \$2`).
		WithArgs(profileID, firmBID).
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "name", "upi_id", "bank_account_name", "bank_account_number",
			"bank_ifsc", "bank_name", "bank_branch", "is_default", "created_at",
		}))

	c, w := ginContextWithFirm("u2", firmBID, "lawyer")
	c.Params = gin.Params{{Key: "id", Value: profileID}}
	GetPaymentProfile(c)

	if w.Code != http.StatusNotFound {
		t.Errorf("expected 404 for another firm's profile id, got %d: %s", w.Code, w.Body.String())
	}
}
