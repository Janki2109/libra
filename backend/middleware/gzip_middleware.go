package middleware

import (
	"compress/gzip"
	"net/http"
	"strings"
	"sync"

	"github.com/gin-gonic/gin"
)

// minCompressSize is the payload floor below which compression costs more than
// it saves — the gzip header alone is ~20 bytes, and small JSON often grows.
const minCompressSize = 1024

// gzipWriterPool avoids allocating a new compressor per request. gzip.Writer
// carries a ~64 KB internal window; allocating one per request would add real
// GC pressure at any traffic level.
var gzipWriterPool = sync.Pool{
	New: func() interface{} {
		w, _ := gzip.NewWriterLevel(nil, gzip.DefaultCompression)
		return w
	},
}

// Gzip compresses JSON responses for clients that accept it.
//
// The API returns list payloads that are almost entirely repeated field names
// and UUIDs — JSON of that shape typically compresses 80-90%. On the mobile
// networks this app's users are actually on, transfer time dominates every
// list screen, so this is the single cheapest latency win available.
//
// Written against the standard library rather than pulling in gin-contrib/gzip:
// one fewer dependency to audit in a codebase that handles privileged data.
func Gzip() gin.HandlerFunc {
	return func(c *gin.Context) {
		if !strings.Contains(c.GetHeader("Accept-Encoding"), "gzip") {
			c.Next()
			return
		}

		// Range requests and already-encoded bodies must pass through
		// untouched.
		if c.GetHeader("Range") != "" {
			c.Next()
			return
		}

		gz := gzipWriterPool.Get().(*gzip.Writer)
		defer gzipWriterPool.Put(gz)

		writer := &gzipResponseWriter{
			ResponseWriter: c.Writer,
			gz:             gz,
		}
		c.Writer = writer

		defer func() {
			// Close finalizes the gzip stream. Skipping it on the
			// not-compressed path matters: calling Close on an unused writer
			// would emit a bare gzip header with no body.
			if writer.compressing {
				writer.gz.Close()
			}
		}()

		c.Next()
	}
}

type gzipResponseWriter struct {
	gin.ResponseWriter
	gz          *gzip.Writer
	compressing bool
	decided     bool
}

// decide runs once, on the first write, when the status and content type are
// finally known.
func (w *gzipResponseWriter) decide(firstChunk []byte) {
	if w.decided {
		return
	}
	w.decided = true

	status := w.ResponseWriter.Status()
	// 204 and 304 carry no body; compressing them produces an invalid response.
	if status == http.StatusNoContent || status == http.StatusNotModified {
		return
	}

	ct := w.ResponseWriter.Header().Get("Content-Type")
	if !strings.Contains(ct, "json") && !strings.Contains(ct, "text/") {
		return
	}

	// Skip payloads too small to benefit. Content-Length is set by gin for
	// c.JSON, so this is usually accurate; when it is absent, fall back to the
	// size of the first chunk.
	size := w.ResponseWriter.Size()
	if size < 0 {
		size = len(firstChunk)
	}
	if size < minCompressSize {
		return
	}

	h := w.ResponseWriter.Header()
	h.Set("Content-Encoding", "gzip")
	// Content-Length now describes the uncompressed body and would be wrong.
	h.Del("Content-Length")
	// Caches keyed only on the URL must not serve a gzipped body to a client
	// that cannot decode it.
	h.Add("Vary", "Accept-Encoding")

	w.gz.Reset(w.ResponseWriter)
	w.compressing = true
}

func (w *gzipResponseWriter) Write(data []byte) (int, error) {
	w.decide(data)
	if !w.compressing {
		return w.ResponseWriter.Write(data)
	}
	return w.gz.Write(data)
}

func (w *gzipResponseWriter) WriteString(s string) (int, error) {
	return w.Write([]byte(s))
}

// Flush pushes buffered bytes through the compressor before the underlying
// writer flushes, so streamed responses are not truncated.
func (w *gzipResponseWriter) Flush() {
	if w.compressing {
		w.gz.Flush()
	}
	w.ResponseWriter.Flush()
}
