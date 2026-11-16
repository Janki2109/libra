package controllers

// GetChatRooms previously carried no presence of its own -- the Messages
// List's green dot was a hardcoded literal color on every row, which is
// why it could show "online" for someone GetRoomPresence (the Individual
// Chat header) correctly showed as offline. This asserts GetChatRooms now
// derives `online` from the same last_active_at/onlineWindow computation,
// for a fresh vs. a stale/absent last_active_at.

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/gin-gonic/gin"
)

func ginContextForChatRooms(userID, firmID, role string) (*gin.Context, *httptest.ResponseRecorder) {
	gin.SetMode(gin.TestMode)
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest(http.MethodGet, "/chat/rooms", nil)
	c.Set("user_id", userID)
	c.Set("firm_id", firmID)
	c.Set("role", role)
	return c, w
}

func TestGetChatRooms_ClientSide_ReflectsFreshLastActiveAsOnline(t *testing.T) {
	clientUserID := "11111111-1111-1111-1111-111111111111"
	roomID := "22222222-2222-2222-2222-222222222222"
	mock := withMockDB(t)

	mock.ExpectQuery(`FROM chat_rooms cr\s*LEFT JOIN users u ON cr.lawyer_id = u.id`).
		WithArgs(clientUserID).
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "lawyer_name", "last_message", "last_message_at", "other_name",
			"created_at", "unread_count", "last_active_at",
		}).AddRow(roomID, "Lawyer A", "Hi", "2026-01-01T10:00:00Z", "Lawyer A",
			time.Now(), 0, time.Now().Add(-10*time.Second)))

	c, w := ginContextForChatRooms(clientUserID, "", "client")
	GetChatRooms(c)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	if !strings.Contains(w.Body.String(), `"online":true`) {
		t.Errorf("expected online:true for a 10s-old last_active_at, got: %s", w.Body.String())
	}
}

func TestGetChatRooms_ClientSide_ReflectsStaleLastActiveAsOffline(t *testing.T) {
	clientUserID := "11111111-1111-1111-1111-111111111111"
	roomID := "22222222-2222-2222-2222-222222222222"
	mock := withMockDB(t)

	mock.ExpectQuery(`FROM chat_rooms cr\s*LEFT JOIN users u ON cr.lawyer_id = u.id`).
		WithArgs(clientUserID).
		WillReturnRows(sqlmock.NewRows([]string{
			"id", "lawyer_name", "last_message", "last_message_at", "other_name",
			"created_at", "unread_count", "last_active_at",
		}).AddRow(roomID, "Lawyer A", "Hi", "2026-01-01T10:00:00Z", "Lawyer A",
			time.Now(), 0, time.Now().Add(-10*time.Minute)))

	c, w := ginContextForChatRooms(clientUserID, "", "client")
	GetChatRooms(c)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	if !strings.Contains(w.Body.String(), `"online":false`) {
		t.Errorf("expected online:false for a 10m-old last_active_at, got: %s", w.Body.String())
	}
}
