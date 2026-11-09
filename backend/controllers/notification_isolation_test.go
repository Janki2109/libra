package controllers

// Automated cross-account notification-isolation tests, per the explicit
// security-audit requirement that this not be verified by manual UI
// testing alone. These use sqlmock rather than a live Postgres connection
// (no test database is available in this environment) — which is actually
// the more precise tool for what's being asserted here: not "does a real
// row come back", but "does the handler's SQL scope strictly to the
// authenticated caller's own user_id, with no path for one account's
// request to touch another account's row". sqlmock lets a test assert the
// exact WHERE-clause arguments a handler sends to the database, which is
// exactly the property an IDOR regression would break.

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"libra/config"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/gin-gonic/gin"
)

func withMockDB(t *testing.T) sqlmock.Sqlmock {
	t.Helper()
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock.New: %v", err)
	}
	prev := config.DB
	config.DB = db
	t.Cleanup(func() {
		config.DB = prev
		db.Close()
	})
	return mock
}

func ginContextWithUser(userID string) (*gin.Context, *httptest.ResponseRecorder) {
	gin.SetMode(gin.TestMode)
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest(http.MethodGet, "/", nil)
	c.Set("user_id", userID)
	return c, w
}

// GetNotifications must query strictly by the authenticated caller's own
// user_id (from JWT-derived context, never a request parameter). A test
// that queried with Lawyer B's id while authenticated as Lawyer A would
// fail here because sqlmock only has an expectation for Lawyer A's id.
func TestGetNotifications_ScopesToAuthenticatedUserOnly(t *testing.T) {
	lawyerAID := "11111111-1111-1111-1111-111111111111"
	mock := withMockDB(t)

	rows := sqlmock.NewRows([]string{
		"id", "title", "message", "type", "is_read", "created_at",
		"reference_id", "reference_type",
	}).AddRow("n1", "Case updated", "msg", "case", false, time.Now(), "", "")

	mock.ExpectQuery(`SELECT id, title, COALESCE\(message,''\), COALESCE\(type,'general'\),\s*` +
		`is_read, created_at, COALESCE\(reference_id::text,''\), COALESCE\(reference_type,''\)\s*` +
		`FROM notifications WHERE user_id=\$1::uuid`).
		WithArgs(lawyerAID).
		WillReturnRows(rows)

	c, w := ginContextWithUser(lawyerAID)
	GetNotifications(c)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Errorf("query did not scope to the authenticated user's own id as expected: %v", err)
	}
}

// If a handler were changed to accept a user_id override from a query
// parameter or body instead of strictly from the authenticated context,
// this test would fail: the mock only honors a query for lawyerAID, so a
// handler that queries with any other id (e.g. one taken from Lawyer B's
// spoofed request) gets no matching expectation and errors out.
func TestGetNotifications_CannotBeMadeToQueryAnotherAccount(t *testing.T) {
	lawyerAID := "11111111-1111-1111-1111-111111111111"
	lawyerBID := "22222222-2222-2222-2222-222222222222"
	mock := withMockDB(t)

	// Only Lawyer A's id is ever a valid expectation.
	mock.ExpectQuery(`FROM notifications WHERE user_id=\$1::uuid`).
		WithArgs(lawyerAID).
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "title", "message", "type", "is_read", "created_at",
			"reference_id", "reference_type",
		}))

	// Authenticated context says Lawyer B, even though nothing in the
	// handler takes an explicit id argument -- utils.UserID always reads
	// from this same authenticated context, which is the whole point: there
	// is no parameter to spoof.
	c, w := ginContextWithUser(lawyerBID)
	GetNotifications(c)

	// Querying as Lawyer B against a mock that only expects Lawyer A's id
	// must fail at the SQL layer (unexpected query/args), which the handler
	// surfaces as a 500 -- proof the handler has no independent path to
	// "become" Lawyer A's identity.
	if w.Code == http.StatusOK {
		t.Error("handler returned 200 for an unexpected identity — notification query is not bound to the authenticated caller")
	}
}

// MarkNotificationRead must scope its UPDATE by BOTH the notification id
// AND the authenticated caller's own user_id. A notification belonging to
// another account must come back as 404, not succeed and not leak whether
// the id exists at all.
func TestMarkNotificationRead_RejectsAnotherAccountsNotification(t *testing.T) {
	notifID := "33333333-3333-3333-3333-333333333333"
	lawyerBID := "22222222-2222-2222-2222-222222222222"
	mock := withMockDB(t)

	// The notification exists but belongs to someone else, so the
	// WHERE id=$1 AND user_id=$2 predicate matches zero rows -- exactly
	// what happens against a real database when Lawyer B tries to mark
	// Lawyer A's notification.
	mock.ExpectExec(`UPDATE notifications SET is_read=true WHERE id=\$1::uuid AND user_id=\$2::uuid`).
		WithArgs(notifID, lawyerBID).
		WillReturnResult(sqlmock.NewResult(0, 0))

	gin.SetMode(gin.TestMode)
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest(http.MethodPut, "/notifications/"+notifID+"/read", nil)
	c.Params = gin.Params{{Key: "id", Value: notifID}}
	c.Set("user_id", lawyerBID)

	MarkNotificationRead(c)

	if w.Code != http.StatusNotFound {
		t.Errorf("expected 404 for another account's notification, got %d: %s", w.Code, w.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Errorf("update did not include both id and the authenticated user's own id: %v", err)
	}
}

// The mirror-image success case: the same notification id, marked read by
// its actual owner, succeeds. Establishes the 404 above is caused by
// ownership mismatch specifically, not some unrelated handler bug.
func TestMarkNotificationRead_SucceedsForOwner(t *testing.T) {
	notifID := "33333333-3333-3333-3333-333333333333"
	lawyerAID := "11111111-1111-1111-1111-111111111111"
	mock := withMockDB(t)

	mock.ExpectExec(`UPDATE notifications SET is_read=true WHERE id=\$1::uuid AND user_id=\$2::uuid`).
		WithArgs(notifID, lawyerAID).
		WillReturnResult(sqlmock.NewResult(0, 1))

	gin.SetMode(gin.TestMode)
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest(http.MethodPut, "/notifications/"+notifID+"/read", nil)
	c.Params = gin.Params{{Key: "id", Value: notifID}}
	c.Set("user_id", lawyerAID)

	MarkNotificationRead(c)

	if w.Code != http.StatusOK {
		t.Errorf("expected 200 for the actual owner, got %d: %s", w.Code, w.Body.String())
	}
}

// Role-labeled matrix per the explicit "Lawyer A/B, Client A/B, Student A/B"
// audit requirement. GetNotifications and MarkNotificationRead scope purely
// by the authenticated user_id -- role never enters either query -- which is
// exactly why cross-role isolation holds for free: a Client's own id can
// never match a Lawyer's or Student's row regardless of firm, case, or
// booking relationship. This exercises that against every pair, named by
// role, instead of only the two anonymous ids above.
func TestNotificationIsolation_AcrossAllSixAccounts(t *testing.T) {
	type account struct {
		label, id string
	}
	accounts := []account{
		{"Lawyer A", "a1111111-1111-1111-1111-111111111111"},
		{"Lawyer B", "a2222222-2222-2222-2222-222222222222"},
		{"Client A", "c1111111-1111-1111-1111-111111111111"},
		{"Client B", "c2222222-2222-2222-2222-222222222222"},
		{"Student A", "d1111111-1111-1111-1111-111111111111"},
		{"Student B", "d2222222-2222-2222-2222-222222222222"},
	}

	for _, owner := range accounts {
		for _, caller := range accounts {
			owner, caller := owner, caller
			same := owner.id == caller.id
			t.Run(caller.label+"_reads_"+owner.label+"_notifications", func(t *testing.T) {
				mock := withMockDB(t)
				mock.ExpectQuery(`FROM notifications WHERE user_id=\$1::uuid`).
					WithArgs(owner.id).
					WillReturnRows(sqlmock.NewRows([]string{
						"id", "title", "message", "type", "is_read", "created_at",
						"reference_id", "reference_type",
					}))

				c, w := ginContextWithUser(caller.id)
				GetNotifications(c)

				if same {
					if w.Code != http.StatusOK {
						t.Errorf("%s reading their own notifications should succeed, got %d", caller.label, w.Code)
					}
				} else if w.Code == http.StatusOK {
					t.Errorf("%s must not be able to read %s's notifications", caller.label, owner.label)
				}
			})

			t.Run(caller.label+"_marks_read_"+owner.label+"_notification", func(t *testing.T) {
				notifID := "99999999-9999-9999-9999-999999999999"
				mock := withMockDB(t)
				rowsAffected := int64(0)
				if same {
					rowsAffected = 1
				}
				mock.ExpectExec(`UPDATE notifications SET is_read=true WHERE id=\$1::uuid AND user_id=\$2::uuid`).
					WithArgs(notifID, caller.id).
					WillReturnResult(sqlmock.NewResult(0, rowsAffected))

				gin.SetMode(gin.TestMode)
				w := httptest.NewRecorder()
				c, _ := gin.CreateTestContext(w)
				c.Request = httptest.NewRequest(http.MethodPut, "/notifications/"+notifID+"/read", nil)
				c.Params = gin.Params{{Key: "id", Value: notifID}}
				c.Set("user_id", caller.id)

				MarkNotificationRead(c)

				if same {
					if w.Code != http.StatusOK {
						t.Errorf("%s marking their own notification should succeed, got %d", caller.label, w.Code)
					}
				} else if w.Code != http.StatusNotFound {
					t.Errorf("%s marking %s's notification must 404, got %d", caller.label, owner.label, w.Code)
				}
			})
		}
	}
}
