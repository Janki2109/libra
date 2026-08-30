import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});
  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  String _selectedPlan = 'free';
  bool _isYearly = false;

  final List<Map<String, dynamic>> _plans = [
    {
      'id': 'free',
      'name': 'Free',
      'price_monthly': 0,
      'price_yearly': 0,
      'color': AppColors.textMuted,
      'icon': Icons.star_outline_rounded,
      'features': [
        '5 Cases',
        '2 Staff Members',
        '10 Clients',
        'Basic Reports',
        'Email Support',
      ],
      'tag': '14 Day Trial',
    },
    {
      'id': 'pro',
      'name': 'Pro',
      'price_monthly': 999,
      'price_yearly': 9999,
      'color': AppColors.gold,
      'icon': Icons.star_rounded,
      'features': [
        '100 Cases',
        '10 Staff Members',
        '100 Clients',
        'Advanced Reports',
        'Document Storage 10GB',
        'Billing & Invoices',
        'Priority Support',
      ],
      'tag': 'Most Popular',
    },
    {
      'id': 'firm',
      'name': 'Firm',
      'price_monthly': 2999,
      'price_yearly': 29999,
      'color': AppColors.info,
      'icon': Icons.business_rounded,
      'features': [
        'Unlimited Cases',
        'Unlimited Staff',
        'Unlimited Clients',
        'Full Reports & Analytics',
        '100GB Storage',
        'Court Integration',
        'Client Portal',
        '24/7 Support',
        'Custom Branding',
      ],
      'tag': 'Best Value',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          gradient: AppColors.goldGradient,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.balance_rounded,
                            color: AppColors.primary, size: 20),
                      ),
                      const SizedBox(width: 10),
                      const Text('LIBRA',
                          style: TextStyle(
                            color: AppColors.gold,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 3,
                          )),
                      const Spacer(),
                      TextButton(
                        onPressed: () => context.go('/dashboard'),
                        child: const Text('Skip for now',
                            style: TextStyle(
                                color: AppColors.textMuted, fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Choose Your Plan',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Start free, upgrade anytime',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                  const SizedBox(height: 16),

                  // Monthly / Yearly Toggle
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ToggleBtn(
                          label: 'Monthly',
                          selected: !_isYearly,
                          onTap: () => setState(() => _isYearly = false),
                        ),
                        _ToggleBtn(
                          label: 'Yearly  -17%',
                          selected: _isYearly,
                          onTap: () => setState(() => _isYearly = true),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Plans List
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _plans.length,
                itemBuilder: (_, i) {
                  final plan = _plans[i];
                  final selected = _selectedPlan == plan['id'];
                  final color = plan['color'] as Color;
                  final price = _isYearly
                      ? plan['price_yearly'] as int
                      : plan['price_monthly'] as int;

                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedPlan = plan['id'] as String);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: selected
                            ? color.withValues(alpha: 0.08)
                            : AppColors.bgCard,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: selected ? color : AppColors.border,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(plan['icon'] as IconData,
                                    color: color, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          plan['name'] as String,
                                          style: TextStyle(
                                            color: color,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: color.withValues(alpha: 0.1),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            plan['tag'] as String,
                                            style: TextStyle(
                                                color: color,
                                                fontSize: 9,
                                                fontWeight: FontWeight.w700),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      price == 0
                                          ? 'Free Forever'
                                          : '₹$price/${_isYearly ? 'year' : 'month'}',
                                      style: TextStyle(
                                        color: color,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: selected ? color : Colors.transparent,
                                  border: Border.all(
                                    color: selected ? color : AppColors.border,
                                    width: 2,
                                  ),
                                ),
                                child: selected
                                    ? const Icon(Icons.check_rounded,
                                        color: Colors.white, size: 14)
                                    : null,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Divider(color: AppColors.border, height: 1),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: (plan['features'] as List<String>)
                                .map((f) => Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.check_circle_rounded,
                                            color: color, size: 14),
                                        const SizedBox(width: 4),
                                        Text(f,
                                            style: const TextStyle(
                                                color: AppColors.textSecondary,
                                                fontSize: 12)),
                                      ],
                                    ))
                                .toList(),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // Continue Button
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: () {
                    HapticFeedback.heavyImpact();
                    context.go('/dashboard');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    _selectedPlan == 'free'
                        ? 'Start Free Trial'
                        : 'Continue with ${_plans.firstWhere((p) => p['id'] == _selectedPlan)['name']} Plan',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ToggleBtn({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.gold : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.primary : AppColors.textMuted,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
