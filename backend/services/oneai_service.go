package services

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"

	"libra/config"
)

// OneAI is a much simpler API than Groq's: one POST /chat endpoint taking a
// single "message" string and returning a single "reply" string. No system
// prompt, no multi-turn message array, no model/token/temperature controls,
// and no image input — so it stands in for Groq on plain text generation
// only. Vision (OCR) still requires Groq.
const (
	oneAIDefaultBaseURL = "https://34-224-90-21.sslip.io"
	// Kept short enough that one retry still finishes well inside the app's
	// own 60s request timeout — OneAI's free shared model is occasionally
	// slow or flaky, and a single transient failure shouldn't cost the user
	// the full round trip twice before they see anything.
	oneAIRequestTimeout = 18 * time.Second
)

func oneAIBaseURL() string {
	return config.GetEnv("ONEAI_BASE_URL", oneAIDefaultBaseURL)
}

func oneAIAPIKey() string {
	return config.GetEnv("ONEAI_API_KEY", "")
}

// oneAIConfigured reports whether a key is set, so callers can fall back to
// Groq without making a doomed request first.
func oneAIConfigured() bool {
	return oneAIAPIKey() != ""
}

// callOneAI sends one message and returns the reply, retrying once on
// failure. OneAI's free shared model occasionally times out or errors
// transiently under load; one immediate retry meaningfully improves the
// success rate without making a real failure take noticeably longer to
// surface.
func callOneAI(message string) (string, error) {
	reply, err := callOneAIOnce(message)
	if err == nil {
		return reply, nil
	}
	return callOneAIOnce(message)
}

// callOneAIOnce is a single attempt. There is no system/user split in this
// API, so callers fold both into one string.
func callOneAIOnce(message string) (string, error) {
	body, err := json.Marshal(map[string]string{"message": message})
	if err != nil {
		return "", err
	}

	req, err := http.NewRequest(http.MethodPost, oneAIBaseURL()+"/chat", bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Authorization", "Bearer "+oneAIAPIKey())
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{Timeout: oneAIRequestTimeout}
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	respBody, _ := io.ReadAll(resp.Body)
	if resp.StatusCode == http.StatusTooManyRequests {
		// OneAI's free tier caps at 20 requests/minute per calling IP — and
		// every user of this app shares this server's one IP, so the shared
		// quota exhausts fast under any real concurrent usage. This is the
		// single most common OneAI failure in production; callers should
		// treat it as "try again shortly", not "unconfigured".
		return "", fmt.Errorf("AI service is busy right now (rate limited) — please try again in a moment")
	}
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("oneai status %d: %s", resp.StatusCode, string(respBody))
	}

	var parsed struct {
		Reply string `json:"reply"`
	}
	if err := json.Unmarshal(respBody, &parsed); err != nil || parsed.Reply == "" {
		return "", fmt.Errorf("unexpected response shape from OneAI")
	}
	return parsed.Reply, nil
}
