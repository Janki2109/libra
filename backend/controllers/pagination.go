package controllers

import (
	"strconv"

	"github.com/gin-gonic/gin"
)

// Pagination bounds a list response.
//
// Every list endpoint previously returned the firm's entire table — all cases,
// all clients, all hearings, all invoices, ordered and unbounded. For a firm
// with a few dozen matters that is invisible; for one with several thousand it
// means the API serializes megabytes of JSON, the device parses all of it, and
// the list screen blocks on a single request that grows forever as the firm
// succeeds. Growth made the app slower.
type Pagination struct {
	Limit  int
	Offset int
	Page   int
}

const (
	defaultPageSize = 25 // matches AppConstants.pageSize territory in the app
	maxPageSize     = 100
)

// ParsePagination reads ?page= and ?limit= (or ?per_page=) from the request.
// Both are clamped: a caller cannot ask for the whole table by sending
// limit=1000000.
func ParsePagination(c *gin.Context) Pagination {
	limit := defaultPageSize
	raw := c.Query("limit")
	if raw == "" {
		raw = c.Query("per_page")
	}
	if raw != "" {
		if n, err := strconv.Atoi(raw); err == nil && n > 0 {
			limit = n
		}
	}
	if limit > maxPageSize {
		limit = maxPageSize
	}

	page := 1
	if raw := c.Query("page"); raw != "" {
		if n, err := strconv.Atoi(raw); err == nil && n > 0 {
			page = n
		}
	}

	return Pagination{
		Limit:  limit,
		Offset: (page - 1) * limit,
		Page:   page,
	}
}

// Meta describes the page for the client, so a list screen knows whether to
// keep scrolling without guessing from the row count.
func (p Pagination) Meta(returned int) gin.H {
	return gin.H{
		"page":     p.Page,
		"limit":    p.Limit,
		"count":    returned,
		"has_more": returned == p.Limit,
	}
}
