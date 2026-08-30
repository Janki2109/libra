// Package services holds the outbound integrations.
//
// ecourts.go talks to India's eCourts platform, which is the free source of
// case status, cause lists and orders for district courts and High Courts.
// See docs/court-data.md for what is and is not free, and how to get access.
package services

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"libra/config"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// ErrCourtDataUnavailable is returned when no upstream is configured.
var ErrCourtDataUnavailable = errors.New("court data source is not configured")

// ErrNotFound is returned when the upstream has no record for a query.
var ErrNotFound = errors.New("no court record found")

// CaseStatus is the normalized shape the API returns, whichever upstream
// produced it.
type CaseStatus struct {
	CNR             string       `json:"cnr"`
	CaseNumber      string       `json:"case_number"`
	CaseType        string       `json:"case_type"`
	FilingNumber    string       `json:"filing_number"`
	FilingDate      string       `json:"filing_date"`
	RegistrationNo  string       `json:"registration_number"`
	CourtName       string       `json:"court_name"`
	CourtComplex    string       `json:"court_complex"`
	State           string       `json:"state"`
	District        string       `json:"district"`
	JudgeName       string       `json:"judge_name"`
	Petitioners     []string     `json:"petitioners"`
	Respondents     []string     `json:"respondents"`
	Status          string       `json:"status"`
	Stage           string       `json:"stage"`
	FirstHearing    string       `json:"first_hearing_date"`
	NextHearing     string       `json:"next_hearing_date"`
	DecisionDate    string       `json:"decision_date"`
	Hearings        []CourtEvent `json:"hearing_history"`
	Orders          []CourtOrder `json:"orders"`
	Source          string       `json:"source"`
	FetchedAt       time.Time    `json:"fetched_at"`
	FromCache       bool         `json:"from_cache"`
	AttributionNote string       `json:"attribution_note"`
}

// CourtEvent is one line of a case's hearing history.
type CourtEvent struct {
	Date    string `json:"date"`
	Purpose string `json:"purpose"`
	Judge   string `json:"judge"`
	Result  string `json:"result"`
}

// CourtOrder is a published order or judgment.
type CourtOrder struct {
	Date   string `json:"date"`
	Number string `json:"number"`
	Title  string `json:"title"`
	URL    string `json:"url"`
}

// CauseListEntry is one matter listed for a given court on a given day.
type CauseListEntry struct {
	SerialNumber string `json:"serial_number"`
	CaseNumber   string `json:"case_number"`
	CNR          string `json:"cnr"`
	Parties      string `json:"parties"`
	Purpose      string `json:"purpose"`
	CourtNumber  string `json:"court_number"`
	JudgeName    string `json:"judge_name"`
	Stage        string `json:"stage"`
}

// ECourtsClient fetches from whichever free eCourts-backed endpoint is
// configured.
//
// eCourts itself publishes no open REST API — the public site is a CAPTCHA-
// gated form. Two lawful free routes exist, and this client speaks to either:
//
//   - ECOURTS_API_BASE + ECOURTS_API_KEY: an eCourts API gateway. The National
//     Informatics Centre grants free API access to bona fide applicants; several
//     third parties also resell/mirror it with a free tier.
//   - The National Judicial Data Grid (NJDG) open-data endpoints, which are
//     free and unauthenticated but only expose aggregate and cause-list data.
//
// Scraping the eCourts web form directly is deliberately not implemented: it
// requires defeating a CAPTCHA, which breaches the site's terms of use.
type ECourtsClient struct {
	baseURL string
	apiKey  string
	http    *http.Client
}

func NewECourtsClient() *ECourtsClient {
	return &ECourtsClient{
		baseURL: strings.TrimRight(config.GetEnv("ECOURTS_API_BASE", ""), "/"),
		apiKey:  config.GetEnv("ECOURTS_API_KEY", ""),
		http: &http.Client{
			// Government endpoints are frequently slow; they are never fast
			// enough to justify blocking a request thread indefinitely.
			Timeout: 20 * time.Second,
		},
	}
}

// Configured reports whether an upstream is available.
func (e *ECourtsClient) Configured() bool {
	return e.baseURL != ""
}

// ValidateCNR checks the shape of a Case Number Record identifier.
//
// A CNR is exactly 16 characters: a 4-letter court establishment code, a
// 2-digit court number, a 6-digit sequence and a 4-digit year — e.g.
// MHAU010012342024. Checking this locally avoids a pointless round trip and
// gives the user a clear error.
func ValidateCNR(cnr string) error {
	cnr = strings.ToUpper(strings.TrimSpace(cnr))
	if len(cnr) != 16 {
		return fmt.Errorf("a CNR is 16 characters, got %d", len(cnr))
	}
	for i, ch := range cnr {
		switch {
		case i < 4:
			if ch < 'A' || ch > 'Z' {
				return errors.New("the first four characters of a CNR are letters")
			}
		default:
			if ch < '0' || ch > '9' {
				return errors.New("characters 5-16 of a CNR are digits")
			}
		}
	}
	return nil
}

// NormalizeCNR upper-cases and trims a CNR for storage and comparison.
func NormalizeCNR(cnr string) string {
	return strings.ToUpper(strings.TrimSpace(cnr))
}

// CaseStatusByCNR fetches the current status of one case.
func (e *ECourtsClient) CaseStatusByCNR(ctx context.Context, cnr string) (*CaseStatus, error) {
	if !e.Configured() {
		return nil, ErrCourtDataUnavailable
	}
	cnr = NormalizeCNR(cnr)
	if err := ValidateCNR(cnr); err != nil {
		return nil, err
	}

	endpoint := fmt.Sprintf("%s/case/status?cnr=%s", e.baseURL, url.QueryEscape(cnr))

	var raw ecourtsCaseResponse
	if err := e.getJSON(ctx, endpoint, &raw); err != nil {
		return nil, err
	}
	if raw.CNR == "" && raw.CaseNumber == "" {
		return nil, ErrNotFound
	}

	return raw.toCaseStatus(cnr), nil
}

// CauseList fetches the matters listed for a court on a date.
func (e *ECourtsClient) CauseList(
	ctx context.Context, state, district, courtComplex, date string,
) ([]CauseListEntry, error) {
	if !e.Configured() {
		return nil, ErrCourtDataUnavailable
	}

	q := url.Values{}
	q.Set("state", state)
	q.Set("district", district)
	q.Set("court_complex", courtComplex)
	q.Set("date", date)

	endpoint := fmt.Sprintf("%s/cause-list?%s", e.baseURL, q.Encode())

	var raw struct {
		CauseList []CauseListEntry `json:"cause_list"`
		Data      []CauseListEntry `json:"data"`
	}
	if err := e.getJSON(ctx, endpoint, &raw); err != nil {
		return nil, err
	}

	// Gateways differ on whether the array is under "cause_list" or "data".
	if len(raw.CauseList) > 0 {
		return raw.CauseList, nil
	}
	return raw.Data, nil
}

// getJSON performs the request and decodes the body, bounding how much it will
// read so a misbehaving upstream cannot exhaust memory.
func (e *ECourtsClient) getJSON(ctx context.Context, endpoint string, out interface{}) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return err
	}
	req.Header.Set("Accept", "application/json")
	if e.apiKey != "" {
		req.Header.Set("Authorization", "Bearer "+e.apiKey)
		// Gateways vary; sending both costs nothing.
		req.Header.Set("X-API-Key", e.apiKey)
	}

	resp, err := e.http.Do(req)
	if err != nil {
		return fmt.Errorf("court data request failed: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if err != nil {
		return fmt.Errorf("reading court data response: %w", err)
	}

	switch {
	case resp.StatusCode == http.StatusNotFound:
		return ErrNotFound
	case resp.StatusCode == http.StatusTooManyRequests:
		return errors.New("court data source rate limit reached, try again later")
	case resp.StatusCode < 200 || resp.StatusCode >= 300:
		return fmt.Errorf("court data source returned %d", resp.StatusCode)
	}

	if err := json.Unmarshal(body, out); err != nil {
		return fmt.Errorf("court data source returned an unexpected format: %w", err)
	}
	return nil
}

// ecourtsCaseResponse mirrors the field names the common eCourts gateways use.
// They are inconsistent about naming, so the frequent aliases are accepted and
// normalized into one shape rather than leaking upstream quirks to the client.
type ecourtsCaseResponse struct {
	CNR            string `json:"cnr"`
	CaseNumber     string `json:"case_number"`
	CaseType       string `json:"case_type"`
	FilingNumber   string `json:"filing_number"`
	FilingDate     string `json:"filing_date"`
	RegistrationNo string `json:"registration_number"`
	CourtName      string `json:"court_name"`
	CourtComplex   string `json:"court_complex"`
	State          string `json:"state"`
	District       string `json:"district"`
	JudgeName      string `json:"judge_name"`

	Petitioners []string `json:"petitioners"`
	Respondents []string `json:"respondents"`

	// Some gateways send a single joined string instead of an array.
	PetitionerName string `json:"petitioner_name"`
	RespondentName string `json:"respondent_name"`

	Status       string `json:"status"`
	CaseStatus   string `json:"case_status"`
	Stage        string `json:"stage"`
	FirstHearing string `json:"first_hearing_date"`
	NextHearing  string `json:"next_hearing_date"`
	DecisionDate string `json:"decision_date"`

	History []struct {
		Date    string `json:"date"`
		Purpose string `json:"purpose"`
		Judge   string `json:"judge"`
		Result  string `json:"result"`
	} `json:"hearing_history"`

	Orders []struct {
		Date   string `json:"date"`
		Number string `json:"number"`
		Title  string `json:"title"`
		URL    string `json:"url"`
	} `json:"orders"`
}

func (r ecourtsCaseResponse) toCaseStatus(cnr string) *CaseStatus {
	status := r.Status
	if status == "" {
		status = r.CaseStatus
	}

	petitioners := r.Petitioners
	if len(petitioners) == 0 && r.PetitionerName != "" {
		petitioners = splitParties(r.PetitionerName)
	}
	respondents := r.Respondents
	if len(respondents) == 0 && r.RespondentName != "" {
		respondents = splitParties(r.RespondentName)
	}

	out := &CaseStatus{
		CNR:            firstNonEmpty(r.CNR, cnr),
		CaseNumber:     r.CaseNumber,
		CaseType:       r.CaseType,
		FilingNumber:   r.FilingNumber,
		FilingDate:     r.FilingDate,
		RegistrationNo: r.RegistrationNo,
		CourtName:      r.CourtName,
		CourtComplex:   r.CourtComplex,
		State:          r.State,
		District:       r.District,
		JudgeName:      r.JudgeName,
		Petitioners:    petitioners,
		Respondents:    respondents,
		Status:         status,
		Stage:          r.Stage,
		FirstHearing:   r.FirstHearing,
		NextHearing:    r.NextHearing,
		DecisionDate:   r.DecisionDate,
		Source:         "ecourts",
		FetchedAt:      time.Now().UTC(),
		AttributionNote: "Sourced from eCourts / National Judicial Data Grid, " +
			"Department of Justice, Government of India. Verify against the " +
			"court record before relying on it.",
	}

	for _, h := range r.History {
		out.Hearings = append(out.Hearings, CourtEvent{
			Date: h.Date, Purpose: h.Purpose, Judge: h.Judge, Result: h.Result,
		})
	}
	for _, o := range r.Orders {
		out.Orders = append(out.Orders, CourtOrder{
			Date: o.Date, Number: o.Number, Title: o.Title, URL: o.URL,
		})
	}

	return out
}

// splitParties turns "A Kumar, B Singh" or "A Kumar and B Singh" into a slice.
func splitParties(s string) []string {
	s = strings.ReplaceAll(s, " and ", ",")
	parts := strings.Split(s, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}
	return out
}

func firstNonEmpty(vals ...string) string {
	for _, v := range vals {
		if v != "" {
			return v
		}
	}
	return ""
}
