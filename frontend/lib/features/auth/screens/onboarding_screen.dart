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

  // Plan choice happens after login/registration (see SubscriptionScreen),
  // not here — showing it before an account exists let people "select" a
  // plan with nothing behind it to purchase or activate.
  final List<Map<String, dynamic>> _pages = [
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
          itemBuilder: (_, i) => _buildFeatureSlide(_pages[i]),
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
