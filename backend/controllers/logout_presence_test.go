package controllers

// Logout previously never touched last_active_at, so a user who signed out
// still showed as "Online" to anyone chatting with them for up to the full
// presence timeout. This asserts Logout actually clears it for the
// authenticated caller, identified from a real signed token (not a request
// field), and leaves other accounts untouched.

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"libra/utils"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/gin-gonic/gin"
)

func TestLogout_ClearsLastActiveForAuthenticatedUser(t *testing.T) {
	userID := "11111111-1111-1111-1111-111111111111"
	token, err := utils.GenerateToken(userID, "lawyer@example.com", "lawyer", "")
	if err != nil {
		t.Fatalf("GenerateToken: %v", err)
	}

	mock := withMockDB(t)
	mock.ExpectExec(`UPDATE users SET last_active_at = NULL WHERE id = \$1::uuid`).
		WithArgs(userID).
		WillReturnResult(sqlmock.NewResult(0, 1))

	gin.SetMode(gin.TestMode)
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest(http.MethodPost, "/auth/logout", nil)
	c.Request.Header.Set("Authorization", "Bearer "+token)

	Logout(c)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Errorf("Logout did not clear last_active_at for the token's own user_id: %v", err)
	}
}

// A missing/invalid token must never fail the logout request itself -- the
// client-side logout proceeds regardless, this is best-effort cleanup only.
func TestLogout_NoTokenStillSucceeds(t *testing.T) {
	withMockDB(t) // no expectations set -- any DB call here would fail the test

	gin.SetMode(gin.TestMode)
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest(http.MethodPost, "/auth/logout", nil)

	Logout(c)

	if w.Code != http.StatusOK {
		t.Errorf("expected 200 even with no token, got %d: %s", w.Code, w.Body.String())
	}
}
