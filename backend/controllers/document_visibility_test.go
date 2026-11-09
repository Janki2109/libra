package controllers

// Automated coverage for the "Visible to Client" document toggle, per the
// explicit requirement that the toggle be enforced by backend authorization
// and not just a Flutter switch. sqlmock asserts exactly what SQL/args each
// path sends, which is the right tool for "does the handler actually block
// this", not "does a real row come back".

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/gin-gonic/gin"
)

func ginContextWithFirmUser(userID, firmID, role string, body string) (*gin.Context, *httptest.ResponseRecorder) {
	gin.SetMode(gin.TestMode)
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest(http.MethodPut, "/", strings.NewReader(body))
	c.Request.Header.Set("Content-Type", "application/json")
	c.Set("user_id", userID)
	c.Set("firm_id", firmID)
	c.Set("role", role)
	return c, w
}

// A lawyer's own upload can be freely toggled either way.
func TestSetDocumentVisibility_LawyerDocument_CanToggleEitherWay(t *testing.T) {
	docID := "11111111-1111-1111-1111-111111111111"
	firmID := "22222222-2222-2222-2222-222222222222"
	mock := withMockDB(t)

	// requireFirmResource's lookup.
	mock.ExpectQuery(`SELECT firm_id::text FROM documents WHERE id = \$1::uuid AND firm_id = \$2::uuid`).
		WithArgs(docID, firmID).
		WillReturnRows(sqlmock.NewRows([]string{"firm_id"}).AddRow(firmID))
	// uploaded_by_role lookup.
	mock.ExpectQuery(`SELECT COALESCE\(uploaded_by_role,''\) FROM documents WHERE id=\$1::uuid AND firm_id=\$2::uuid`).
		WithArgs(docID, firmID).
		WillReturnRows(sqlmock.NewRows([]string{"uploaded_by_role"}).AddRow("lawyer"))
	mock.ExpectExec(`UPDATE documents SET visible_to_client=\$1, updated_at=NOW\(\) WHERE id=\$2::uuid AND firm_id=\$3::uuid`).
		WithArgs(true, docID, firmID).
		WillReturnResult(sqlmock.NewResult(0, 1))

	c, w := ginContextWithFirmUser("u1", firmID, "lawyer", `{"visible_to_client":true}`)
	c.Params = gin.Params{{Key: "id", Value: docID}}
	SetDocumentVisibility(c)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Errorf("unexpected query sequence: %v", err)
	}
}

// A client's own upload must never be turned OFF by the lawyer's toggle —
// the client must always keep access to what they themselves submitted.
func TestSetDocumentVisibility_ClientUpload_CannotBeHidden(t *testing.T) {
	docID := "11111111-1111-1111-1111-111111111111"
	firmID := "22222222-2222-2222-2222-222222222222"
	mock := withMockDB(t)

	mock.ExpectQuery(`SELECT firm_id::text FROM documents WHERE id = \$1::uuid AND firm_id = \$2::uuid`).
		WithArgs(docID, firmID).
		WillReturnRows(sqlmock.NewRows([]string{"firm_id"}).AddRow(firmID))
	mock.ExpectQuery(`SELECT COALESCE\(uploaded_by_role,''\) FROM documents WHERE id=\$1::uuid AND firm_id=\$2::uuid`).
		WithArgs(docID, firmID).
		WillReturnRows(sqlmock.NewRows([]string{"uploaded_by_role"}).AddRow("client"))
	// No UPDATE expectation registered at all -- if the handler tried to run
	// one anyway, ExpectationsWereMet would catch the unexpected query.

	c, w := ginContextWithFirmUser("u1", firmID, "lawyer", `{"visible_to_client":false}`)
	c.Params = gin.Params{{Key: "id", Value: docID}}
	SetDocumentVisibility(c)

	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400 rejecting the toggle, got %d: %s", w.Code, w.Body.String())
	}
}

// The mirror case: setting a client-uploaded document to visible=true (a
// no-op in practice, since it's already forced true at insert) is allowed,
// never blocked.
func TestSetDocumentVisibility_ClientUpload_CanStayVisible(t *testing.T) {
	docID := "11111111-1111-1111-1111-111111111111"
	firmID := "22222222-2222-2222-2222-222222222222"
	mock := withMockDB(t)

	mock.ExpectQuery(`SELECT firm_id::text FROM documents WHERE id = \$1::uuid AND firm_id = \$2::uuid`).
		WithArgs(docID, firmID).
		WillReturnRows(sqlmock.NewRows([]string{"firm_id"}).AddRow(firmID))
	mock.ExpectQuery(`SELECT COALESCE\(uploaded_by_role,''\) FROM documents WHERE id=\$1::uuid AND firm_id=\$2::uuid`).
		WithArgs(docID, firmID).
		WillReturnRows(sqlmock.NewRows([]string{"uploaded_by_role"}).AddRow("client"))
	mock.ExpectExec(`UPDATE documents SET visible_to_client=\$1, updated_at=NOW\(\) WHERE id=\$2::uuid AND firm_id=\$3::uuid`).
		WithArgs(true, docID, firmID).
		WillReturnResult(sqlmock.NewResult(0, 1))

	c, w := ginContextWithFirmUser("u1", firmID, "lawyer", `{"visible_to_client":true}`)
	c.Params = gin.Params{{Key: "id", Value: docID}}
	SetDocumentVisibility(c)

	if w.Code != http.StatusOK {
		t.Errorf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Errorf("unexpected query sequence: %v", err)
	}
}
