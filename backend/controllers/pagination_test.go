package controllers

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

func ctxWithQuery(q string) *gin.Context {
	gin.SetMode(gin.TestMode)
	c, _ := gin.CreateTestContext(httptest.NewRecorder())
	c.Request = httptest.NewRequest(http.MethodGet, "/x?"+q, nil)
	return c
}

func TestParsePaginationDefaults(t *testing.T) {
	p := ParsePagination(ctxWithQuery(""))
	if p.Limit != defaultPageSize {
		t.Errorf("Limit = %d, want %d", p.Limit, defaultPageSize)
	}
	if p.Offset != 0 || p.Page != 1 {
		t.Errorf("Offset/Page = %d/%d, want 0/1", p.Offset, p.Page)
	}
}

func TestParsePaginationOffset(t *testing.T) {
	p := ParsePagination(ctxWithQuery("page=3&limit=10"))
	if p.Limit != 10 {
		t.Errorf("Limit = %d, want 10", p.Limit)
	}
	if p.Offset != 20 {
		t.Errorf("Offset = %d, want 20 (page 3 of 10)", p.Offset)
	}
}

func TestParsePaginationClampsLimit(t *testing.T) {
	// Without a ceiling, ?limit=1000000 restores the unbounded behaviour this
	// was added to remove.
	p := ParsePagination(ctxWithQuery("limit=1000000"))
	if p.Limit != maxPageSize {
		t.Errorf("Limit = %d, want it clamped to %d", p.Limit, maxPageSize)
	}
}

func TestParsePaginationRejectsNonsense(t *testing.T) {
	// Negative or unparseable values must not produce a negative OFFSET, which
	// Postgres rejects with a runtime error.
	for _, q := range []string{"page=0", "page=-5", "page=abc", "limit=0", "limit=-1", "limit=x"} {
		p := ParsePagination(ctxWithQuery(q))
		if p.Limit <= 0 {
			t.Errorf("%s produced Limit=%d", q, p.Limit)
		}
		if p.Offset < 0 {
			t.Errorf("%s produced Offset=%d", q, p.Offset)
		}
		if p.Page < 1 {
			t.Errorf("%s produced Page=%d", q, p.Page)
		}
	}
}

func TestPaginationMetaHasMore(t *testing.T) {
	p := ParsePagination(ctxWithQuery("limit=25"))

	// A full page means there is probably another one.
	if got := p.Meta(25)["has_more"]; got != true {
		t.Errorf("has_more = %v for a full page, want true", got)
	}
	// A short page is the last one.
	if got := p.Meta(7)["has_more"]; got != false {
		t.Errorf("has_more = %v for a partial page, want false", got)
	}
	if got := p.Meta(0)["has_more"]; got != false {
		t.Errorf("has_more = %v for an empty page, want false", got)
	}
}
