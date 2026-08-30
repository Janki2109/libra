import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/router/app_router.dart';
import 'core/services/dio_client.dart';
import 'core/services/fcm_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/dashboard/providers/dashboard_provider.dart';
import 'features/clients/providers/client_provider.dart';
import 'features/cases/providers/case_provider.dart';
import 'features/hearings/providers/hearing_provider.dart';
import 'features/notifications/providers/notification_provider.dart';
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

          return MaterialApp.router(
            title: 'Libra Law Practice',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: ThemeMode.dark, // ✅ Always dark
            routerConfig: AppRouter.router(auth),
          );
        },
      ),
    );
  }
}
