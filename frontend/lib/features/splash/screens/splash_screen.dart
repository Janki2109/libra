import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/services/storage_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        duration: const Duration(milliseconds: 1200), vsync: this);
    _scaleAnim = Tween<double>(begin: 0.7, end: 1.0)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.elasticOut));
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _animCtrl, curve: const Interval(0.0, 0.6)));
    _animCtrl.forward();
    Future.delayed(const Duration(seconds: 3), _navigateNext);
  }

  Future<void> _navigateNext() async {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    final role = auth.user?.roleName ?? '';
    if (auth.status == AuthStatus.authenticated) {
      if (role == 'super_admin')
        context.go('/admin');
      else if (role == 'client')
        context.go('/portal/dashboard');
      else if (role == 'law_student')
        context.go('/student/dashboard');
      else
        context.go('/dashboard');
    } else {
      final seenOnboarding = await StorageService.hasSeenOnboarding();
      if (!mounted) return;
      context.go(seenOnboarding ? '/login' : '/onboarding');
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  static const _gold = Color(0xFFD4A017);

  Widget _brandItem(IconData icon, String label) {
    return Column(children: [
      Icon(icon, color: _gold, size: 20),
      const SizedBox(height: 6),
      Text(label,
          style: const TextStyle(
              color: Colors.white60,
              fontSize: 11,
              fontWeight: FontWeight.w500)),
    ]);
  }

  Widget _brandDivider() => Container(
      width: 1, height: 34, color: Colors.white24, margin: const EdgeInsets.symmetric(horizontal: 18));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A14),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0A0A14), Color(0xFF1A0E2E), Color(0xFF0A0A14)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Stack(children: [
          // Bottom wave design
          Positioned(
              left: 0,
              right: 0,
              bottom: 90,
              child: SizedBox(
                  height: 60,
                  child: CustomPaint(painter: _WavePainter()))),

          Center(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: ScaleTransition(
                scale: _scaleAnim,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: _gold, width: 1.6),
                        boxShadow: [
                          BoxShadow(
                              color: _gold.withValues(alpha: 0.35),
                              blurRadius: 30,
                              spreadRadius: 4),
                        ],
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/logo/app logo.png',
                          width: 92,
                          height: 92,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    RichText(
                        text: const TextSpan(children: [
                      TextSpan(
                          text: 'ONE',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 4)),
                      TextSpan(
                          text: 'LEGAL',
                          style: TextStyle(
                              color: _gold,
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 4)),
                    ])),
                    const SizedBox(height: 10),
                    Container(width: 36, height: 2, color: _gold),
                    const SizedBox(height: 14),
                    RichText(
                        text: const TextSpan(children: [
                      TextSpan(
                          text: 'Your Legal Journey. ',
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w500)),
                      TextSpan(
                          text: 'Simplified.',
                          style: TextStyle(
                              color: _gold,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                    ])),
                    const SizedBox(height: 26),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      _brandItem(Icons.work_outline_rounded, 'For Lawyers'),
                      _brandDivider(),
                      _brandItem(Icons.groups_outlined, 'For Clients'),
                      _brandDivider(),
                      _brandItem(
                          Icons.school_outlined, 'For Students'),
                    ]),
                  ],
                ),
              ),
            ),
          ),

          // Loading indicator
          Positioned(
              left: 0,
              right: 0,
              bottom: 40,
              child: Column(children: [
                Container(
                    width: 60,
                    height: 2,
                    decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [
                      _gold.withValues(alpha: 0.0),
                      _gold,
                      _gold.withValues(alpha: 0.0),
                    ]))),
                const SizedBox(height: 12),
                const Text('Loading, please wait...',
                    style: TextStyle(color: Colors.white38, fontSize: 12)),
              ])),
        ]),
      ),
    );
  }
}

// Subtle decorative wave behind the loading area, matching the reference
// splash design. Purely visual — no logic.
class _WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (int line = 0; line < 3; line++) {
      final path = Path();
      final baseY = size.height * 0.5 + (line - 1) * 10;
      final amplitude = 8.0;
      final frequency = 1.5 + line * 0.3;
      for (double x = 0; x <= size.width; x += 2) {
        final y = baseY +
            amplitude *
                math.sin((x / size.width) * 2 * math.pi * frequency);
        if (x == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
