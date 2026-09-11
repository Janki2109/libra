import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../providers/auth_provider.dart';

// The hidden super-admin backdoor that used to live here has been removed.
//
// It compared the typed email and password against two constants compiled
// into the app — `jayashri@jayashrigroups.com` / `password` — and on a match
// fabricated a super_admin session locally, bypassing the API entirely. Anyone
// who downloaded the APK could recover both strings with `strings` on the
// binary and walk into the platform admin panel.
//
// A platform owner signs in through the normal login below, against the
// super_admin account seeded via database/seeds/seed_roles.sql, and the API
// decides their role.

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _lawyerEmailCtrl = TextEditingController();
  final _lawyerPassCtrl = TextEditingController();
  final _clientEmailCtrl = TextEditingController();
  final _clientPassCtrl = TextEditingController();
  final _studentEmailCtrl = TextEditingController();
  final _studentPassCtrl = TextEditingController();
  bool _lawyerObscure = true;
  bool _clientObscure = true;
  bool _studentObscure = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _lawyerEmailCtrl.dispose();
    _lawyerPassCtrl.dispose();
    _clientEmailCtrl.dispose();
    _clientPassCtrl.dispose();
    _studentEmailCtrl.dispose();
    _studentPassCtrl.dispose();
    super.dispose();
  }

  // ── Super Admin check ──────────────────────────
  Future<void> _lawyerLogin() async {
    if (_lawyerEmailCtrl.text.isEmpty || _lawyerPassCtrl.text.isEmpty) {
      _showError('Please enter email and password');
      return;
    }
    HapticFeedback.lightImpact();

    final auth = context.read<AuthProvider>();
    final success =
        await auth.login(_lawyerEmailCtrl.text.trim(), _lawyerPassCtrl.text);
    if (success && mounted) {
      HapticFeedback.heavyImpact();
      // A platform owner authenticates through this same call; the API's role
      // claim decides where they land.
      context.go(auth.user?.roleName == 'super_admin' ? '/admin' : '/dashboard');
    } else if (mounted) {
      _showError(auth.error ?? 'Login failed. Check email & password.');
    }
  }

  Future<void> _clientLogin() async {
    if (_clientEmailCtrl.text.isEmpty || _clientPassCtrl.text.isEmpty) {
      _showError('Please enter email and password');
      return;
    }
    HapticFeedback.lightImpact();

    final auth = context.read<AuthProvider>();
    final success = await auth.portalLogin(
        _clientEmailCtrl.text.trim(), _clientPassCtrl.text);
    if (success && mounted) {
      HapticFeedback.heavyImpact();
      context.go('/portal/dashboard');
    } else if (mounted) {
      _showError(auth.error ?? 'Login failed. Check email & password.');
    }
  }

  Future<void> _studentLogin() async {
    if (_studentEmailCtrl.text.isEmpty || _studentPassCtrl.text.isEmpty) {
      _showError('Please enter email and password');
      return;
    }
    HapticFeedback.lightImpact();

    final auth = context.read<AuthProvider>();
    final success =
        await auth.login(_studentEmailCtrl.text.trim(), _studentPassCtrl.text);
    if (success && mounted) {
      HapticFeedback.heavyImpact();
      context.go('/student/dashboard');
    } else if (mounted) {
      _showError(auth.error ?? 'Login failed. Check email & password.');
    }
  }

  void _showError(String msg) {
    HapticFeedback.vibrate();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.error_rounded, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(msg)),
      ]),
      backgroundColor: AppColors.error,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 3),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
            child: Column(children: [
          const SizedBox(height: 24),
          // Logo — a refined "O" ring with a scales-of-justice mark inside,
          // matching the OneLegal splash screen's mark instead of Libra's
          // solid gold-filled circle.
          Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.bgCard,
                  border: Border.all(color: AppColors.gold, width: 1.6),
                  boxShadow: [
                    BoxShadow(
                        color: AppColors.gold.withValues(alpha: 0.28),
                        blurRadius: 18,
                        spreadRadius: 2)
                  ]),
              child: ClipOval(
                  child: Image.asset('assets/logo/app logo.png',
                      width: 68, height: 68, fit: BoxFit.cover))),
          const SizedBox(height: 12),
          RichText(
              text: const TextSpan(children: [
            TextSpan(
                text: 'ONE',
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 4)),
            TextSpan(
                text: 'LEGAL',
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: AppColors.gold,
                    letterSpacing: 4)),
          ])),
          const SizedBox(height: 4),
          const Text('One Platform. Every Legal Need.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
          const SizedBox(height: 20),

          // Tab Bar
          Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14)),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                    color: AppColors.gold,
                    borderRadius: BorderRadius.circular(10)),
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textMuted,
                labelStyle:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                        Icon(Icons.gavel_rounded, size: 14),
                        SizedBox(width: 4),
                        Text('Lawyer')
                      ])),
                  Tab(
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                        Icon(Icons.person_rounded, size: 14),
                        SizedBox(width: 4),
                        Text('Client')
                      ])),
                  Tab(
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                        Icon(Icons.school_rounded, size: 14),
                        SizedBox(width: 4),
                        Text('Student')
                      ])),
                ],
              )),
          const SizedBox(height: 16),

          // Tab Views
          Expanded(
              child: TabBarView(controller: _tabController, children: [
            _buildLoginCard(
                title: 'Welcome Back, Advocate!',
                subtitle: 'Sign in to manage your practice',
                accentColor: AppColors.gold,
                emailCtrl: _lawyerEmailCtrl,
                passCtrl: _lawyerPassCtrl,
                obscure: _lawyerObscure,
                onToggle: () =>
                    setState(() => _lawyerObscure = !_lawyerObscure),
                onLogin: auth.loading ? null : _lawyerLogin,
                loading: auth.loading,
                registerText: 'New law firm?',
                registerLabel: 'Create Firm Account',
                onRegister: () => context.go('/register'),
                buttonLabel: 'Sign In as Lawyer'),
            _buildLoginCard(
                title: 'Client Portal',
                subtitle: 'Access your cases & documents',
                accentColor: AppColors.info,
                emailCtrl: _clientEmailCtrl,
                passCtrl: _clientPassCtrl,
                obscure: _clientObscure,
                onToggle: () =>
                    setState(() => _clientObscure = !_clientObscure),
                onLogin: auth.loading ? null : _clientLogin,
                loading: auth.loading,
                registerText: 'New client?',
                registerLabel: 'Create Account',
                onRegister: () => context.go('/client/register'),
                buttonLabel: 'Sign In as Client',
                buttonColor: AppColors.info,
                buttonTextColor: Colors.white),
            _buildLoginCard(
                title: 'Law Student Portal',
                subtitle: 'Learn, practice & grow',
                accentColor: AppColors.purple,
                emailCtrl: _studentEmailCtrl,
                passCtrl: _studentPassCtrl,
                obscure: _studentObscure,
                onToggle: () =>
                    setState(() => _studentObscure = !_studentObscure),
                onLogin: auth.loading ? null : _studentLogin,
                loading: auth.loading,
                registerText: 'New student?',
                registerLabel: 'Create Student Account',
                onRegister: () => context.go('/student/register'),
                buttonLabel: 'Sign In as Student',
                buttonColor: AppColors.purple,
                buttonTextColor: Colors.white),
          ])),

          const Padding(
              padding: EdgeInsets.all(12),
              child: Text('© 2024 OneLegal',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 10))),
        ])),
      ),
    );
  }

  Widget _buildLoginCard({
    required String title,
    required String subtitle,
    required Color accentColor,
    required TextEditingController emailCtrl,
    required TextEditingController passCtrl,
    required bool obscure,
    required VoidCallback onToggle,
    required VoidCallback? onLogin,
    required bool loading,
    required String registerText,
    required String registerLabel,
    required VoidCallback onRegister,
    required String buttonLabel,
    Color? buttonColor,
    Color? buttonTextColor,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.borderGold),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 6)),
            ]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: TextStyle(
                  color: accentColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(subtitle,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          const SizedBox(height: 20),

          // Email
          TextField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                  labelText: 'Email Address',
                  labelStyle: const TextStyle(color: AppColors.textMuted),
                  prefixIcon:
                      Icon(Icons.email_outlined, color: accentColor, size: 20),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.border)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.border)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: accentColor)))),
          const SizedBox(height: 12),

          // Password
          TextField(
              controller: passCtrl,
              obscureText: obscure,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                  labelText: 'Password',
                  labelStyle: const TextStyle(color: AppColors.textMuted),
                  prefixIcon:
                      Icon(Icons.lock_outline, color: accentColor, size: 20),
                  suffixIcon: IconButton(
                      icon: Icon(
                          obscure ? Icons.visibility_off : Icons.visibility,
                          color: AppColors.textMuted,
                          size: 20),
                      onPressed: onToggle),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.border)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.border)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: accentColor))),
              onSubmitted: (_) => onLogin?.call()),
          const SizedBox(height: 8),

          // Forgot Password — same for all three tabs (Lawyer/Client/
          // Student), since this one shared card builds all of them.
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () => context.push('/forgot-password'),
              child: const Text('Forgot Password?',
                  style: TextStyle(
                      color: AppColors.gold,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 12),

          // Login Button
          SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                  onPressed: onLogin,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: buttonColor ?? AppColors.gold,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  child: loading
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              color: buttonTextColor ?? AppColors.primary,
                              strokeWidth: 2))
                      : Text(buttonLabel,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: buttonTextColor ?? AppColors.primary)))),
          const SizedBox(height: 14),

          // Register link
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('$registerText ',
                style:
                    const TextStyle(color: AppColors.textMuted, fontSize: 13)),
            GestureDetector(
                onTap: onRegister,
                child: Text(registerLabel,
                    style: TextStyle(
                        color: accentColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w700))),
          ]),
        ]),
      ),
    );
  }
}
