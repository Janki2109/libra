import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/router/app_router.dart';
import 'core/services/dio_client.dart';
import 'core/services/fcm_service.dart';
import 'core/services/auto_refresh_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/dashboard/providers/dashboard_provider.dart';
import 'features/clients/providers/client_provider.dart';
import 'features/cases/providers/case_provider.dart';
import 'features/hearings/providers/hearing_provider.dart';
import 'features/notifications/providers/notification_provider.dart';
import 'features/chat/providers/chat_unread_provider.dart';
import 'features/billing/providers/billing_provider.dart';
import 'features/documents/providers/document_provider.dart';
import 'features/client_portal/providers/portal_provider.dart';
import 'features/reports/providers/report_provider.dart';
import 'features/staff/providers/staff_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  await FcmService.instance.initialize();
  runApp(const LibraApp());
}

class LibraApp extends StatelessWidget {
  const LibraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => DashboardProvider()),
        ChangeNotifierProvider(create: (_) => ClientProvider()),
        ChangeNotifierProvider(create: (_) => CaseProvider()),
        ChangeNotifierProvider(create: (_) => HearingProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        ChangeNotifierProvider(create: (_) => ChatUnreadProvider()),
        ChangeNotifierProvider(create: (_) => BillingProvider()),
        ChangeNotifierProvider(create: (_) => DocumentProvider()),
        ChangeNotifierProvider(create: (_) => PortalProvider()),
        ChangeNotifierProvider(create: (_) => ReportProvider()),
        ChangeNotifierProvider(create: (_) => StaffProvider()),
      ],
      child: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          // Route any 401 from the API back into the auth state, so an expired
          // session sends the user to the login screen instead of leaving them
          // on a silently empty dashboard.
          DioClient.onUnauthorized = auth.onSessionExpired;

          return _AutoRefreshGate(
            isAuthenticated: auth.isAuthenticated,
            child: MaterialApp.router(
              title: 'Libra Law Practice',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: ThemeMode.dark, // ✅ Always dark
              routerConfig: AppRouter.router(auth),
              // Only reached once go_router's own Navigator has nothing left
              // to pop — i.e. the system/gesture back press would otherwise
              // exit the app outright with no warning. In-app back navigation
              // elsewhere is untouched; this never intercepts a pop that a
              // screen further down the stack can still handle itself.
              //
              // An authenticated user lands here exactly when they're on their
              // role's root dashboard (login/registration replace the whole
              // stack via context.go(), so the dashboard sits at the bottom
              // with nothing beneath it) — back must never exit or log them
              // out from there, just stay put, per the "no accidental exit for
              // a logged-in user" requirement. Logout is a separate, explicit
              // action (see each role's own Logout confirmation), never a side
              // effect of the back button. The pre-login "Exit app?" prompt
              // (splash/onboarding/login/register) is unchanged.
              builder: (context, child) => PopScope(
                canPop: false,
                onPopInvokedWithResult: (didPop, _) async {
                  if (didPop) return;
                  if (auth.isAuthenticated) return;
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Exit app?'),
                      content:
                          const Text('Are you sure you want to exit the app?'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel')),
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Exit')),
                      ],
                    ),
                  );
                  if (confirmed == true) SystemNavigator.pop();
                },
                child: child!,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Starts/stops the single global [AutoRefreshService] timer in response to
/// auth state and app lifecycle — the two conditions the spec calls out:
/// "every 3 seconds while the app is active/in foreground" and "stop all
/// timers immediately on logout".
class _AutoRefreshGate extends StatefulWidget {
  final bool isAuthenticated;
  final Widget child;
  const _AutoRefreshGate({required this.isAuthenticated, required this.child});

  @override
  State<_AutoRefreshGate> createState() => _AutoRefreshGateState();
}

class _AutoRefreshGateState extends State<_AutoRefreshGate>
    with WidgetsBindingObserver {
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sync();
  }

  @override
  void didUpdateWidget(_AutoRefreshGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isAuthenticated != widget.isAuthenticated) _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  void _sync() {
    if (widget.isAuthenticated && _foreground) {
      AutoRefreshService.instance.start();
    } else {
      AutoRefreshService.instance.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AutoRefreshService.instance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
