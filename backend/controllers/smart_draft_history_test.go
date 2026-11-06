package controllers

// Cross-lawyer isolation tests for Smart Draft History, same sqlmock
// approach as notification_isolation_test.go: no live test database is
// available in this environment, so these assert the handler's SQL is
// actually scoped to the authenticated caller's own user_id rather than
// relying on a real database to happen to reject the wrong query.

import (
	"database/sql"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/gin-gonic/gin"
)

func smartDraftTestContext(method, path, userID, paramID string, body *httptest.ResponseRecorder) *gin.Context {
	gin.SetMode(gin.TestMode)
	c, _ := gin.CreateTestContext(body)
	c.Request = httptest.NewRequest(method, path, nil)
	c.Set("user_id", userID)
	if paramID != "" {
		c.Params = gin.Params{{Key: "id", Value: paramID}}
	}
	return c
}

// Lawyer B must never be able to fetch a history item that belongs to
// Lawyer A, even with the correct item id -- the ownership check is
// user_id=$2, and the mock only has an expectation for Lawyer A's id, so
// a handler that dropped that predicate (or used the wrong variable) would
// fail this test by either matching unexpectedly or erroring differently.
func TestGetSmartDraftHistoryItem_RejectsAnotherLawyersItem(t *testing.T) {
	itemID := "44444444-4444-4444-4444-444444444444"
	lawyerBID := "22222222-2222-2222-2222-222222222222"
	mock := withMockDB(t)

	// Lawyer B's own id is a valid, well-formed query, but the WHERE
	// id=$1 AND user_id=$2 predicate against the real table would match
	// zero rows for an item that belongs to Lawyer A -- sqlmock models
	// that directly by returning ErrNoRows.
	mock.ExpectQuery(`FROM smart_draft_history h\s*LEFT JOIN cases ca ON h\.case_id = ca\.id\s*WHERE h\.id = \$1::uuid AND h\.user_id = \$2::uuid`).
		WithArgs(itemID, lawyerBID).
		WillReturnError(sql.ErrNoRows)

	w := httptest.NewRecorder()
	c := smartDraftTestContext(http.MethodGet, "/ai/history/"+itemID, lawyerBID, itemID, w)
	GetSmartDraftHistoryItem(c)

	if w.Code != http.StatusNotFound {
		t.Errorf("expected 404 for another lawyer's history item, got %d: %s", w.Code, w.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Errorf("query did not scope by both id and the authenticated user's own id: %v", err)
	}
}

// The matching success case: the owner fetching their own item.
func TestGetSmartDraftHistoryItem_SucceedsForOwner(t *testing.T) {
	itemID := "44444444-4444-4444-4444-444444444444"
	lawyerAID := "11111111-1111-1111-1111-111111111111"
	mock := withMockDB(t)

	rows := sqlmock.NewRows([]string{
		"id", "thread_id", "version", "activity_type", "title", "case_id", "case_title",
		"input_text", "output_text", "file_name", "mime_type", "file_content",
		"status", "created_at", "updated_at",
	}).AddRow(itemID, "thread-1", 1, "draft", "Notice to Vacate", "", "",
		"draft a notice", "Dear Sir/Madam...", "", "", "",
		"completed", "2026-01-01", "2026-01-01")

	mock.ExpectQuery(`FROM smart_draft_history h\s*LEFT JOIN cases ca ON h\.case_id = ca\.id\s*WHERE h\.id = \$1::uuid AND h\.user_id = \$2::uuid`).
		WithArgs(itemID, lawyerAID).
		WillReturnRows(rows)

	w := httptest.NewRecorder()
	c := smartDraftTestContext(http.MethodGet, "/ai/history/"+itemID, lawyerAID, itemID, w)
	GetSmartDraftHistoryItem(c)

	if w.Code != http.StatusOK {
		t.Errorf("expected 200 for the actual owner, got %d: %s", w.Code, w.Body.String())
	}
}

// DeleteSmartDraftHistory must not delete (or even look up) a thread_id
// belonging to another lawyer's item -- it first resolves thread_id scoped
// to id+user_id, so a non-owner's request never reaches the DELETE at all.
func TestDeleteSmartDraftHistory_RejectsAnotherLawyersItem(t *testing.T) {
	itemID := "44444444-4444-4444-4444-444444444444"
	lawyerBID := "22222222-2222-2222-2222-222222222222"
	mock := withMockDB(t)

	mock.ExpectQuery(`SELECT thread_id::text FROM smart_draft_history WHERE id=\$1::uuid AND user_id=\$2::uuid`).
		WithArgs(itemID, lawyerBID).
		WillReturnError(sql.ErrNoRows)

	w := httptest.NewRecorder()
	c := smartDraftTestContext(http.MethodDelete, "/ai/history/"+itemID, lawyerBID, itemID, w)
	DeleteSmartDraftHistory(c)

	if w.Code != http.StatusNotFound {
		t.Errorf("expected 404, got %d: %s", w.Code, w.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Errorf("delete path did not verify ownership before any delete could run: %v", err)
	}
}

// UpdateSmartDraftHistory ("continue editing") must likewise refuse to
// create a new version under a thread it doesn't own.
func TestUpdateSmartDraftHistory_RejectsAnotherLawyersItem(t *testing.T) {
	itemID := "44444444-4444-4444-4444-444444444444"
	lawyerBID := "22222222-2222-2222-2222-222222222222"
	mock := withMockDB(t)

	mock.ExpectQuery(`SELECT thread_id::text, version, activity_type, title, COALESCE\(case_id::text,''\),\s*` +
		`input_text, file_name, file_content, mime_type, firm_id::text\s*` +
		`FROM smart_draft_history WHERE id=\$1::uuid AND user_id=\$2::uuid`).
		WithArgs(itemID, lawyerBID).
		WillReturnError(sql.ErrNoRows)

	gin.SetMode(gin.TestMode)
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest(http.MethodPut, "/ai/history/"+itemID,
		strings.NewReader(`{"output_text":"updated content"}`))
	c.Request.Header.Set("Content-Type", "application/json")
	c.Params = gin.Params{{Key: "id", Value: itemID}}
	c.Set("user_id", lawyerBID)

	UpdateSmartDraftHistory(c)

	if w.Code != http.StatusNotFound {
		t.Errorf("expected 404, got %d: %s", w.Code, w.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Errorf("update ('continue editing') did not verify ownership first: %v", err)
	}
}
