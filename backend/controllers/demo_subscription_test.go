package controllers

// DemoActivateSubscription is the real, always-available replacement for
// the dead-ended "Payment Coming Soon" dialog. These assert its most
// important rule (Phase 4 of the request): a firm with an active,
// unexpired subscription must be rejected, never allowed to stack a
// second active plan, and a firm with no conflicting active subscription
// activates cleanly and is tagged payment_mode='demo' throughout.

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/gin-gonic/gin"
)

func ginContextForDemoPay(userID, firmID, role, body string) (*gin.Context, *httptest.ResponseRecorder) {
	gin.SetMode(gin.TestMode)
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest(http.MethodPost, "/subscription/demo-pay", strings.NewReader(body))
	c.Request.Header.Set("Content-Type", "application/json")
	c.Set("user_id", userID)
	c.Set("firm_id", firmID)
	c.Set("role", role)
	return c, w
}

func TestDemoActivateSubscription_RejectsWhenAlreadyActive(t *testing.T) {
	lawyerID := "11111111-1111-1111-1111-111111111111"
	firmID := "22222222-2222-2222-2222-222222222222"
	planID := "33333333-3333-3333-3333-333333333333"
	mock := withMockDB(t)

	mock.ExpectQuery(`SELECT id, display_name, price_monthly, price_yearly\s*FROM plans WHERE name = \$1 AND is_active = true`).
		WithArgs("solo").
		WillReturnRows(sqlmock.NewRows([]string{"id", "display_name", "price_monthly", "price_yearly"}).
			AddRow(planID, "Solo", 99.0, 999.0))

	mock.ExpectBegin()
	mock.ExpectQuery(`SELECT id::text, status, current_period_end FROM subscriptions\s*WHERE firm_id = \$1::uuid FOR UPDATE`).
		WithArgs(firmID).
		WillReturnRows(sqlmock.NewRows([]string{"id", "status", "current_period_end"}).
			AddRow("sub-1", "active", time.Now().Add(20*24*time.Hour)))
	mock.ExpectRollback()

	c, w := ginContextForDemoPay(lawyerID, firmID, "lawyer", `{"plan":"solo","billing_cycle":"monthly"}`)
	DemoActivateSubscription(c)

	if w.Code != http.StatusConflict {
		t.Errorf("expected 409 for an already-active subscription, got %d: %s", w.Code, w.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Errorf("unexpected query sequence (no write should have been attempted): %v", err)
	}
}

func TestDemoActivateSubscription_ActivatesWhenNoActivePlan(t *testing.T) {
	lawyerID := "11111111-1111-1111-1111-111111111111"
	firmID := "22222222-2222-2222-2222-222222222222"
	planID := "33333333-3333-3333-3333-333333333333"
	mock := withMockDB(t)

	mock.ExpectQuery(`SELECT id, display_name, price_monthly, price_yearly\s*FROM plans WHERE name = \$1 AND is_active = true`).
		WithArgs("solo").
		WillReturnRows(sqlmock.NewRows([]string{"id", "display_name", "price_monthly", "price_yearly"}).
			AddRow(planID, "Solo", 99.0, 999.0))

	mock.ExpectBegin()
	mock.ExpectQuery(`SELECT id::text, status, current_period_end FROM subscriptions\s*WHERE firm_id = \$1::uuid FOR UPDATE`).
		WithArgs(firmID).
		WillReturnRows(sqlmock.NewRows([]string{"id", "status", "current_period_end"}).
			AddRow("sub-1", "trial_expired", time.Now().Add(-1*time.Hour)))
	mock.ExpectExec(`INSERT INTO payment_orders`).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(`INSERT INTO subscription_payments`).
		WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(`UPDATE subscriptions SET`).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectExec(`UPDATE firms SET plan_id`).
		WillReturnResult(sqlmock.NewResult(0, 1))
	mock.ExpectCommit()

	c, w := ginContextForDemoPay(lawyerID, firmID, "lawyer", `{"plan":"solo","billing_cycle":"monthly"}`)
	DemoActivateSubscription(c)

	if w.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d: %s", w.Code, w.Body.String())
	}
	if !strings.Contains(w.Body.String(), `"payment_mode":"demo"`) {
		t.Errorf("expected the response to be explicitly tagged payment_mode:demo, got: %s", w.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Errorf("unexpected query sequence: %v", err)
	}
}
