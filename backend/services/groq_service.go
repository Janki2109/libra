package services

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"libra/config"
)

// groqKeyPool rotates across several Groq API keys so one rate-limited or
// temporarily-failing key does not block AI generation. Keys live only in
// backend environment variables (GROQ_API_KEY_1..N) — never sent to the
// Flutter app, never logged.
type groqKeyPool struct {
	mu        sync.Mutex
	keys      []string
	cooldowns []time.Time // cooldowns[i] is when keys[i] becomes usable again
}

// Lazily initialized on first use, not as a package-level var — Go runs
// package-level var initializers before main(), which is before
// config.LoadConfig() has read .env, so an eager init here always saw an
// empty environment and reported "no keys configured" even when .env had
// them.
var (
	groqPool     *groqKeyPool
	groqPoolOnce sync.Once
)

func getGroqPool() *groqKeyPool {
	groqPoolOnce.Do(func() { groqPool = loadGroqKeyPool() })
	return groqPool
}

func loadGroqKeyPool() *groqKeyPool {
	var keys []string
	for i := 1; i <= 10; i++ {
		k := config.GetEnv(fmt.Sprintf("GROQ_API_KEY_%d", i), "")
		if k != "" {
			keys = append(keys, k)
		}
	}
	if len(keys) == 0 {
		log.Println("[groq] no GROQ_API_KEY_1..N configured — AI drafting will return an error until keys are set")
	} else {
		log.Printf("[groq] %d API key(s) loaded for rotation", len(keys))
	}
	return &groqKeyPool{keys: keys, cooldowns: make([]time.Time, len(keys))}
}

// availableKeyIndexes returns key indexes not currently in cooldown, in
// rotation order (1, 2, 3, ...).
func (p *groqKeyPool) availableKeyIndexes() []int {
	p.mu.Lock()
	defer p.mu.Unlock()
	now := time.Now()
	var idx []int
	for i, until := range p.cooldowns {
		if now.After(until) {
			idx = append(idx, i)
		}
	}
	return idx
}

// coolDown marks a key temporarily unusable. Never permanent — the key
// becomes eligible again as soon as `until` passes, so a rate limit today
// does not disable the key forever.
func (p *groqKeyPool) coolDown(index int, until time.Time) {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.cooldowns[index] = until
}

const (
	groqURL              = "https://api.groq.com/openai/v1/chat/completions"
	groqDefaultCooldown  = 60 * time.Second  // rate limit / transient failure
	groqAuthKeyCooldown  = 5 * time.Minute   // invalid/unauthorized key — still not permanent, per requirements
	groqRequestTimeout   = 30 * time.Second
)

// GenerateLegalDraft tries each configured Groq key in order, skipping any
// currently in cooldown, until one succeeds or all are exhausted. Every call
// is a fresh HTTP request to Groq — nothing here is cached, so the caller
// always gets a new generation for the current prompt.
func GenerateLegalDraft(systemPrompt, userPrompt string, maxTokens int, temperature float64) (string, error) {
	return rotateAndCall(func(apiKey string) (string, time.Duration, error) {
		return callGroq(apiKey, systemPrompt, userPrompt, maxTokens, temperature)
	})
}

// GenerateChat is GenerateLegalDraft's counterpart for a multi-turn
// conversation (used by the AI Legal Advisor chat) — same key pool, same
// rotation/cooldown behaviour, just a full message history instead of a
// single system+user pair.
func GenerateChat(messages []map[string]string, maxTokens int, temperature float64) (string, error) {
	return rotateAndCall(func(apiKey string) (string, time.Duration, error) {
		return callGroqChat(apiKey, messages, maxTokens, temperature)
	})
}

// GenerateVisionText is GenerateLegalDraft's counterpart for image input
// (used by OCR) — same key pool, same rotation/cooldown behaviour, just a
// multimodal request to a vision-capable Groq model instead of a text-only
// one.
func GenerateVisionText(systemPrompt, userPrompt, imageDataURI string, maxTokens int) (string, error) {
	return rotateAndCall(func(apiKey string) (string, time.Duration, error) {
		return callGroqVision(apiKey, systemPrompt, userPrompt, imageDataURI, maxTokens)
	})
}

// rotateAndCall is the shared rotation loop: try each key not currently in
// cooldown, in order, until one succeeds or all are exhausted.
func rotateAndCall(call func(apiKey string) (content string, retryAfter time.Duration, err error)) (string, error) {
	pool := getGroqPool()
	if len(pool.keys) == 0 {
		return "", fmt.Errorf("AI drafting is not configured — no Groq API keys are set on the server")
	}

	indexes := pool.availableKeyIndexes()
	if len(indexes) == 0 {
		return "", fmt.Errorf("AI drafting is temporarily unavailable — all configured keys are cooling down, try again shortly")
	}

	var lastErr error
	for _, i := range indexes {
		log.Printf("[groq] attempting generation with key #%d", i+1)
		content, retryAfter, err := call(pool.keys[i])
		if err == nil {
			return content, nil
		}
		lastErr = err

		cooldownUntil := time.Now().Add(groqDefaultCooldown)
		if retryAfter > 0 {
			cooldownUntil = time.Now().Add(retryAfter)
		} else if isAuthFailure(err) {
			cooldownUntil = time.Now().Add(groqAuthKeyCooldown)
		}
		pool.coolDown(i, cooldownUntil)
		log.Printf("[groq] key #%d failed (%v) — cooling down, trying next key", i+1, classifyError(err))
	}

	return "", fmt.Errorf("AI drafting failed — every configured key is currently unavailable (last error: %v)", classifyError(lastErr))
}

type groqErrType int

const (
	errAuth groqErrType = iota
	errRateLimit
	errOther
)

func isAuthFailure(err error) bool {
	ge, ok := err.(*groqError)
	return ok && ge.kind == errAuth
}

func classifyError(err error) string {
	ge, ok := err.(*groqError)
	if !ok {
		return err.Error()
	}
	switch ge.kind {
	case errAuth:
		return "authentication failure"
	case errRateLimit:
		return "rate limited"
	default:
		return "provider error"
	}
}

type groqError struct {
	kind    groqErrType
	status  int
	message string
}

func (e *groqError) Error() string {
	return fmt.Sprintf("groq status %d: %s", e.status, e.message)
}

// callGroq makes one text-only request against one key. It never logs the
// key itself.
func callGroq(apiKey, systemPrompt, userPrompt string, maxTokens int, temperature float64) (content string, retryAfter time.Duration, err error) {
	body, _ := json.Marshal(map[string]any{
		"model": "openai/gpt-oss-120b",
		"messages": []map[string]string{
			{"role": "system", "content": systemPrompt},
			{"role": "user", "content": userPrompt},
		},
		"max_tokens":  maxTokens,
		"temperature": temperature,
	})
	return sendGroqRequest(apiKey, body)
}

// callGroqChat makes one request against one key using a caller-supplied
// message history (system + prior turns + latest user message).
func callGroqChat(apiKey string, messages []map[string]string, maxTokens int, temperature float64) (content string, retryAfter time.Duration, err error) {
	body, _ := json.Marshal(map[string]any{
		"model":       "openai/gpt-oss-120b",
		"messages":    messages,
		"max_tokens":  maxTokens,
		"temperature": temperature,
	})
	return sendGroqRequest(apiKey, body)
}

// callGroqVision makes one multimodal (text + image) request against one
// key, using a vision-capable Groq model. Used only by OCR.
func callGroqVision(apiKey, systemPrompt, userPrompt, imageDataURI string, maxTokens int) (content string, retryAfter time.Duration, err error) {
	body, _ := json.Marshal(map[string]any{
		"model": "qwen/qwen3.6-27b",
		"messages": []map[string]any{
			{"role": "system", "content": systemPrompt},
			{"role": "user", "content": []map[string]any{
				{"type": "text", "text": userPrompt},
				{"type": "image_url", "image_url": map[string]string{"url": imageDataURI}},
			}},
		},
		"max_tokens":  maxTokens,
		"temperature": 0.2,
	})
	return sendGroqRequest(apiKey, body)
}

// sendGroqRequest posts a pre-built chat-completion body and parses the
// response, shared by the text-only and vision call paths.
func sendGroqRequest(apiKey string, body []byte) (content string, retryAfter time.Duration, err error) {
	req, err := http.NewRequest(http.MethodPost, groqURL, bytes.NewReader(body))
	if err != nil {
		return "", 0, &groqError{kind: errOther, message: err.Error()}
	}
	req.Header.Set("Authorization", "Bearer "+apiKey)
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{Timeout: groqRequestTimeout}
	resp, err := client.Do(req)
	if err != nil {
		return "", 0, &groqError{kind: errOther, message: err.Error()}
	}
	defer resp.Body.Close()

	respBody, _ := io.ReadAll(resp.Body)

	if resp.StatusCode == http.StatusTooManyRequests {
		ra := parseRetryAfter(resp.Header.Get("Retry-After"))
		return "", ra, &groqError{kind: errRateLimit, status: resp.StatusCode, message: "rate limited"}
	}
	if resp.StatusCode == http.StatusUnauthorized || resp.StatusCode == http.StatusForbidden {
		return "", 0, &groqError{kind: errAuth, status: resp.StatusCode, message: "unauthorized"}
	}
	if resp.StatusCode >= 500 {
		return "", 0, &groqError{kind: errOther, status: resp.StatusCode, message: "provider error"}
	}
	if resp.StatusCode != http.StatusOK {
		return "", 0, &groqError{kind: errOther, status: resp.StatusCode, message: string(respBody)}
	}

	var parsed struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if err := json.Unmarshal(respBody, &parsed); err != nil || len(parsed.Choices) == 0 {
		return "", 0, &groqError{kind: errOther, message: "unexpected response shape from provider"}
	}
	return parsed.Choices[0].Message.Content, 0, nil
}

func parseRetryAfter(v string) time.Duration {
	if v == "" {
		return 0
	}
	if secs, err := strconv.Atoi(strings.TrimSpace(v)); err == nil && secs > 0 {
		return time.Duration(secs) * time.Second
	}
	return 0
}
