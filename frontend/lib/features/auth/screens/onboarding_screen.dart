import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/storage_service.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // Total pages = 1 subscription + 3 feature pages = 4
  final List<Map<String, dynamic>> _pages = [
    {'type': 'subscription'}, // ← Subscription slide first
    {
      'type': 'feature',
      'icon': Icons.gavel_rounded,
      'title': 'Manage Your Cases',
      'subtitle':
          'Track all your cases, hearings, timelines and documents in one place. Never miss a court date again.',
      'color': AppColors.gold,
    },
    {
      'type': 'feature',
      'icon': Icons.people_rounded,
      'title': 'Client Management',
      'subtitle':
          'Manage all your clients, their documents, invoices and case history with ease.',
      'color': AppColors.info,
    },
    {
      'type': 'feature',
      'icon': Icons.currency_rupee_rounded,
      'title': 'Smart Billing',
      'subtitle':
          'Create professional invoices, track payments and manage your firm\'s finances effortlessly.',
      'color': AppColors.success,
    },
  ];

  // 'key' matches the backend plans.name row so the choice can be sent
  // straight through to Register() as-is.
  String _selectedPlan = 'lawyer_pro';

  final List<Map<String, dynamic>> _plans = [
    {
      'key': 'student_pro',
      'name': 'Student Pro',
      'price': '₹99',
      'period': '/month',
      'icon': '🎓',
      'color': const Color(0xFF1565C0),
      'features': [
        'Case Studies',
        'Court Mock Assignments',
        'Draft Practice',
        'Legal Research Practice'
      ],
    },
    {
      'key': 'lawyer',
      'name': 'Lawyer',
      'price': '₹199',
      'period': '/month',
      'icon': '⚖️',
      'color': const Color(0xFF2E8B57),
      'features': [
        'Multiple Cases',
        'Client Management',
        'Client Documents',
        'Case Documents'
      ],
    },
    {
      'key': 'lawyer_pro',
      'name': 'Lawyer Pro',
      'price': '₹299',
      'period': '/month',
      'icon': '🏆',
      'color': const Color(0xFFB8860B),
      'popular': true,
      'features': [
        'Everything in Lawyer',
        'e-Court Access',
        'Hearing List',
        'Advanced Case Info'
      ],
    },
    {
      'key': 'lawyer_premium',
      'name': 'Lawyer Premium',
      'price': '₹499',
      'period': '/month',
      'icon': '👑',
      'color': const Color(0xFF5C3317),
      'features': [
        'Everything in Lawyer Pro',
        'All Premium Features',
        'Advanced Tools',
        'Full e-Court Access'
      ],
    },
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
          child: Column(children: [
        // Skip button
        Align(
            alignment: Alignment.centerRight,
            child: TextButton(
                onPressed: () {
                  StorageService.setOnboardingSeen();
                  context.go('/login');
                },
                child: const Text('Skip',
                    style:
                        TextStyle(color: AppColors.textMuted, fontSize: 14)))),

        // Pages
        Expanded(
            child: PageView.builder(
          controller: _pageController,
          onPageChanged: (i) => setState(() => _currentPage = i),
          itemCount: _pages.length,
          itemBuilder: (_, i) {
            final page = _pages[i];
            if (page['type'] == 'subscription')
              return _buildSubscriptionSlide();
            return _buildFeatureSlide(page);
          },
        )),

        // Dots + Button
        Padding(
            padding: const EdgeInsets.all(32),
            child: Column(children: [
              // Dots
              Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                      _pages.length,
                      (i) => AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: _currentPage == i ? 24 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                                color: _currentPage == i
                                    ? AppColors.gold
                                    : AppColors.border,
                                borderRadius: BorderRadius.circular(4)),
                          ))),
              const SizedBox(height: 32),

              // Next / Get Started Button
              SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      if (_currentPage < _pages.length - 1) {
                        _pageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut);
                      } else {
                        StorageService.setOnboardingSeen();
                        StorageService.savePendingPlan(_selectedPlan);
                        context.go('/register');
                      }
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.gold,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14))),
                    child: Text(
                        _currentPage < _pages.length - 1
                            ? 'Next'
                            : 'Get Started',
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary)),
                  )),
              const SizedBox(height: 16),

              // Already have account
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text('Already have an account? ',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                GestureDetector(
                    onTap: () {
                      StorageService.setOnboardingSeen();
                      context.go('/login');
                    },
                    child: const Text('Sign In',
                        style: TextStyle(
                            color: AppColors.gold,
                            fontSize: 13,
                            fontWeight: FontWeight.w700))),
              ]),
            ])),
      ])),
    );
  }

  // ── Subscription Slide ─────────────────────────
  Widget _buildSubscriptionSlide() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        // Header
        ShaderMask(
            shaderCallback: (b) => const LinearGradient(
                colors: [Color(0xFFFFD700), Color(0xFFB8860B)]).createShader(b),
            child: const Text('Choose Your Plan',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900))),
        const SizedBox(height: 2),
        const Text('5 Days FREE Trial • No credit card required',
            style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
        const SizedBox(height: 12),

        // Plans - compact 2x2 grid
        Row(children: [
          Expanded(child: _PlanCard(_plans[0])),
          const SizedBox(width: 8),
          Expanded(child: _PlanCard(_plans[1])),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _PlanCard(_plans[2])),
          const SizedBox(width: 8),
          Expanded(child: _PlanCard(_plans[3])),
        ]),
        const SizedBox(height: 12),

        // Free trial banner
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFB8860B).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFB8860B).withValues(alpha: 0.3)),
          ),
          child: const Row(children: [
            Text('🎁', style: TextStyle(fontSize: 18)),
            SizedBox(width: 8),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('Start FREE for 5 Days!',
                      style: TextStyle(
                          color: Color(0xFFB8860B),
                          fontWeight: FontWeight.w800,
                          fontSize: 12)),
                  Text(
                      'Full access to all features. No payment needed to start.',
                      style:
                          TextStyle(color: AppColors.textMuted, fontSize: 10)),
                ])),
          ]),
        ),
      ]),
    );
  }

  Widget _PlanCard(Map<String, dynamic> plan) {
    final color = plan['color'] as Color;
    final popular = plan['popular'] == true;
    final selected = _selectedPlan == plan['key'];
    final highlighted = popular || selected;
    return GestureDetector(
      onTap: () => setState(() => _selectedPlan = plan['key']),
      child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: highlighted ? color : color.withValues(alpha: 0.2),
            width: highlighted ? 2 : 0.8),
        boxShadow: highlighted
            ? [BoxShadow(color: color.withValues(alpha: 0.15), blurRadius: 8)]
            : [],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(plan['icon'], style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 4),
          if (popular)
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                    color: color, borderRadius: BorderRadius.circular(4)),
                child: const Text('⭐', style: TextStyle(fontSize: 8))),
        ]),
        const SizedBox(height: 4),
        Text(plan['name'],
            style: TextStyle(
                color: color, fontWeight: FontWeight.w800, fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        Text('${plan['price']}${plan['period']}',
            style: TextStyle(
                color: color.withValues(alpha: 0.8),
                fontSize: 11,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        ...(plan['features'] as List<String>).take(2).map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(children: [
                Icon(Icons.check_rounded, color: color, size: 10),
                const SizedBox(width: 3),
                Expanded(
                    child: Text(f,
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 9),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis)),
              ]),
            )),
      ]),
      ),
    );
  }

  // ── Feature Slide ──────────────────────────────
  Widget _buildFeatureSlide(Map<String, dynamic> page) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (page['color'] as Color).withValues(alpha: 0.1),
                border: Border.all(
                    color: (page['color'] as Color).withValues(alpha: 0.3),
                    width: 2)),
            child: Icon(page['icon'] as IconData,
                size: 70, color: page['color'] as Color)),
        const SizedBox(height: 48),
        Text(page['title'] as String,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 26,
                fontWeight: FontWeight.w800),
            textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Text(page['subtitle'] as String,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 15, height: 1.6),
            textAlign: TextAlign.center),
      ]),
    );
  }
}
