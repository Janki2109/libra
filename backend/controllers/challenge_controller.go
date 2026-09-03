package controllers

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"libra/config"
	"libra/utils"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

// ─── GENERATE CASE CHALLENGE ─────────────────
func GenerateChallenge(c *gin.Context) {
	userID, _ := c.Get("user_id")

	var req struct {
		Category string `json:"category" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}

	var level int = 1
	config.DB.QueryRow(
		"SELECT level FROM student_progress WHERE user_id=$1::uuid", userID,
	).Scan(&level)

	// ✅ Generate unique case with Groq AI
	caseData, err := generateCaseWithGroq(req.Category, level)
	if err != nil {
		// Fallback to static case
		caseData = getStaticCase(req.Category)
	}

	id := uuid.New().String()
	questionsJSON, _ := json.Marshal(caseData["questions"])
	suspectsJSON, _ := json.Marshal(caseData["suspects"])
	witnessJSON, _ := json.Marshal(caseData["witnesses"])
	evidenceJSON, _ := json.Marshal(caseData["evidence"])

	_, err = config.DB.Exec(`
		INSERT INTO case_challenges 
		(id, user_id, category, case_title, case_story, suspects, witnesses, evidence, questions)
		VALUES ($1, $2::uuid, $3, $4, $5, $6, $7, $8, $9)
	`, id, userID, req.Category,
		caseData["case_title"], caseData["case_story"],
		suspectsJSON, witnessJSON, evidenceJSON, questionsJSON)

	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to create challenge", err.Error())
		return
	}

	utils.Success(c, http.StatusCreated, "Challenge generated!", gin.H{
		"challenge_id": id,
		"category":     req.Category,
		"case_title":   caseData["case_title"],
		"case_story":   caseData["case_story"],
		"suspects":     caseData["suspects"],
		"witnesses":    caseData["witnesses"],
		"evidence":     caseData["evidence"],
		"questions":    caseData["questions"],
		"level":        level,
	})
}

// ✅ Generate using Groq (Llama 3.3)
//
// The key used to be a hardcoded literal here — GitHub's secret scanning
// flagged it in commit a2eea21. It now comes from the same GROQ_API_KEY_1
// environment variable the rest of the backend's Groq integration
// (services/groq_service.go) already reads, so there is exactly one place
// Groq credentials are configured, not two.
func generateCaseWithGroq(category string, level int) (map[string]interface{}, error) {
	apiKey := config.GetEnv("GROQ_API_KEY_1", "")
	if apiKey == "" {
		return nil, fmt.Errorf("AI challenge generation is not configured — no Groq API key is set on the server")
	}

	difficulty := "beginner"
	if level > 3 {
		difficulty = "intermediate"
	}
	if level > 7 {
		difficulty = "advanced"
	}

	// ✅ Add random seed to ensure unique cases every time
	seed := time.Now().UnixNano()

	prompt := fmt.Sprintf(`You are a legal education AI for Indian law students. Generate a UNIQUE fictional legal case challenge. Seed: %d

Category: %s
Difficulty: %s
Level: %d

IMPORTANT: Return ONLY valid JSON, no markdown, no backticks, no extra text. Make it a completely NEW and UNIQUE story every time.

{
  "case_title": "The Case of [Creative Unique Name]",
  "case_story": "A detailed 3-4 paragraph fictional Indian legal case with specific facts, timeline, location, and context. Make it realistic, engaging and DIFFERENT from common cases.",
  "suspects": [
    {"name": "Indian Name", "description": "Their role and background", "motive": "Why they might be involved"}
  ],
  "witnesses": [
    {"name": "Witness Name", "statement": "Their specific statement"}
  ],
  "evidence": [
    {"item": "Evidence item", "description": "What it proves", "type": "physical/digital/documentary"}
  ],
  "questions": [
    {
      "id": "q1",
      "type": "mcq",
      "question": "Under which specific IPC/BNS section is this offense covered?",
      "options": ["Option A with section", "Option B with section", "Option C with section", "Option D with section"],
      "correct_answer": "Option A with section",
      "explanation": "Detailed legal explanation with section reference"
    },
    {
      "id": "q2",
      "type": "truefalse",
      "question": "True or False: [Specific legal statement about this case]",
      "options": ["True", "False"],
      "correct_answer": "True",
      "explanation": "Why this is true with legal basis"
    },
    {
      "id": "q3",
      "type": "evidence",
      "question": "Which piece of evidence is most legally significant for conviction?",
      "options": ["Evidence 1", "Evidence 2", "Evidence 3", "Evidence 4"],
      "correct_answer": "Evidence 1",
      "explanation": "Legal reasoning for evidence importance"
    },
    {
      "id": "q4",
      "type": "reasoning",
      "question": "What legal principle applies to this case?",
      "options": ["Principle A", "Principle B", "Principle C", "Principle D"],
      "correct_answer": "Principle A",
      "explanation": "Detailed legal principle explanation"
    },
    {
      "id": "q5",
      "type": "decision",
      "question": "As the judge, what is your final verdict based on the evidence?",
      "options": ["Guilty - Convicted", "Not Guilty - Acquitted", "Insufficient Evidence - Dismissed", "Case for Retrial"],
      "correct_answer": "Guilty - Convicted",
      "explanation": "Judicial reasoning based on presented evidence"
    }
  ]
}`, seed, category, difficulty, level)

	reqBody := map[string]interface{}{
		"model": "llama-3.3-70b-versatile",
		"messages": []map[string]string{
			{"role": "system", "content": "You are a legal education AI. Always return valid JSON only, no markdown."},
			{"role": "user", "content": prompt},
		},
		"max_tokens":  2000,
		"temperature": 0.9, // ✅ High temperature = more varied responses
	}

	bodyBytes, _ := json.Marshal(reqBody)
	httpReq, _ := http.NewRequest("POST",
		"https://api.groq.com/openai/v1/chat/completions",
		bytes.NewBuffer(bodyBytes))

	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Authorization", "Bearer "+apiKey)

	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("request failed: %v", err)
	}
	defer resp.Body.Close()

	respBytes, _ := io.ReadAll(resp.Body)

	var groqResp struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
		Error struct {
			Message string `json:"message"`
		} `json:"error"`
	}

	if err := json.Unmarshal(respBytes, &groqResp); err != nil {
		return nil, fmt.Errorf("parse error: %v", err)
	}

	if groqResp.Error.Message != "" {
		return nil, fmt.Errorf("groq error: %s", groqResp.Error.Message)
	}

	if len(groqResp.Choices) == 0 {
		return nil, fmt.Errorf("empty response")
	}

	text := groqResp.Choices[0].Message.Content
	text = cleanJSON(text)

	var result map[string]interface{}
	if err := json.Unmarshal([]byte(text), &result); err != nil {
		return nil, fmt.Errorf("json parse error: %v", err)
	}

	return result, nil
}

func cleanJSON(text string) string {
	// Remove markdown
	for _, prefix := range []string{"```json", "```JSON", "```"} {
		if len(text) > len(prefix) && text[:len(prefix)] == prefix {
			text = text[len(prefix):]
		}
	}
	for len(text) >= 3 && text[len(text)-3:] == "```" {
		text = text[:len(text)-3]
	}
	// Find JSON object
	start := -1
	for i, ch := range text {
		if ch == '{' {
			start = i
			break
		}
	}
	if start >= 0 {
		text = text[start:]
	}

	end := -1
	for i := len(text) - 1; i >= 0; i-- {
		if text[i] == '}' {
			end = i
			break
		}
	}
	if end >= 0 {
		text = text[:end+1]
	}

	return text
}

func minInt(a, b int) int {
	if a < b {
		return a
	}
	return b
}

// ─── SUBMIT ANSWERS ──────────────────────────
func SubmitChallenge(c *gin.Context) {
	challengeID := c.Param("id")
	userID, _ := c.Get("user_id")

	var req struct {
		Answers map[string]string `json:"answers" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}

	var questionsJSON []byte
	var category string
	err := config.DB.QueryRow(`
		SELECT questions, category FROM case_challenges 
		WHERE id=$1::uuid AND user_id=$2::uuid
	`, challengeID, userID).Scan(&questionsJSON, &category)

	if err != nil {
		utils.Error(c, http.StatusNotFound, "Challenge not found", "")
		return
	}

	var questions []map[string]interface{}
	json.Unmarshal(questionsJSON, &questions)

	correct := 0
	total := len(questions)
	evidenceScore := 0
	reasoningScore := 0
	mcqScore := 0

	for _, q := range questions {
		qID := fmt.Sprintf("%v", q["id"])
		correctAns := fmt.Sprintf("%v", q["correct_answer"])
		userAns := req.Answers[qID]

		if userAns == correctAns {
			correct++
			switch fmt.Sprintf("%v", q["type"]) {
			case "evidence":
				evidenceScore += 20
			case "reasoning":
				reasoningScore += 20
			default:
				mcqScore += 10
			}
		}
	}

	accuracy := 0.0
	if total > 0 {
		accuracy = float64(correct) / float64(total) * 100
	}

	xpEarned := correct * 15
	stars := 0
	if accuracy >= 90 {
		stars = 3
		xpEarned += 50
	} else if accuracy >= 70 {
		stars = 2
		xpEarned += 25
	} else if accuracy >= 50 {
		stars = 1
		xpEarned += 10
	}

	totalScore := correct * 10
	answersJSON, _ := json.Marshal(req.Answers)

	config.DB.Exec(`
		UPDATE case_challenges SET
		status='completed', score=$1, xp_earned=$2, stars_earned=$3,
		accuracy=$4, answers=$5, completed_at=NOW()
		WHERE id=$6::uuid
	`, totalScore, xpEarned, stars, accuracy, answersJSON, challengeID)

	config.DB.Exec(`
		INSERT INTO student_progress (id, user_id, xp, total_cases_completed)
		VALUES (gen_random_uuid(), $1::uuid, $2, 1)
		ON CONFLICT (user_id) DO UPDATE SET
		xp = student_progress.xp + $2,
		total_cases_completed = student_progress.total_cases_completed + 1,
		updated_at = NOW()
	`, userID, xpEarned)

	var totalXP int
	config.DB.QueryRow(
		"SELECT xp FROM student_progress WHERE user_id=$1::uuid", userID,
	).Scan(&totalXP)
	newLevel := (totalXP / 500) + 1
	config.DB.Exec(
		"UPDATE student_progress SET level=$1 WHERE user_id=$2::uuid",
		newLevel, userID)

	var userName string
	config.DB.QueryRow("SELECT name FROM users WHERE id=$1::uuid", userID).Scan(&userName)
	config.DB.Exec(`
		INSERT INTO student_leaderboard (id, user_id, user_name, xp, level, cases_won)
		VALUES (gen_random_uuid(), $1::uuid, $2, $3, $4, $5)
		ON CONFLICT (user_id) DO UPDATE SET
		xp=$3, level=$4,
		cases_won = student_leaderboard.cases_won + CASE WHEN $5 > 0 THEN 1 ELSE 0 END,
		user_name=$2,
		updated_at=NOW()
	`, userID, userName, totalXP, newLevel, stars)

	badges := checkBadges(correct, total, accuracy, totalXP, newLevel)

	utils.Success(c, http.StatusOK, "Challenge completed!", gin.H{
		"score":           totalScore,
		"correct":         correct,
		"total":           total,
		"accuracy":        accuracy,
		"xp_earned":       xpEarned,
		"total_xp":        totalXP,
		"stars":           stars,
		"level":           newLevel,
		"evidence_score":  evidenceScore,
		"reasoning_score": reasoningScore,
		"mcq_score":       mcqScore,
		"badges":          badges,
		"passed":          accuracy >= 50,
		"message":         getResultMessage(accuracy),
	})
}

// ─── GET PROGRESS ─────────────────────────────
func GetStudentProgress(c *gin.Context) {
	userID, _ := c.Get("user_id")

	var level, xp, totalCases, streak int
	config.DB.QueryRow(`
		SELECT COALESCE(level,1), COALESCE(xp,0), 
		COALESCE(total_cases_completed,0), COALESCE(current_streak,0)
		FROM student_progress WHERE user_id=$1::uuid
	`, userID).Scan(&level, &xp, &totalCases, &streak)

	rows, _ := config.DB.Query(`
		SELECT id, category, COALESCE(case_title,''), score, accuracy, 
		stars_earned, xp_earned, status, created_at
		FROM case_challenges WHERE user_id=$1::uuid
		ORDER BY created_at DESC LIMIT 10
	`, userID)

	type Challenge struct {
		ID        string    `json:"id"`
		Category  string    `json:"category"`
		Title     string    `json:"case_title"`
		Score     int       `json:"score"`
		Accuracy  float64   `json:"accuracy"`
		Stars     int       `json:"stars_earned"`
		XP        int       `json:"xp_earned"`
		Status    string    `json:"status"`
		CreatedAt time.Time `json:"created_at"`
	}

	challenges := []Challenge{}
	if rows != nil {
		defer rows.Close()
		for rows.Next() {
			var ch Challenge
			rows.Scan(&ch.ID, &ch.Category, &ch.Title, &ch.Score,
				&ch.Accuracy, &ch.Stars, &ch.XP, &ch.Status, &ch.CreatedAt)
			challenges = append(challenges, ch)
		}
	}

	utils.Success(c, http.StatusOK, "Progress fetched", gin.H{
		"progress": gin.H{
			"level":                 level,
			"xp":                    xp,
			"total_cases_completed": totalCases,
			"current_streak":        streak,
			"next_level_xp":         level * 500,
			"current_level_xp":      (level - 1) * 500,
		},
		"challenges": challenges,
	})
}

// SubmitQuizResult records a completed quiz's score. Grading happens
// client-side (the questions and answers are already on the device once
// generated), so this just logs the outcome — it's the only record of a
// quiz ever having been taken, which certificate eligibility reads back.
func SubmitQuizResult(c *gin.Context) {
	userID, _ := c.Get("user_id")

	var req struct {
		Subject      string `json:"subject" binding:"required"`
		ScorePercent int    `json:"score_percent" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.Error(c, http.StatusBadRequest, "Invalid request", err.Error())
		return
	}
	if req.ScorePercent < 0 || req.ScorePercent > 100 {
		utils.Error(c, http.StatusBadRequest, "Invalid score", "must be 0-100")
		return
	}

	_, err := config.DB.Exec(`
		INSERT INTO student_activity_log (id, user_id, activity_type, category, score)
		VALUES (uuid_generate_v4(), $1::uuid, 'quiz', $2, $3)
	`, userID, req.Subject, req.ScorePercent)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed to record quiz result", err.Error())
		return
	}

	utils.Success(c, http.StatusOK, "Quiz result recorded", nil)
}

// certificateDef mirrors the frontend's certificate list — kept in the same
// order so results line up positionally. The frontend still owns the
// display copy (title, icon, description); this only answers "has this
// account actually earned it".
type certificateDef struct {
	Key string
	Met func(userID string) (bool, int, int) // earned, progress, target
}

var certificateDefs = []certificateDef{
	{"constitutional_law", quizCertCheck("Constitutional Law")},
	{"criminal_law", quizCertCheck("BNS / IPC")},
	{"case_solver", caseSolverCertCheck},
	{"contract_law", quizCertCheck("Law of Contracts")},
	{"mock_court_champion", mockCourtCertCheck},
	{"ai_study_partner", aiAdvisorCertCheck},
}

func quizCertCheck(subject string) func(string) (bool, int, int) {
	return func(userID string) (bool, int, int) {
		var best int
		config.DB.QueryRow(`
			SELECT COALESCE(MAX(score), 0) FROM student_activity_log
			WHERE user_id=$1::uuid AND activity_type='quiz' AND category=$2
		`, userID, subject).Scan(&best)
		return best >= 80, best, 80
	}
}

func caseSolverCertCheck(userID string) (bool, int, int) {
	var count int
	config.DB.QueryRow(`
		SELECT COUNT(*) FROM case_challenges WHERE user_id=$1::uuid AND is_submitted=true
	`, userID).Scan(&count)
	target := 5
	if count > target {
		count = target
	}
	return count >= target, count, target
}

func mockCourtCertCheck(userID string) (bool, int, int) {
	var count int
	config.DB.QueryRow(`
		SELECT COUNT(*) FROM student_activity_log
		WHERE user_id=$1::uuid AND activity_type='mock_court' AND result='won'
	`, userID).Scan(&count)
	target := 5
	if count > target {
		count = target
	}
	return count >= target, count, target
}

func aiAdvisorCertCheck(userID string) (bool, int, int) {
	var count int
	config.DB.QueryRow(`
		SELECT COUNT(*) FROM student_activity_log
		WHERE user_id=$1::uuid AND activity_type='ai_advisor'
	`, userID).Scan(&count)
	target := 10
	if count > target {
		count = target
	}
	return count >= target, count, target
}

// GetCertificates reports, for every certificate the app shows, whether the
// signed-in student has actually earned it and how far along they are —
// every entry used to be hardcoded to locked regardless of what the student
// had done, because nothing was ever recorded to check against.
func GetCertificates(c *gin.Context) {
	userID, _ := c.Get("user_id")
	uid, _ := userID.(string)

	results := make([]gin.H, 0, len(certificateDefs))
	for _, def := range certificateDefs {
		earned, progress, target := def.Met(uid)
		results = append(results, gin.H{
			"key":      def.Key,
			"earned":   earned,
			"progress": progress,
			"target":   target,
		})
	}

	utils.Success(c, http.StatusOK, "Certificates fetched", results)
}

// ─── LEADERBOARD ──────────────────────────────
func GetLeaderboard(c *gin.Context) {
	rows, err := config.DB.Query(`
		SELECT user_name, xp, level, cases_won
		FROM student_leaderboard ORDER BY xp DESC LIMIT 20
	`)
	if err != nil {
		utils.Error(c, http.StatusInternalServerError, "Failed", err.Error())
		return
	}
	defer rows.Close()

	type Entry struct {
		Name     string `json:"name"`
		XP       int    `json:"xp"`
		Level    int    `json:"level"`
		CasesWon int    `json:"cases_won"`
	}
	entries := []Entry{}
	for rows.Next() {
		var e Entry
		rows.Scan(&e.Name, &e.XP, &e.Level, &e.CasesWon)
		entries = append(entries, e)
	}
	utils.Success(c, http.StatusOK, "Leaderboard fetched", entries)
}

// ─── GET CHALLENGE ────────────────────────────
func GetChallenge(c *gin.Context) {
	id := c.Param("id")
	userID, _ := c.Get("user_id")

	var ch struct {
		ID        string          `json:"id"`
		Category  string          `json:"category"`
		Title     string          `json:"case_title"`
		Story     string          `json:"case_story"`
		Suspects  json.RawMessage `json:"suspects"`
		Witnesses json.RawMessage `json:"witnesses"`
		Evidence  json.RawMessage `json:"evidence"`
		Questions json.RawMessage `json:"questions"`
		Status    string          `json:"status"`
		Score     int             `json:"score"`
		Accuracy  float64         `json:"accuracy"`
		Stars     int             `json:"stars_earned"`
	}

	err := config.DB.QueryRow(`
		SELECT id, category, case_title, case_story,
		suspects, witnesses, evidence, questions,
		status, score, accuracy, stars_earned
		FROM case_challenges WHERE id=$1::uuid AND user_id=$2::uuid
	`, id, userID).Scan(
		&ch.ID, &ch.Category, &ch.Title, &ch.Story,
		&ch.Suspects, &ch.Witnesses, &ch.Evidence, &ch.Questions,
		&ch.Status, &ch.Score, &ch.Accuracy, &ch.Stars)

	if err != nil {
		utils.Error(c, http.StatusNotFound, "Challenge not found", "")
		return
	}
	utils.Success(c, http.StatusOK, "Challenge fetched", ch)
}

// ─── STATIC FALLBACK ──────────────────────────
func getStaticCase(category string) map[string]interface{} {
	// Random variation so even static cases feel different
	titles := []string{
		"The Case of the Missing Diamond",
		"The Midnight Robbery at Sharma Estate",
		"The Mysterious Death at Hotel Oberoi",
	}
	idx := int(time.Now().UnixNano() % 3)

	return map[string]interface{}{
		"case_title": titles[idx],
		"case_story": `On the night of March 15, 2024, a valuable diamond necklace worth ₹50 lakhs went missing from the Mehta residence in South Mumbai. The family had hosted a dinner party that evening with six guests. The necklace was last seen at 8 PM when Mrs. Mehta showed it to her guests. By 11 PM when guests left, it was missing.

Mumbai Police were called immediately. Security camera at the front entrance had been tampered with between 9:30-10:15 PM. The back door showed signs of forced entry.

Three suspects emerged: Ramesh the driver who had access; Priya a family friend who visited the safe room; and an unknown person whose fingerprints were found on the window sill.`,
		"suspects": []map[string]interface{}{
			{"name": "Ramesh Kumar", "description": "Family driver for 5 years", "motive": "Financial troubles, seen near safe room"},
			{"name": "Priya Sharma", "description": "Family friend with access", "motive": "Gambling debts of ₹10 lakhs"},
		},
		"witnesses": []map[string]interface{}{
			{"name": "Mrs. Mehta", "statement": "I saw Ramesh near my bedroom at 9 PM."},
			{"name": "Neighbor", "statement": "Unfamiliar car parked outside from 9:30-10:00 PM."},
		},
		"evidence": []map[string]interface{}{
			{"item": "Torn fabric on door latch", "description": "Matches Ramesh's uniform color", "type": "physical"},
			{"item": "Tampered CCTV", "description": "Professionally disabled", "type": "digital"},
			{"item": "Financial records", "description": "Priya has ₹10L debt", "type": "documentary"},
		},
		"questions": []map[string]interface{}{
			{
				"id": "q1", "type": "mcq",
				"question":       "Under which IPC section can the accused be charged for theft?",
				"options":        []string{"Section 378 IPC", "Section 420 IPC", "Section 302 IPC", "Section 498 IPC"},
				"correct_answer": "Section 378 IPC",
				"explanation":    "Section 378 IPC defines theft as dishonest taking of movable property.",
			},
			{
				"id": "q2", "type": "truefalse",
				"question":       "True or False: Tampering with CCTV evidence is an offense under Section 65 of IT Act 2000.",
				"options":        []string{"True", "False"},
				"correct_answer": "True",
				"explanation":    "Section 65 of IT Act 2000 covers tampering with computer source documents.",
			},
			{
				"id": "q3", "type": "evidence",
				"question":       "Which evidence most directly links Ramesh to the crime?",
				"options":        []string{"Torn fabric matching his uniform", "Financial records of Priya", "Unknown fingerprints", "Tampered CCTV"},
				"correct_answer": "Torn fabric matching his uniform",
				"explanation":    "Direct physical evidence linking suspect is strongest.",
			},
			{
				"id": "q4", "type": "reasoning",
				"question":       "What must prosecution prove for Section 378 IPC conviction?",
				"options":        []string{"Dishonest intention + taking of property", "Only physical presence at scene", "Financial motive alone", "Prior criminal record"},
				"correct_answer": "Dishonest intention + taking of property",
				"explanation":    "Section 378 requires both mens rea (intention) and actus reus (act).",
			},
			{
				"id": "q5", "type": "decision",
				"question":       "Based on evidence, who is the primary suspect?",
				"options":        []string{"Ramesh Kumar - Primary suspect", "Priya Sharma - Primary suspect", "Unknown Third Party", "Insufficient evidence"},
				"correct_answer": "Ramesh Kumar - Primary suspect",
				"explanation":    "Torn fabric and witness testimony make Ramesh the primary suspect.",
			},
		},
	}
}

func checkBadges(correct, total int, accuracy float64, totalXP, level int) []string {
	badges := []string{}
	if accuracy == 100 {
		badges = append(badges, "Perfect Detective 🎯")
	}
	if accuracy >= 90 {
		badges = append(badges, "Master Investigator 🔍")
	}
	if level >= 5 {
		badges = append(badges, "Senior Advocate ⚖️")
	}
	if level >= 10 {
		badges = append(badges, "Chief Justice 👨‍⚖️")
	}
	if totalXP >= 1000 {
		badges = append(badges, "Legal Eagle 🦅")
	}
	if totalXP >= 5000 {
		badges = append(badges, "Supreme Court Legend 🏛️")
	}
	return badges
}

func getResultMessage(accuracy float64) string {
	if accuracy >= 90 {
		return "Outstanding! You're a legal genius! 🏆"
	}
	if accuracy >= 70 {
		return "Great work! Strong legal instincts! ⭐"
	}
	if accuracy >= 50 {
		return "Good effort! Keep practicing! 📚"
	}
	return "Keep learning! Every case makes you stronger! 💪"
}
