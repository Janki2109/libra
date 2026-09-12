import 'dart:async';
import 'package:go_router/go_router.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/splash/screens/splash_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/auth/screens/client_register_screen.dart';
import '../../features/auth/screens/student_register_screen.dart';
import '../../features/auth/screens/onboarding_screen.dart';
import '../../features/auth/screens/subscription_screen.dart';
import '../../features/auth/screens/subscription_wall_screen.dart';
import '../../features/dashboard/screens/dashboard_screen.dart';
import '../../features/student/screens/legal_challenge_screen.dart';
import '../../features/student/screens/news_tab.dart';
import '../../features/student/screens/ai_lawyer_screen.dart';
import '../../features/student/screens/law_books_screen.dart';
import '../../features/student/screens/leaderboard_screen.dart';
import '../../features/student/screens/news_webview_screen.dart';
import '../../features/dashboard/screens/law_student_dashboard_screen.dart';
import '../../features/clients/screens/client_list_screen.dart';
import '../../features/clients/screens/add_client_screen.dart';
import '../../features/clients/screens/client_details_screen.dart';
import '../../features/cases/screens/case_list_screen.dart';
import '../../features/cases/screens/add_case_screen.dart';
import '../../features/cases/screens/case_details_screen.dart';
import '../../features/hearings/screens/hearing_list_screen.dart';
import '../../features/hearings/screens/add_hearing_screen.dart';
import '../../features/documents/screens/document_list_screen.dart';
import '../../features/billing/screens/billing_list_screen.dart';
import '../../features/billing/screens/create_invoice_screen.dart';
import '../../features/billing/screens/payment_screen.dart';
import '../../features/billing/screens/payment_verification_screen.dart';
import '../../features/notifications/screens/notifications_screen.dart';
import '../../features/reports/screens/reports_screen.dart';
import '../../features/staff/screens/staff_list_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/profile/screens/settings_screen.dart';
import '../../features/admin/screens/admin_dashboard_screen.dart';
import '../../features/client_portal/screens/portal_dashboard_screen.dart';
import '../../features/client_portal/screens/portal_case_screen.dart';
import '../../features/client_portal/screens/portal_invoices_screen.dart';
import '../../features/client_portal/screens/portal_documents_screen.dart';
import '../../features/client_portal/screens/incoming_call_screen.dart';
import '../../features/calls/screens/call_screen.dart';
import '../../features/client_portal/screens/portal_messages_screen.dart';
import '../../features/client_portal/screens/find_lawyer_screen.dart';
import '../../features/client_portal/screens/book_consultation_screen.dart';
import '../../features/client_portal/screens/consultation_history_screen.dart';
import '../../features/calendar/screens/calendar_screen.dart';
import '../../features/billing/screens/invoice_details_screen.dart';
import '../../features/billing/screens/payment_history_screen.dart';
import '../../features/hearings/screens/hearing_details_screen.dart';
import '../../features/clients/screens/edit_client_screen.dart';
import '../../features/cases/screens/edit_case_screen.dart';
import '../../features/profile/screens/edit_profile_screen.dart';
import '../../features/cases/screens/case_timeline_screen.dart';
import '../../features/cases/screens/case_documents_screen.dart';
import '../../features/documents/screens/upload_document_screen.dart';
import '../../features/documents/screens/view_document_screen.dart';
import '../../features/staff/screens/add_staff_screen.dart';
import '../../features/auth/screens/otp_screen.dart';
import '../../features/profile/screens/change_password_screen.dart';
import '../../features/admin/screens/admin_users_screen.dart';
import '../../features/admin/screens/admin_audit_screen.dart';
import '../../features/admin/screens/admin_verify_lawyers_screen.dart';
import '../../features/admin/screens/admin_subscriptions_screen.dart';
import '../../features/admin/screens/admin_revenue_screen.dart';
import '../../features/admin/screens/admin_lawyers_screen.dart';
import '../../features/admin/screens/admin_students_screen.dart';
import '../../features/admin/screens/admin_clients_screen.dart';
import '../../features/admin/screens/admin_consultations_screen.dart';
import '../../features/admin/screens/admin_payments_screen.dart';
import '../../features/admin/screens/admin_lawyer_earnings_screen.dart';
import '../../features/admin/screens/admin_documents_screen.dart';
import '../../features/admin/screens/admin_cases_screen.dart';
import '../../features/admin/screens/admin_hearings_screen.dart';
import '../../features/admin/screens/admin_notifications_screen.dart';
import '../../features/chat/screens/chat_list_screen.dart';
import '../../features/chat/screens/chat_screen.dart';
import '../../features/student/screens/lawyer_profile_screen.dart';
import '../../features/lawyer/screens/ai_legal_research_screen.dart';
import '../../features/lawyer/screens/research_history_screen.dart';
import '../../features/lawyer/screens/ai_drafting_screen.dart';
import '../../features/lawyer/screens/ecourts_screen.dart';
import '../../features/lawyer/screens/consultation_management_screen.dart';
import '../../features/earnings/screens/lawyer_earnings_screen.dart';
import '../../features/earnings/screens/bill_details_screen.dart';
import '../../features/student/screens/legal_notes_screen.dart';
import '../../features/student/screens/quiz_screen.dart';
import '../../features/student/screens/mock_court_screen.dart';
import '../../features/student/screens/certificate_screen.dart';

class AppRouter {
  // Lets code outside the widget tree (the FCM notification-tap handler)
  // navigate without needing a BuildContext of its own. A plain object
  // reference to whichever GoRouter is currently active — NOT a GlobalKey,
  // since a new GoRouter is constructed on every auth-state change here and
  // a GlobalKey shared across the old/new Navigator during that swap caused
  // a duplicate-GlobalKey error that dropped users back on the splash screen
  // after registering.
  static GoRouter? current;

  // main() awaits FcmService.instance.initialize() (which checks
  // getInitialMessage() for a cold start from a tapped notification, e.g. an
  // incoming call) *before* calling runApp() — so `current` above is still
  // null at that point; a `current?.push(...)` from that cold-start check
  // would silently no-op. FcmService awaits this instead so that navigation
  // is only attempted once `current` actually exists, fixing incoming-call
  // (and plain notification) taps that launch the app from a terminated
  // state.
  static final Completer<void> _ready = Completer<void>();
  static Future<void> get ready => _ready.future;

  // Root cause of the "onboarding/splash reappears" bug: this used to build
  // a brand new GoRouter (fresh initialLocation: '/splash') every single time
  // it was called — and it was being called on every AuthProvider
  // notifyListeners(), including the "_loading = true" fired at the start of
  // login()/register(). That reset navigation back to '/splash' mid-flow,
  // whose own 3-second timer then routed to '/onboarding' once it elapsed.
  // GoRouter already reacts to auth changes via `refreshListenable: auth`
  // below, so it only ever needs to be constructed once.
  static GoRouter router(AuthProvider auth) {
    if (current != null) return current!;
    final router = GoRouter(
      initialLocation: '/splash',
      refreshListenable: auth,
      redirect: (context, state) {
        final isAuth = auth.status == AuthStatus.authenticated;
        final isUnknown = auth.status == AuthStatus.unknown;
        final loc = state.matchedLocation;

        // Public routes that don't require login
        final publicRoutes = [
          '/splash',
          '/onboarding',
          '/login',
          '/register',
          '/client/register',
          '/student/register',
          // Reachable from the Login screen before the user is signed in —
          // without this, the redirect below bounced it straight back to
          // /login on every tap, which is why "Forgot Password?" looked
          // like it did nothing at all.
          '/forgot-password',
        ];

        // Still loading session
        if (isUnknown) return '/splash';

        // Not logged in → send to login
        if (!isAuth && !publicRoutes.contains(loc)) return '/login';

        final role = isAuth ? (auth.user?.roleName ?? '') : '';

        // Admin routes are super_admin only. The backend's
        // RoleMiddleware("super_admin") is the real enforcement — every
        // /admin/* API 403s for anyone else regardless of what the frontend
        // does — but without this check, a Lawyer/Student/Client could still
        // navigate straight to an /admin/... URL and see the admin shell
        // itself (just with every request in it failing). This sends any
        // non-admin role away before that shell ever renders.
        if (loc.startsWith('/admin') && role != 'super_admin') {
          if (!isAuth) return '/login';
          if (role == 'client') return '/portal/dashboard';
          if (role == 'law_student') return '/student/dashboard';
          return '/dashboard';
        }

        // Logged in → redirect away from public routes to dashboard
        if (isAuth && publicRoutes.contains(loc)) {
          if (role == 'super_admin') return '/admin';
          if (role == 'client') return '/portal/dashboard';
          if (role == 'law_student') return '/student/dashboard';
          return '/dashboard';
        }

        return null;
      },
      routes: [
        // ─── PUBLIC ──────────────────────────
        GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
        GoRoute(
            path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
        GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
        GoRoute(
            path: '/forgot-password',
            builder: (_, __) => const ForgotPasswordScreen()),
        GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
        GoRoute(
            path: '/client/register',
            builder: (_, __) => const ClientRegisterScreen()),
        GoRoute(
            path: '/student/register',
            builder: (_, __) => const StudentRegisterScreen()),
        GoRoute(
            path: '/subscription',
            builder: (_, __) => const SubscriptionScreen()),
        GoRoute(
            path: '/subscription-wall',
            builder: (_, __) => const SubscriptionWallScreen()),

        // ─── DASHBOARDS ──────────────────────
        GoRoute(
            path: '/dashboard', builder: (_, __) => const DashboardScreen()),
        GoRoute(
            path: '/portal/dashboard',
            builder: (_, __) => const PortalDashboardScreen()),
        GoRoute(
            path: '/student/dashboard',
            builder: (_, __) => const LawStudentDashboardScreen()),
        GoRoute(
            path: '/challenge',
            builder: (_, __) => const LegalChallengeScreen()),
        GoRoute(
            path: '/student/challenge',
            builder: (_, __) => const LegalChallengeScreen()),
        GoRoute(path: '/student/news', builder: (_, __) => const NewsScreen()),
        GoRoute(
            path: '/student/ai-lawyer',
            builder: (_, __) => const AILawyerScreen()),
        GoRoute(
            path: '/student/law-books',
            builder: (_, __) => const LawBooksScreen()),
        GoRoute(
            path: '/student/leaderboard',
            builder: (_, __) => const LeaderboardScreen()),
        GoRoute(
          path: '/student/news-detail',
          builder: (_, state) => NewsWebViewScreen(
            url: state.uri.queryParameters['url'] ?? '',
            title: state.uri.queryParameters['title'] ?? '',
            source: state.uri.queryParameters['source'] ?? '',
          ),
        ),
        GoRoute(
          path: '/student/lawyer/:id',
          builder: (_, state) => LawyerProfileScreen(
            lawyerId: state.pathParameters['id']!,
            lawyerName: state.uri.queryParameters['name'] ?? '',
          ),
        ),

        // ─── CLIENT PORTAL ───────────────────
        GoRoute(
            path: '/portal/find-lawyer',
            builder: (_, __) => const FindLawyerScreen()),
        GoRoute(
          path: '/portal/lawyer/:id',
          builder: (_, state) => LawyerProfileScreen(
            lawyerId: state.pathParameters['id']!,
            lawyerName: state.uri.queryParameters['name'] ?? '',
            fromClientPortal: true,
          ),
        ),
        GoRoute(
          path: '/portal/book-consultation/:lawyerId',
          builder: (_, state) => BookConsultationScreen(
            lawyerId: state.pathParameters['lawyerId']!,
            lawyerName: state.uri.queryParameters['name'] ?? '',
          ),
        ),
        GoRoute(
            path: '/portal/consultation-history',
            builder: (_, __) => const ConsultationHistoryScreen()),
        GoRoute(
            path: '/portal/cases',
            builder: (_, __) => const PortalCaseScreen()),
        GoRoute(
            path: '/portal/invoices',
            builder: (_, __) => const PortalInvoicesScreen()),
        GoRoute(
            path: '/portal/documents',
            builder: (_, __) => const PortalDocumentsScreen()),
        GoRoute(
            path: '/portal/messages',
            builder: (_, __) => const PortalMessagesScreen()),
        GoRoute(
          path: '/portal/payment/:invoiceId',
          builder: (_, state) => PaymentScreen(
            invoiceId: state.pathParameters['invoiceId']!,
            amount: double.parse(state.uri.queryParameters['amount'] ?? '0'),
            invoiceNumber: state.uri.queryParameters['invoice'] ?? '',
          ),
        ),

        // ─── COURT ───────────────────────────
        GoRoute(path: '/calendar', builder: (_, __) => const CalendarScreen()),

        // ─── CHAT ────────────────────────────
        GoRoute(path: '/chat', builder: (_, __) => const ChatListScreen()),
        GoRoute(
          path: '/incoming-call',
          builder: (_, state) {
            final extra = state.extra as Map<String, dynamic>? ?? {};
            return IncomingCallScreen(
              consultationId: extra['consultationId'] ?? '',
              callType: extra['callType'] ?? 'audio',
              lawyerName: extra['lawyerName'] ?? 'Your Lawyer',
            );
          },
        ),
        GoRoute(
          path: '/call',
          builder: (_, state) {
            final extra = state.extra as Map<String, dynamic>? ?? {};
            return CallScreen(
              consultationId: extra['consultationId'] ?? '',
              peerName: extra['peerName'] ?? 'User',
              video: extra['video'] == true,
              isCaller: extra['isCaller'] == true,
            );
          },
        ),
        GoRoute(
          path: '/chat/:roomId',
          builder: (_, state) => ChatScreen(
            roomId: state.pathParameters['roomId']!,
            roomName: state.uri.queryParameters['name'] ?? 'Chat',
          ),
        ),

        // ─── CLIENTS ─────────────────────────
        GoRoute(path: '/clients', builder: (_, __) => const ClientListScreen()),
        GoRoute(
            path: '/clients/add', builder: (_, __) => const AddClientScreen()),
        GoRoute(
          path: '/clients/:id',
          builder: (_, state) =>
              ClientDetailsScreen(clientId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/clients/:id/edit',
          builder: (_, state) =>
              EditClientScreen(clientId: state.pathParameters['id']!),
        ),

        // ─── CASES ───────────────────────────
        GoRoute(path: '/cases', builder: (_, __) => const CaseListScreen()),
        GoRoute(
          path: '/cases/add',
          builder: (_, state) {
            final extra = state.extra as Map<String, dynamic>? ?? {};
            return AddCaseScreen(
              initialClientId: extra['clientId'] as String?,
              initialClientName: extra['clientName'] as String?,
            );
          },
        ),
        GoRoute(
          path: '/cases/:id',
          builder: (_, state) =>
              CaseDetailsScreen(caseId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/cases/:id/edit',
          builder: (_, state) =>
              EditCaseScreen(caseId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/cases/:id/timeline',
          builder: (_, state) =>
              CaseTimelineScreen(caseId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/cases/:id/documents',
          builder: (_, state) =>
              CaseDocumentsScreen(caseId: state.pathParameters['id']!),
        ),

        // ─── HEARINGS ────────────────────────
        GoRoute(
            path: '/hearings', builder: (_, __) => const HearingListScreen()),
        GoRoute(
          path: '/hearings/add',
          builder: (_, state) {
            final extra = state.extra as Map<String, dynamic>? ?? {};
            return AddHearingScreen(initialCaseId: extra['caseId'] as String?);
          },
        ),
        GoRoute(
          path: '/hearings/:id',
          builder: (_, state) =>
              HearingDetailsScreen(hearingId: state.pathParameters['id']!),
        ),

        // ─── DOCUMENTS ───────────────────────
        GoRoute(
            path: '/documents', builder: (_, __) => const DocumentListScreen()),
        GoRoute(
            path: '/documents/upload',
            builder: (_, __) => const UploadDocumentScreen()),
        GoRoute(
          path: '/documents/:id',
          builder: (_, state) =>
              ViewDocumentScreen(documentId: state.pathParameters['id']!),
        ),

        // ─── BILLING ─────────────────────────
        GoRoute(
            path: '/billing', builder: (_, __) => const BillingListScreen()),
        GoRoute(
            path: '/billing/create',
            builder: (_, __) => const CreateInvoiceScreen()),
        GoRoute(
            path: '/billing/verify',
            builder: (_, __) => const PaymentVerificationScreen()),
        GoRoute(
          path: '/billing/:id',
          builder: (_, state) =>
              InvoiceDetailsScreen(invoiceId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/billing/pay/:invoiceId',
          builder: (_, state) => PaymentScreen(
            invoiceId: state.pathParameters['invoiceId']!,
            amount: double.parse(state.uri.queryParameters['amount'] ?? '0'),
            invoiceNumber: state.uri.queryParameters['invoice'] ?? '',
          ),
        ),
        GoRoute(
            path: '/payments/history',
            builder: (_, __) => const PaymentHistoryScreen()),

        // ─── AUTH EXTRAS ─────────────────────
        GoRoute(path: '/otp', builder: (_, __) => const OtpScreen()),

        // ─── MISC ────────────────────────────
        GoRoute(
            path: '/notifications',
            builder: (_, __) => const NotificationsScreen()),
        GoRoute(path: '/reports', builder: (_, __) => const ReportsScreen()),

        // ─── STAFF ───────────────────────────
        GoRoute(path: '/staff', builder: (_, __) => const StaffListScreen()),
        GoRoute(path: '/staff/add', builder: (_, __) => const AddStaffScreen()),

        // ─── PROFILE ─────────────────────────
        GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
        GoRoute(
            path: '/profile/edit',
            builder: (_, __) => const EditProfileScreen()),
        GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
        GoRoute(
            path: '/profile/change-password',
            builder: (_, __) => const ChangePasswordScreen()),

        // ─── STUDENT FEATURES ────────────────────────────
        GoRoute(
            path: '/student/notes',
            builder: (_, __) => const LegalNotesScreen()),
        GoRoute(path: '/student/quiz', builder: (_, __) => const QuizScreen()),
        GoRoute(
            path: '/student/mock-court',
            builder: (_, __) => const MockCourtScreen()),
        GoRoute(
            path: '/student/certificates',
            builder: (_, __) => const CertificateScreen()),

        // ─── LAWYER AI TOOLS ─────────────────────────
        GoRoute(
            path: '/lawyer/ai-research',
            builder: (_, __) => const AILegalResearchScreen()),
        GoRoute(
            path: '/lawyer/ai-research/history',
            builder: (_, __) => const ResearchHistoryScreen()),
        GoRoute(
            path: '/lawyer/ai-research/history/:id',
            builder: (_, state) => ResearchHistoryDetailScreen(
                id: state.pathParameters['id']!)),
        GoRoute(
            path: '/lawyer/ai-drafting',
            builder: (_, __) => const AIDraftingScreen()),
        GoRoute(
            path: '/lawyer/ecourts', builder: (_, __) => const EcourtsScreen()),
        GoRoute(
            path: '/lawyer/consultations',
            builder: (_, __) => const ConsultationManagementScreen()),
        // Bottom-nav Billing tab: the lawyer's consultation-earnings ledger.
        // Distinct from '/billing' (firm invoicing) already registered above.
        GoRoute(
            path: '/lawyer/earnings',
            builder: (_, __) => const LawyerEarningsScreen()),
        GoRoute(
            path: '/lawyer/earnings/:id',
            builder: (_, state) => BillDetailsScreen(
                consultationId: state.pathParameters['id']!)),

        // ─── ADMIN ───────────────────────────
        GoRoute(
            path: '/admin', builder: (_, __) => const AdminDashboardScreen()),
        GoRoute(
            path: '/admin/users', builder: (_, __) => const AdminUsersScreen()),
        GoRoute(
            path: '/admin/audit', builder: (_, __) => const AdminAuditScreen()),
        GoRoute(
            path: '/admin/verify-lawyers',
            builder: (_, __) => const AdminVerifyLawyersScreen()),
        GoRoute(
            path: '/admin/subscriptions',
            builder: (_, __) => const AdminSubscriptionsScreen()),
        GoRoute(
            path: '/admin/revenue',
            builder: (_, __) => const AdminRevenueScreen()),
        GoRoute(
            path: '/admin/lawyers',
            builder: (_, __) => const AdminLawyersScreen()),
        GoRoute(
            path: '/admin/students',
            builder: (_, __) => const AdminStudentsScreen()),
        GoRoute(
            path: '/admin/clients',
            builder: (_, __) => const AdminClientsScreen()),
        GoRoute(
            path: '/admin/consultations',
            builder: (_, __) => const AdminConsultationsScreen()),
        GoRoute(
            path: '/admin/payments',
            builder: (_, __) => const AdminPaymentsScreen()),
        GoRoute(
            path: '/admin/lawyer-earnings',
            builder: (_, __) => const AdminLawyerEarningsScreen()),
        GoRoute(
            path: '/admin/documents',
            builder: (_, __) => const AdminDocumentsScreen()),
        GoRoute(
            path: '/admin/cases', builder: (_, __) => const AdminCasesScreen()),
        GoRoute(
            path: '/admin/hearings',
            builder: (_, __) => const AdminHearingsScreen()),
        GoRoute(
            path: '/admin/notifications',
            builder: (_, __) => const AdminNotificationsScreen()),
      ],
    );
    current = router;
    if (!_ready.isCompleted) _ready.complete();
    return router;
  }
}
