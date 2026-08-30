package middleware

import (
	"bytes"
	"compress/gzip"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
)

func newGzipRouter(handler gin.HandlerFunc) *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.Use(Gzip())
	r.GET("/test", handler)
	return r
}

func TestGzipCompressesLargeJSON(t *testing.T) {
	payload := gin.H{"items": strings.Repeat("case-record ", 500)}
	r := newGzipRouter(func(c *gin.Context) { c.JSON(http.StatusOK, payload) })

	req := httptest.NewRequest(http.MethodGet, "/test", nil)
	req.Header.Set("Accept-Encoding", "gzip")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if got := w.Header().Get("Content-Encoding"); got != "gzip" {
		t.Fatalf("Content-Encoding = %q, want gzip", got)
	}
	if !strings.Contains(w.Header().Get("Vary"), "Accept-Encoding") {
		t.Error("Vary must include Accept-Encoding or caches will serve gzip to clients that cannot decode it")
	}
	// A stale Content-Length describing the uncompressed body breaks clients.
	if w.Header().Get("Content-Length") != "" {
		t.Error("Content-Length must be dropped once the body is compressed")
	}

	zr, err := gzip.NewReader(bytes.NewReader(w.Body.Bytes()))
	if err != nil {
		t.Fatalf("response is not valid gzip: %v", err)
	}
	body, err := io.ReadAll(zr)
	if err != nil {
		t.Fatalf("reading gzip body: %v", err)
	}

	var decoded map[string]interface{}
	if err := json.Unmarshal(body, &decoded); err != nil {
		t.Fatalf("decompressed body is not the original JSON: %v", err)
	}
	if w.Body.Len() >= len(body) {
		t.Errorf("compressed %d bytes >= original %d; compression achieved nothing",
			w.Body.Len(), len(body))
	}
}

func TestGzipSkippedWithoutAcceptEncoding(t *testing.T) {
	payload := gin.H{"items": strings.Repeat("case-record ", 500)}
	r := newGzipRouter(func(c *gin.Context) { c.JSON(http.StatusOK, payload) })

	// No Accept-Encoding: the client cannot decode gzip.
	req := httptest.NewRequest(http.MethodGet, "/test", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Header().Get("Content-Encoding") == "gzip" {
		t.Fatal("compressed a response for a client that did not ask for gzip")
	}
	var decoded map[string]interface{}
	if err := json.Unmarshal(w.Body.Bytes(), &decoded); err != nil {
		t.Fatalf("plain body is not valid JSON: %v", err)
	}
}

func TestGzipSkipsSmallPayloads(t *testing.T) {
	r := newGzipRouter(func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"ok": true})
	})

	req := httptest.NewRequest(http.MethodGet, "/test", nil)
	req.Header.Set("Accept-Encoding", "gzip")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	// Compressing a 13-byte body makes it larger.
	if w.Header().Get("Content-Encoding") == "gzip" {
		t.Error("compressed a payload below the size floor")
	}
	if w.Body.String() != `{"ok":true}` {
		t.Errorf("body = %q, want the plain JSON", w.Body.String())
	}
}

func TestGzipLeavesEmptyResponsesAlone(t *testing.T) {
	r := newGzipRouter(func(c *gin.Context) { c.Status(http.StatusNoContent) })

	req := httptest.NewRequest(http.MethodGet, "/test", nil)
	req.Header.Set("Accept-Encoding", "gzip")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Header().Get("Content-Encoding") == "gzip" {
		t.Error("204 carries no body; emitting a gzip header makes the response invalid")
	}
	if w.Body.Len() != 0 {
		t.Errorf("204 body = %q, want empty", w.Body.String())
	}
}
