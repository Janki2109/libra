package controllers

// VerifyCertificate is deliberately public (unauthenticated) -- anyone
// holding a certificate number must be able to check it -- so it must
// never leak more than what the certificate itself already shows, and an
// unknown number must come back as simply invalid, not an error that
// reveals anything about the lookup.

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/gin-gonic/gin"
)

func TestVerifyCertificate_KnownNumberReturnsValid(t *testing.T) {
	mock := withMockDB(t)
	mock.ExpectQuery(`SELECT certificate_number, student_name, course_name, issued_at::text, status\s*FROM student_certificates WHERE certificate_number=\$1`).
		WithArgs("OL-2026-000001").
		WillReturnRows(sqlmock.NewRows([]string{
			"certificate_number", "student_name", "course_name", "issued_at", "status",
		}).AddRow("OL-2026-000001", "Student A", "Constitutional Law Expert", "2026-01-01T00:00:00Z", "valid"))

	gin.SetMode(gin.TestMode)
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest(http.MethodGet, "/certificates/verify/OL-2026-000001", nil)
	c.Params = gin.Params{{Key: "number", Value: "OL-2026-000001"}}

	VerifyCertificate(c)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	if !strings.Contains(w.Body.String(), `"valid":true`) {
		t.Errorf("expected valid:true for a known certificate, got: %s", w.Body.String())
	}
}

func TestVerifyCertificate_UnknownNumberReturnsInvalid(t *testing.T) {
	mock := withMockDB(t)
	mock.ExpectQuery(`FROM student_certificates WHERE certificate_number=\$1`).
		WithArgs("OL-2026-999999").
		WillReturnError(sqlmock.ErrCancelled)

	gin.SetMode(gin.TestMode)
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest(http.MethodGet, "/certificates/verify/OL-2026-999999", nil)
	c.Params = gin.Params{{Key: "number", Value: "OL-2026-999999"}}

	VerifyCertificate(c)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200 (not an error status) for an unknown number, got %d: %s", w.Code, w.Body.String())
	}
	if !strings.Contains(w.Body.String(), `"valid":false`) {
		t.Errorf("expected valid:false for an unknown certificate, got: %s", w.Body.String())
	}
}
