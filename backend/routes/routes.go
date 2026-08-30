package routes

import (
	"context"
	"libra/config"
	"libra/controllers"
	"libra/middleware"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

func SetupRoutes() *gin.Engine {
	r := gin.New()
	r.Use(gin.Recovery())
	if !config.IsProduction() {
		r.Use(gin.Logger())
	}
	r.Use(middleware.SecurityHeaders())
	r.Use(middleware.CorsMiddleware())
	// List payloads are mostly repeated JSON keys and UUIDs and compress ~85%.
	// On mobile networks transfer time dominates every list screen.
	r.Use(middleware.Gzip())

	// Cap request bodies. Without this a single POST can stream unbounded data
	// into memory — UploadDocument in particular accepts a base64 payload.
	r.MaxMultipartMemory = 12 << 20
	r.Use(middleware.BodyLimit(12 << 20))

	// Liveness: the process is up.
	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok", "message": "Libra Law Practice API running"})
	})

	// Readiness: the process can actually serve traffic. /health answered 200
	// unconditionally, so a load balancer kept sending requests to an instance
	// whose database had gone away.
	r.GET("/ready", func(c *gin.Context) {
		ctx, cancel := context.WithTimeout(c.Request.Context(), 3*time.Second)
		defer cancel()
		if err := config.Healthy(ctx); err != nil {
			c.JSON(http.StatusServiceUnavailable, gin.H{"status": "degraded", "database": "unreachable"})
			return
		}
		c.JSON(http.StatusOK, gin.H{"status": "ok", "database": "ok"})
	})

	api := r.Group("/api/v1")

	// Credential endpoints were completely unthrottled — free rein for
	// credential stuffing, and a 6-digit OTP falls in under a minute at HTTP
	// speeds. Signup is throttled separately and more loosely.
	loginLimiter := middleware.NewRateLimiter(10, time.Minute)
	otpLimiter := middleware.NewRateLimiter(5, 15*time.Minute)
	signupLimiter := middleware.NewRateLimiter(5, time.Hour)

	// ─── PUBLIC ──────────────────────────────────
	auth := api.Group("/auth")
	{
		auth.POST("/login", loginLimiter.Middleware(), controllers.Login)
		auth.POST("/register", signupLimiter.Middleware(), controllers.Register)
		auth.POST("/client/register", signupLimiter.Middleware(), controllers.ClientRegister)
		auth.POST("/student/register", signupLimiter.Middleware(), controllers.StudentRegister)
		auth.POST("/send-otp", otpLimiter.Middleware(), controllers.SendOTP)
		auth.POST("/verify-otp", otpLimiter.Middleware(), controllers.VerifyOTP)
		auth.POST("/logout", controllers.Logout)
		auth.GET("/plans", controllers.GetPlans)
	}

	api.POST("/portal/login", loginLimiter.Middleware(), controllers.PortalLogin)

	// ─── CALL SIGNALING (WebRTC) ─────────────────
	// Outside the auth middleware by necessity — browser WebSocket clients
	// can't set an Authorization header on the handshake. The JWT instead
	// travels as a query param and is validated inside the handler itself,
	// which then re-checks that the caller is actually a participant on this
	// exact consultation before allowing the upgrade.
	api.GET("/consultations/:id/call/ws", controllers.CallSignalingWS)

	// ─── WEBHOOKS ────────────────────────────────
	// Outside the auth middleware by necessity — the gateway has no session.
	// Authenticity comes from the HMAC signature over the raw body, which the
	// handler verifies before it will act on anything.
	api.POST("/webhooks/razorpay", controllers.RazorpayWebhook)

	// ─── PROTECTED ───────────────────────────────
	protected := api.Group("/")
	protected.Use(middleware.AuthMiddleware())
	{
		protected.GET("/auth/me", controllers.GetMe)
		protected.GET("/dashboard", controllers.GetDashboard)

		// ── FCM device tokens (all roles) ──────
		protected.POST("/fcm/token", controllers.RegisterDeviceToken)
		protected.DELETE("/fcm/token", controllers.UnregisterDeviceToken)

		// Either side of a consultation may cancel a call before the other
		// has answered (see CancelConsultationCall) — not role-gated, since
		// the handler itself checks the caller is actually a participant.
		protected.POST("/consultations/:id/call/cancel", controllers.CancelConsultationCall)

		// ── Subscription & billing ─────────────
		// Entitlement is decided here, not in the app's local storage. These
		// routes sit above the paywall middleware, or an expired firm could
		// never reach the screen that lets them pay.
		protected.GET("/subscription", controllers.GetMySubscription)
		protected.GET("/subscription/payments", controllers.GetSubscriptionPayments)
		protected.GET("/subscription/usage", controllers.GetPlanUsage)
		protected.POST("/subscription/checkout", controllers.CreateSubscriptionCheckout)
		protected.POST("/subscription/activate", controllers.ActivateSubscription)
		protected.POST("/subscription/cancel", controllers.CancelSubscription)

		// The app's change-password screen has always posted here; nothing
		// served it. Both paths are registered because the app calls one and
		// the settings screen the other.
		protected.POST("/users/change-password", controllers.ChangePassword)
		protected.POST("/auth/change-password", controllers.ChangePassword)

		// ── Client Portal ──────────────────────
		portal := protected.Group("/portal")
		{
			portal.GET("/my-cases", controllers.GetMyCases)
			portal.GET("/my-hearings", controllers.GetMyHearings)
			portal.GET("/my-documents", controllers.GetMyDocuments)
			portal.GET("/documents/:id", controllers.GetMyDocument)
			portal.POST("/documents/upload", controllers.UploadDocument)
			portal.GET("/my-invoices", controllers.GetMyInvoices)

			portal.POST("/book-consultation", controllers.BookConsultation)
			// Payment-gated booking (Razorpay). The plain /book-consultation
			// above is left registered but its bookings never reach the lawyer
			// — see the payment_status filter in GetLawyerConsultations — so
			// there is exactly one path to an actual confirmed, paid booking.
			portal.POST("/book-consultation/checkout", controllers.CreateConsultationCheckout)
			portal.POST("/book-consultation/verify", controllers.VerifyConsultationPayment)
			portal.GET("/my-consultations", controllers.GetMyConsultations)
			portal.GET("/my-consultations/:id", controllers.GetConsultation)
			portal.PUT("/my-consultations/:id/cancel", controllers.CancelConsultation)
			portal.POST("/my-consultations/:id/call-response", controllers.RespondToConsultationCall)
			// Symmetric to the lawyer-side /consultations/:id/call below — a
			// client can ring their lawyer the same way.
			portal.POST("/my-consultations/:id/call", controllers.InitiateConsultationCall)
		}

		// ── Court (e-Court — Lawyer Pro / Lawyer Premium only) ──
		court := protected.Group("/court")
		court.Use(middleware.RequirePlanTier("lawyer_pro", "lawyer_premium"))
		{
			court.GET("/cause-list", controllers.GetCauseList)
			court.GET("/case-status", controllers.GetCaseStatus)
			court.POST("/cases/:id/sync", controllers.SyncCaseFromCourt)
			court.GET("/holidays", controllers.GetCourtHolidays)
			court.POST("/holidays", controllers.UpsertCourtHolidays)
		}

		// ── Firm workspace ─────────────────────
		//
		// Everything below sits behind the paywall. The middleware lets every
		// GET through unconditionally, so a firm whose plan lapsed can still
		// open its own case files, read documents and export data — only
		// creating new work is gated. Locking a practice out of its own
		// records over a billing lapse is not an acceptable failure mode.
		//
		// The paywall used to exist only inside the Flutter app, which meant
		// any HTTP client that never ran that code had unlimited free access.
		//
		// RequireFirmStaff comes first. Gating on "has a firm id" alone was not
		// enough: a client portal account carries its lawyer's firm id so the
		// portal can find that client's matters, so clients were passing the
		// firm check and reading the firm's entire client list, staff
		// directory, cases and invoices.
		billed := protected.Group("")
		billed.Use(middleware.RequireFirmStaff())
		billed.Use(middleware.RequireActiveSubscription())
		{
			// ── Clients ────────────────────────
			billed.GET("/clients", controllers.GetClients)
			billed.POST("/clients", controllers.CreateClient)
			billed.GET("/clients/:id", controllers.GetClient)
			billed.PUT("/clients/:id", controllers.UpdateClient)
			billed.DELETE("/clients/:id", controllers.DeleteClient)

			// ── Cases ──────────────────────────
			billed.GET("/cases", controllers.GetCases)
			billed.POST("/cases", controllers.CreateCase)
			billed.GET("/cases/:id", controllers.GetCase)
			billed.PUT("/cases/:id", controllers.UpdateCase)
			billed.DELETE("/cases/:id", controllers.DeleteCase)
			billed.GET("/cases/:id/timeline", controllers.GetCaseTimeline)
			billed.GET("/cases/:id/hearings", controllers.GetCaseHearings)
			billed.GET("/cases/:id/notes", controllers.GetCaseNotes)
			billed.POST("/cases/:id/notes", controllers.AddCaseNote)

			// ── Hearings ───────────────────────
			// /hearings/today is declared before /hearings/:id so the literal
			// segment is unambiguous; registered the other way round, "today"
			// is liable to be captured as an :id and fail the uuid check.
			billed.GET("/hearings", controllers.GetHearings)
			billed.GET("/hearings/today", controllers.GetTodayHearings)
			billed.POST("/hearings", controllers.CreateHearing)
			billed.GET("/hearings/:id", controllers.GetHearing)
			billed.PUT("/hearings/:id", controllers.UpdateHearing)
			billed.DELETE("/hearings/:id", controllers.DeleteHearing)

			// ── Consultations (Lawyer side) ────
			// /consultations/earnings is registered before /consultations/:id
			// so the literal segment isn't captured as an :id — same ordering
			// rule as /hearings/today and /invoices/pending-verification below.
			billed.GET("/consultations/earnings", controllers.GetLawyerEarnings)
			billed.GET("/consultations", controllers.GetLawyerConsultations)
			billed.GET("/consultations/:id", controllers.GetConsultation)
			billed.PUT("/consultations/:id", controllers.UpdateConsultation)
			billed.POST("/consultations/:id/call", controllers.InitiateConsultationCall)
			// Symmetric to the client-side /portal/my-consultations/:id/call-response
			// above — the lawyer can accept/decline a call the client placed.
			billed.POST("/consultations/:id/call-response", controllers.RespondToConsultationCall)

			// ── AI Legal Drafting / Smart Draft AI Tools ──
			billed.POST("/ai/draft", controllers.GenerateDraft)
			billed.POST("/ai/tool", controllers.GenerateAITool)
			billed.POST("/ai/research", controllers.LegalResearch)

			// ── Documents ──────────────────────
			billed.GET("/documents", controllers.GetDocuments)
			billed.POST("/documents/upload", controllers.UploadDocument)
			billed.GET("/documents/:id", controllers.GetDocument)
			billed.DELETE("/documents/:id", controllers.DeleteDocument)

			// ── Billing ────────────────────────
			// Same ordering rule as /hearings: the literal
			// /invoices/pending-verification comes before /invoices/:id.
			billed.GET("/invoices", controllers.GetInvoices)
			billed.GET("/invoices/pending-verification", controllers.GetPendingVerification)
			billed.POST("/invoices", controllers.CreateInvoice)
			billed.GET("/invoices/:id", controllers.GetInvoice)
			billed.PUT("/invoices/:id", controllers.UpdateInvoice)
			billed.GET("/payments", controllers.GetPayments)
			billed.POST("/payments", controllers.CreatePayment)
			billed.POST("/payments/razorpay/order", controllers.CreateRazorpayOrder)
			billed.POST("/payments/razorpay/verify", controllers.VerifyRazorpayPayment)
			billed.PUT("/payments/:id/verify", controllers.VerifyPayment)
		}

		// ── Firm-staff only, not paywalled ─────
		//
		// Same role gate as the workspace above: a client portal account
		// carries its lawyer's firm id, so without this it could read the
		// firm's staff directory, its revenue reports and its bank details.
		// These sit outside the paywall because a firm whose plan lapsed must
		// still be able to see its own numbers and pay us.
		staffOnly := protected.Group("")
		staffOnly.Use(middleware.RequireFirmStaff())
		{
			// ── Firm ───────────────────────────
			staffOnly.GET("/firm/bank-details", controllers.GetFirmBankDetails)
			staffOnly.PUT("/firm/bank-details", controllers.UpdateFirmBankDetails)

			// ── Reports ────────────────────────
			staffOnly.GET("/reports/cases", controllers.GetCaseReport)
			staffOnly.GET("/reports/revenue", controllers.GetRevenueReport)

			// ── Staff ──────────────────────────
			staffOnly.GET("/staff", controllers.GetStaff)
			staffOnly.POST("/staff", controllers.CreateStaff)
			staffOnly.GET("/staff/:id", controllers.GetStaffMember)
			staffOnly.PUT("/staff/:id", controllers.UpdateStaffMember)
		}

		// ── Notifications ──────────────────────
		// Scoped to the caller's own user id, so every role may use these.
		protected.GET("/notifications", controllers.GetNotifications)
		protected.PUT("/notifications/:id/read", controllers.MarkNotificationRead)

		// ── Chat ───────────────────────────────
		protected.GET("/chat/rooms", controllers.GetChatRooms)
		protected.POST("/chat/rooms", controllers.CreateChatRoom)
		protected.GET("/chat/rooms/:room_id/messages", controllers.GetMessages)
		protected.POST("/chat/rooms/:room_id/messages", controllers.SendMessage)
		protected.DELETE("/chat/messages/:message_id", controllers.DeleteMessage)
		protected.GET("/chat/unread", controllers.GetUnreadCount)

		// ── Student ────────────────────────────
		protected.GET("/student/lawyers", controllers.GetAllLawyers)
		protected.GET("/student/lawyer/:id", controllers.GetLawyerProfile)
		protected.GET("/student/progress", controllers.GetStudentProgress)
		protected.GET("/student/leaderboard", controllers.GetLeaderboard)

		// ── AI Legal Advisor (student panel) ───
		protected.POST("/ai/legal-advisor", controllers.AdvisorChat)
		protected.POST("/ai/quiz", controllers.GenerateQuiz)
		protected.POST("/ai/mock-court/case", controllers.GenerateMockCase)
		protected.POST("/ai/mock-court/evaluate", controllers.EvaluateMockCourt)

		// ── Challenges ─────────────────────────
		protected.POST("/challenges/generate", controllers.GenerateChallenge)
		protected.POST("/challenges/:id/submit", controllers.SubmitChallenge)
		protected.GET("/challenges/:id", controllers.GetChallenge)

		// ── Admin ──────────────────────────────
		//
		// These are PLATFORM-wide endpoints: they list every user on the
		// service, suspend or delete arbitrary accounts, and report total
		// revenue across all firms.
		//
		// The guard used to be RoleMiddleware("admin", "super_admin"), but
		// "admin" is the role handed to every lawyer who signs up — see
		// Register. That made each customer a platform administrator, able to
		// read every other firm's user list and deactivate their accounts.
		// Only the platform owner belongs here.
		admin := protected.Group("/admin")
		admin.Use(middleware.RoleMiddleware("super_admin"))
		{
			// ✅ Existing
			admin.GET("/audit-logs", controllers.GetAuditLogs)

			// ✅ User Management (Suspend / Activate / Delete)
			admin.GET("/users", controllers.AdminGetUsers)
			admin.PUT("/users/:id", controllers.AdminUpdateUser)
			admin.DELETE("/users/:id", controllers.AdminDeleteUser)

			// ✅ Stats & Dashboard
			admin.GET("/stats", controllers.AdminGetStats)

			// ✅ Lawyers
			admin.GET("/lawyers", controllers.AdminGetLawyers)
			admin.GET("/lawyers/:id/document", controllers.AdminGetLawyerDocument)
			admin.PUT("/lawyers/:id/verify", controllers.AdminVerifyLawyer)

			// ✅ Subscriptions & Revenue
			admin.GET("/subscriptions", controllers.AdminGetSubscriptions)
			admin.GET("/revenue", controllers.AdminGetRevenue)
		}
	}

	return r
}
