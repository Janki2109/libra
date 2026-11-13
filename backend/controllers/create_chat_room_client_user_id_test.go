package controllers

// CreateChatRoom's client_user_id path (added so a Lawyer's "Start Chat" on
// a booked consultation actually connects to a real chat_rooms row instead
// of opening the generic chat list with nothing created) must still gate on
// an actual paid consultation between that lawyer and that user -- never
// just trust the id to open a room with an arbitrary account.

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/gin-gonic/gin"
)

func ginContextForCreateChatRoom(userID, firmID, role, body string) (*gin.Context, *httptest.ResponseRecorder) {
	gin.SetMode(gin.TestMode)
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest(http.MethodPost, "/chat/rooms", strings.NewReader(body))
	c.Request.Header.Set("Content-Type", "application/json")
	c.Set("user_id", userID)
	c.Set("firm_id", firmID)
	c.Set("role", role)
	return c, w
}

func TestCreateChatRoom_ClientUserID_RejectsWithoutPaidConsultation(t *testing.T) {
	lawyerID := "11111111-1111-1111-1111-111111111111"
	firmID := "22222222-2222-2222-2222-222222222222"
	clientUserID := "33333333-3333-3333-3333-333333333333"
	mock := withMockDB(t)

	mock.ExpectQuery(`SELECT EXISTS\(\s*SELECT 1 FROM consultations\s*WHERE client_id=\$1::uuid AND lawyer_id=\$2::uuid AND payment_status='paid'\s*\)`).
		WithArgs(clientUserID, lawyerID).
		WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(false))

	c, w := ginContextForCreateChatRoom(lawyerID, firmID, "lawyer",
		`{"client_user_id":"`+clientUserID+`"}`)
	CreateChatRoom(c)

	if w.Code != http.StatusForbidden {
		t.Errorf("expected 403 with no paid consultation, got %d: %s", w.Code, w.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Errorf("unexpected query sequence: %v", err)
	}
}

func TestCreateChatRoom_ClientUserID_ReusesExistingRoom(t *testing.T) {
	lawyerID := "11111111-1111-1111-1111-111111111111"
	firmID := "22222222-2222-2222-2222-222222222222"
	clientUserID := "33333333-3333-3333-3333-333333333333"
	clientRowID := "44444444-4444-4444-4444-444444444444"
	roomID := "55555555-5555-5555-5555-555555555555"
	mock := withMockDB(t)

	mock.ExpectQuery(`SELECT EXISTS\(\s*SELECT 1 FROM consultations`).
		WithArgs(clientUserID, lawyerID).
		WillReturnRows(sqlmock.NewRows([]string{"exists"}).AddRow(true))
	mock.ExpectQuery(`SELECT name, email, COALESCE\(phone,''\) FROM users WHERE id=\$1::uuid`).
		WithArgs(clientUserID).
		WillReturnRows(sqlmock.NewRows([]string{"name", "email", "phone"}).
			AddRow("Client A", "clienta@example.com", "9999999999"))
	mock.ExpectQuery(`SELECT id FROM clients WHERE firm_id=\$1::uuid AND lower\(email\)=lower\(\$2\) LIMIT 1`).
		WithArgs(firmID, "clienta@example.com").
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(clientRowID))
	// req.CaseID is empty, so belongsToFirm returns true without querying.
	mock.ExpectQuery(`SELECT id FROM chat_rooms\s*WHERE lawyer_id=\$1::uuid AND client_id=\$2::uuid AND is_active=true LIMIT 1`).
		WithArgs(lawyerID, clientRowID).
		WillReturnRows(sqlmock.NewRows([]string{"id"}).AddRow(roomID))

	c, w := ginContextForCreateChatRoom(lawyerID, firmID, "lawyer",
		`{"client_user_id":"`+clientUserID+`"}`)
	CreateChatRoom(c)

	if w.Code != http.StatusOK {
		t.Errorf("expected 200 reusing the existing room, got %d: %s", w.Code, w.Body.String())
	}
	if !strings.Contains(w.Body.String(), roomID) {
		t.Errorf("expected response to contain the existing room id, got: %s", w.Body.String())
	}
}
