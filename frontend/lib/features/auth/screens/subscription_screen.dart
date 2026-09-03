import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../billing/repositories/subscription_repository.dart';

/// Per-plan icon/tag are display-only — the plan itself (id, name, price,
/// features) always comes from [SubscriptionRepository.fetchPlans], the same
/// source of truth the paywall and checkout screens use.
const Map<String, IconData> _kPlanIcons = {
  'student_pro': Icons.school_rounded,
  'lawyer': Icons.gavel_rounded,
  'lawyer_pro': Icons.workspace_premium_rounded,
  'lawyer_premium': Icons.diamond_rounded,
};

const Map<String, String> _kPlanTags = {
  'lawyer_pro': 'Most Popular',
  'lawyer_premium': 'Best Value',
};

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});
  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  final _repo = SubscriptionRepository();

  List<Plan> _plans = [];
  String? _selectedPlanId;
  bool _isYearly = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final plans = await _repo.fetchPlans();
      if (!mounted) return;
      setState(() {
        _plans = plans;
        _selectedPlanId = plans.isNotEmpty ? plans.first.id : null;
        _loading = false;
      });
    } on BillingException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load plans. Please try again.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedPlan = _plans.isEmpty
        ? null
        : _plans.firstWhere(
            (p) => p.id == _selectedPlanId,
            orElse: () => _plans.first,
          );

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.bgGradient),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(child: _buildBody()),
              if (!_loading && _error == null && _plans.isNotEmpty)
                _buildFooter(selectedPlan),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.bgCard,
                  border: Border.all(color: AppColors.gold, width: 1.4),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.gold.withValues(alpha: 0.25),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/logo/app logo.png',
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              RichText(
                text: const TextSpan(children: [
                  TextSpan(
                    text: 'ONE',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 2.5,
                    ),
                  ),
                  TextSpan(
                    text: 'LEGAL',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: AppColors.gold,
                      letterSpacing: 2.5,
                    ),
                  ),
                ]),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => context.go('/dashboard'),
                child: const Text('Skip for now',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 2),
          const Padding(
            padding: EdgeInsets.only(left: 54),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Your Legal Journey Starts Here',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Choose Your Plan',
            style: TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Select the plan that fits your legal journey. Start with 5 days FREE.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.textMuted, fontSize: 12.5, height: 1.4),
            ),
          ),
          const SizedBox(height: 16),
          if (!_loading && _error == null && _plans.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border, width: 1),
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
                    label: 'Yearly',
                    selected: _isYearly,
                    onTap: () => setState(() => _isYearly = true),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.gold),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: AppColors.textMuted, size: 40),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _loadPlans,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.gold,
                  side: const BorderSide(color: AppColors.gold),
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_plans.isEmpty) {
      return const Center(
        child: Text('No plans available right now.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        children: [
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _plans.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              mainAxisExtent: 214,
            ),
            itemBuilder: (_, i) => _PlanCard(
              plan: _plans[i],
              isYearly: _isYearly,
              selected: _plans[i].id == _selectedPlanId,
              icon: _kPlanIcons[_plans[i].name] ?? Icons.description_rounded,
              tag: _kPlanTags[_plans[i].name],
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _selectedPlanId = _plans[i].id);
              },
            ),
          ),
          const SizedBox(height: 16),
          _buildTrialBanner(),
        ],
      ),
    );
  }

  Widget _buildTrialBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withValues(alpha: 0.12),
            blurRadius: 16,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: AppColors.info.withValues(alpha: 0.08),
            blurRadius: 20,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.card_giftcard_rounded,
                color: AppColors.gold, size: 19),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Start FREE for 5 Days!',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700)),
                SizedBox(height: 2),
                Text('Explore all features. No payment required to start.',
                    style: TextStyle(
                        color: AppColors.textMuted, fontSize: 11.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(Plan? selectedPlan) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: 54,
            child: _GoldButton(
              label: selectedPlan == null
                  ? 'Continue'
                  : 'Continue with ${selectedPlan.displayName}',
              onPressed: () {
                HapticFeedback.heavyImpact();
                context.go('/dashboard');
              },
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Already have an account? ',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
              GestureDetector(
                onTap: () => context.go('/login'),
                child: const Text('Sign In',
                    style: TextStyle(
                        color: AppColors.gold,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final Plan plan;
  final bool isYearly;
  final bool selected;
  final IconData icon;
  final String? tag;
  final VoidCallback onTap;

  const _PlanCard({
    required this.plan,
    required this.isYearly,
    required this.selected,
    required this.icon,
    required this.tag,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final price = isYearly ? plan.priceYearly : plan.priceMonthly;
    final features = plan.features.take(3).toList();
    final moreCount = plan.features.length - features.length;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.gold.withValues(alpha: 0.07)
              : AppColors.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.gold : AppColors.border,
            width: selected ? 1.6 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.gold.withValues(alpha: 0.22),
                    blurRadius: 14,
                    spreadRadius: 0.5,
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: (selected ? AppColors.gold : AppColors.textMuted)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon,
                      color: selected ? AppColors.gold : AppColors.textSecondary,
                      size: 16),
                ),
                const Spacer(),
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? AppColors.gold : Colors.transparent,
                    border: Border.all(
                      color: selected ? AppColors.gold : AppColors.border,
                      width: 1.6,
                    ),
                  ),
                  child: selected
                      ? const Icon(Icons.check_rounded,
                          color: AppColors.primary, size: 12)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              plan.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (tag != null) ...[
              const SizedBox(height: 3),
              Text(tag!,
                  style: const TextStyle(
                      color: AppColors.gold,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 6),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '₹${price.toStringAsFixed(0)}',
                    style: const TextStyle(
                      color: AppColors.gold,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  TextSpan(
                    text: isYearly ? '/yr' : '/mo',
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 10.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  for (final f in features)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.check_circle_rounded,
                              color: AppColors.gold, size: 11),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              f,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 10.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (moreCount > 0)
                    Text('+$moreCount more',
                        style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoldButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  const _GoldButton({required this.label, required this.onPressed});

  @override
  State<_GoldButton> createState() => _GoldButtonState();
}

class _GoldButtonState extends State<_GoldButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: AppColors.gold,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: AppColors.gold.withValues(alpha: _pressed ? 0.18 : 0.32),
                blurRadius: _pressed ? 10 : 18,
                spreadRadius: 1,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded,
                    color: AppColors.primary, size: 20),
              ],
            ),
          ),
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.gold : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.primary : AppColors.textMuted,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
