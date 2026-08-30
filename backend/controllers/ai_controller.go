package controllers

import (
	"net/http"
	"regexp"
	"strconv"
	"strings"

	"libra/services"
	"libra/utils"

	"github.com/gin-gonic/gin"
)

var thinkBlockRE = regexp.MustCompile(`(?s)<think>.*?</think>`)

// stripThinkingBlock removes a reasoning-model's <think>...</think> block
// (some vision-capable Groq models emit one inline despite being told not
// to) so the OCR result shown in the app is just the transcribed text.
func stripThinkingBlock(s string) string {
	return strings.TrimSpace(thinkBlockRE.ReplaceAllString(s, ""))
}

// GenerateDraft proxies AI legal-drafting generation to Groq, rotating across
// server-side API keys (see services.GenerateLegalDraft) so the key never
// reaches the Flutter app and one rate-limited/failing key doesn't block
// generation. Every call makes a fresh request to Groq — nothing is cached.
func GenerateDraft(c *gin.Context) {
	var req struct {
		Prompt string `json:"prompt" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}

	systemPrompt := "You are an expert Indian lawyer specializing in legal document drafting. " +
		"Generate complete, professionally formatted legal documents following Indian legal conventions."

	content, err := services.GenerateLegalDraft(systemPrompt, req.Prompt, 2000, 0.3)
	if err != nil {
		utils.Error(c, http.StatusServiceUnavailable, "AI drafting failed", err.Error())
		return
	}

	utils.Success(c, http.StatusOK, "Document generated", gin.H{"content": content})
}

// GenerateAITool serves the rest of the Smart Draft AI Tools (Generate
// Summary, Translator, OCR, Timeline Generator, Ask Questions, Compare
// Documents, Citation Verifier). All of them are the same shape as
// GenerateDraft — a system prompt plus the caller's content, run through the
// same key-rotation pool — so they share that pool and the OCR path's vision
// call instead of each tool inventing its own AI plumbing.
func GenerateAITool(c *gin.Context) {
	var req struct {
		Tool           string `json:"tool" binding:"required"`
		Text           string `json:"text"`
		SecondText     string `json:"second_text"`
		TargetLanguage string `json:"target_language"`
		Question       string `json:"question"`
		ImageBase64    string `json:"image_base64"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}

	const baseSystem = "You are an expert Indian lawyer's AI assistant. Be precise, professional, " +
		"and follow Indian legal conventions where relevant."

	var content string
	var err error

	switch req.Tool {
	case "summary":
		if req.Text == "" {
			utils.Error(c, http.StatusBadRequest, "Document text is required", "")
			return
		}
		content, err = services.GenerateLegalDraft(
			baseSystem+" Summarize legal documents concisely, preserving every material fact, "+
				"party, date, obligation and figure.",
			"Summarize the following legal document:\n\n"+req.Text, 1200, 0.2)

	case "translate":
		if req.Text == "" || req.TargetLanguage == "" {
			utils.Error(c, http.StatusBadRequest, "Text and target language are required", "")
			return
		}
		content, err = services.GenerateLegalDraft(
			baseSystem+" Translate legal text accurately, preserving legal meaning and formal tone.",
			"Translate the following legal document/text into "+req.TargetLanguage+
				". Preserve legal terminology precisely:\n\n"+req.Text, 2000, 0.2)

	case "timeline":
		if req.Text == "" {
			utils.Error(c, http.StatusBadRequest, "Case/document text is required", "")
			return
		}
		content, err = services.GenerateLegalDraft(
			baseSystem+" Extract every dated event from legal case material and present it as a "+
				"clear chronological timeline (date — event), in order, with nothing invented.",
			"Generate a chronological timeline from the following case/document information:\n\n"+req.Text,
			1500, 0.2)

	case "ask":
		if req.Text == "" || req.Question == "" {
			utils.Error(c, http.StatusBadRequest, "Document text and question are required", "")
			return
		}
		content, err = services.GenerateLegalDraft(
			baseSystem+" Answer strictly using the provided document/context. If the answer is not "+
				"in the provided content, say so explicitly rather than guessing.",
			"Document/context:\n\n"+req.Text+"\n\nQuestion: "+req.Question, 1000, 0.2)

	case "compare":
		if req.Text == "" || req.SecondText == "" {
			utils.Error(c, http.StatusBadRequest, "Both documents are required", "")
			return
		}
		content, err = services.GenerateLegalDraft(
			baseSystem+" Compare two legal documents and report the important differences — changed "+
				"clauses, added/removed obligations, changed parties/dates/figures — as a clear list.",
			"Document A:\n\n"+req.Text+"\n\n---\n\nDocument B:\n\n"+req.SecondText+
				"\n\nList the important differences between Document A and Document B.", 2000, 0.2)

	case "citation":
		if req.Text == "" {
			utils.Error(c, http.StatusBadRequest, "Document text is required", "")
			return
		}
		content, err = services.GenerateLegalDraft(
			baseSystem+" Review legal citations/references (case law, statutes, sections) in the "+
				"provided content. Flag any that look incorrect, incomplete, inconsistent or "+
				"unverifiable, and explain why. If a citation looks correct, say so briefly.",
			"Review the citations/references in the following content:\n\n"+req.Text, 1500, 0.2)

	case "ocr":
		if req.ImageBase64 == "" {
			utils.Error(c, http.StatusBadRequest, "An image is required", "")
			return
		}
		content, err = services.GenerateVisionText(
			baseSystem+" Extract all readable text from the provided document image, exactly as "+
				"written. Preserve line breaks and structure where possible. Do not include any "+
				"reasoning, analysis, notes or <think> tags — reply with ONLY the transcribed text "+
				"itself and nothing else.",
			"Extract the text from this document image.", req.ImageBase64, 2000)
		content = stripThinkingBlock(content)

	default:
		utils.Error(c, http.StatusBadRequest, "Unknown tool", req.Tool)
		return
	}

	if err != nil {
		utils.Error(c, http.StatusServiceUnavailable, "AI request failed", err.Error())
		return
	}
	utils.Success(c, http.StatusOK, "Generated", gin.H{"content": content})
}

// AdvisorChat serves the AI Legal Advisor chat. Like GenerateDraft/
// GenerateAITool it goes through the same server-side Groq key pool — the
// screen that calls this used to hold its own hardcoded (and since revoked)
// Groq key and call api.groq.com directly, which is what produced the 401
// the user saw; it never touched this rotation system at all.
//
// The system prompt is fixed here, not taken from the client, so the
// advisor's behavior can't be redirected by a tampered request; only the
// conversation history and latest question come from the app.
func AdvisorChat(c *gin.Context) {
	var req struct {
		Messages []struct {
			Role    string `json:"role"`
			Content string `json:"content"`
		} `json:"messages" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}

	messages := []map[string]string{
		{"role": "system", "content": "You are LexAI, an expert Indian lawyer AI assistant. " +
			"Answer only Indian law questions. Cite relevant IPC/CrPC/BNS/Constitution sections. " +
			"Keep responses concise. Always end with: \"⚠️ Note: This is general legal information, " +
			"not a substitute for professional legal advice.\""},
	}
	for _, m := range req.Messages {
		role := m.Role
		if role != "user" && role != "assistant" {
			continue // never let the client inject a second system prompt
		}
		messages = append(messages, map[string]string{"role": role, "content": m.Content})
	}

	content, err := services.GenerateChat(messages, 1000, 0.7)
	if err != nil {
		utils.Error(c, http.StatusServiceUnavailable, "AI request failed", err.Error())
		return
	}
	utils.Success(c, http.StatusOK, "Generated", gin.H{"content": content})
}

// LegalResearch serves the lawyer-side AI Legal Research screen — same
// hardcoded-key-bypassing-the-rotation-pool bug as AdvisorChat, fixed the
// same way: the screen now sends only conversation history + question, and
// the fixed system prompt plus key rotation both live here.
func LegalResearch(c *gin.Context) {
	var req struct {
		Messages []struct {
			Role    string `json:"role"`
			Content string `json:"content"`
		} `json:"messages" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}

	messages := []map[string]string{
		{"role": "system", "content": `You are an expert Indian legal research assistant for lawyers.
Provide detailed, accurate legal research including:
- Relevant Acts and Sections with exact section numbers
- Important case laws with citations
- Legal principles and interpretations
- Recent amendments if any
- Practical application for lawyers

Format your response clearly with headings.
Always cite: Act name, Section number, Case name (Year).
Be comprehensive but organized.`},
	}
	for _, m := range req.Messages {
		role := m.Role
		if role != "user" && role != "assistant" {
			continue
		}
		messages = append(messages, map[string]string{"role": role, "content": m.Content})
	}

	content, err := services.GenerateChat(messages, 1500, 0.3)
	if err != nil {
		utils.Error(c, http.StatusServiceUnavailable, "AI request failed", err.Error())
		return
	}
	utils.Success(c, http.StatusOK, "Generated", gin.H{"content": content})
}

// GenerateQuiz serves the Legal Quiz screen. Same pattern as GenerateDraft —
// same server-side Groq key pool/rotation, same "fresh request every time"
// behaviour — this screen previously held its own hardcoded (and since
// revoked) Groq key and called api.groq.com directly, which is what produced
// the 401 the user saw.
//
// The prompt logic (case-based vs. regular MCQs) mirrors exactly what the
// screen used to build client-side, so quiz behavior/format is unchanged —
// only where the Groq call happens has moved.
func GenerateQuiz(c *gin.Context) {
	var req struct {
		Subject  string `json:"subject" binding:"required"`
		Count    int    `json:"count" binding:"required"`
		QuizType string `json:"quiz_type"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}
	if req.Count > 30 {
		req.Count = 30 // matches the largest quiz type the screen offers (Mock Exam, 25 Q) plus headroom
	}

	count := strconv.Itoa(req.Count)
	var prompt string
	if req.QuizType == "case" {
		prompt = "Generate " + count + " case-based legal MCQ questions about " + req.Subject +
			" for Indian law students.\n" +
			"Each question should present a brief scenario/case and ask what law applies.\n" +
			"Return ONLY valid JSON array, no other text:\n" +
			`[{"question": "Case scenario here...", "options": ["A) option1", "B) option2", "C) option3", "D) option4"], "correct": 0, "explanation": "Brief explanation"}]` +
			"\ncorrect is 0-based index. Generate exactly " + count + " questions."
	} else {
		prompt = "Generate " + count + " MCQ questions about " + req.Subject +
			" for Indian law students (LLB/BA LLB level).\n" +
			"Include questions about sections, cases, definitions and principles.\n" +
			"Return ONLY valid JSON array, no other text:\n" +
			`[{"question": "Question here?", "options": ["A) option1", "B) option2", "C) option3", "D) option4"], "correct": 0, "explanation": "Brief explanation"}]` +
			"\ncorrect is 0-based index. Generate exactly " + count + " questions."
	}

	systemPrompt := "You are a legal exam question generator. Generate accurate MCQ questions about Indian law. " +
		"Return ONLY valid JSON array."

	content, err := services.GenerateLegalDraft(systemPrompt, prompt, 3000, 0.7)
	if err != nil {
		utils.Error(c, http.StatusServiceUnavailable, "AI request failed", err.Error())
		return
	}
	utils.Success(c, http.StatusOK, "Generated", gin.H{"content": content})
}

// GenerateMockCase and EvaluateMockCourt serve the Mock Court screen's two
// AI steps (case generation, then judge evaluation). Same pattern as
// GenerateDraft/GenerateQuiz — same server-side Groq key pool/rotation. The
// screen previously held its own hardcoded (and since revoked) Groq key and
// called api.groq.com directly for both steps, which is what produced the
// 401 the user saw. Prompts mirror exactly what the screen used to build
// client-side, so case/evaluation format is unchanged.
func GenerateMockCase(c *gin.Context) {
	var req struct {
		CaseType string `json:"case_type" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}

	systemPrompt := "You are a legal case generator for Indian law students. Generate realistic Indian court cases."
	prompt := "Generate a " + req.CaseType + ` mock court case for Indian law students.
Return ONLY valid JSON:
{
  "title": "Case title",
  "court": "Court name",
  "parties": {"plaintiff": "Name", "defendant": "Name"},
  "facts": "Detailed facts of the case (3-4 paragraphs)",
  "issues": ["Legal issue 1", "Legal issue 2", "Legal issue 3"],
  "applicable_laws": ["Section X of Act Y", "Case Law Z"],
  "prosecution_hints": "Key points for prosecution/plaintiff",
  "defence_hints": "Key points for defence/defendant"
}`

	content, err := services.GenerateLegalDraft(systemPrompt, prompt, 1500, 0.8)
	if err != nil {
		utils.Error(c, http.StatusServiceUnavailable, "AI request failed", err.Error())
		return
	}
	utils.Success(c, http.StatusOK, "Generated", gin.H{"content": content})
}

func EvaluateMockCourt(c *gin.Context) {
	var req struct {
		CaseTitle  string `json:"case_title"`
		CaseFacts  string `json:"case_facts"`
		Issues     string `json:"issues"`
		Role       string `json:"role" binding:"required"`
		Arguments  string `json:"arguments" binding:"required"`
		Submission string `json:"submission"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}

	systemPrompt := "You are a judge evaluating law student arguments in a mock court."
	prompt := `Evaluate this law student's arguments in a mock court case.

CASE: ` + req.CaseTitle + `
FACTS: ` + req.CaseFacts + `
ISSUES: ` + req.Issues + `
STUDENT ROLE: ` + req.Role + `
STUDENT ARGUMENTS: ` + req.Arguments + `
WRITTEN SUBMISSION: ` + req.Submission + `

Return ONLY valid JSON:
{
  "score": 85,
  "grade": "B+",
  "verdict": "Partly allowed",
  "strengths": ["Point 1", "Point 2"],
  "weaknesses": ["Point 1", "Point 2"],
  "missed_points": ["Important argument missed"],
  "judge_remarks": "Detailed feedback from judge",
  "result": "won/lost/partial",
  "xp_earned": 150
}`

	content, err := services.GenerateLegalDraft(systemPrompt, prompt, 1000, 0.3)
	if err != nil {
		utils.Error(c, http.StatusServiceUnavailable, "AI request failed", err.Error())
		return
	}
	utils.Success(c, http.StatusOK, "Generated", gin.H{"content": content})
}
