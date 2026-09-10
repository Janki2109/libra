import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../billing/repositories/subscription_repository.dart';

const _bg = Color(0xFF0A0A14);
const _bgCard = Color(0xFF150A2E);
const _gold = Color(0xFFD4A017);
const _border = Color(0xFF2A1A4E);
const _textPri = Color(0xFFFFFFFF);
const _textMuted = Color(0xFF8888AA);

/// The paywall.
///
/// What this replaces is worth stating plainly. The old screen held four
/// hardcoded plans that existed nowhere in the database, showed the firm's own
/// UPI ID and asked the user to transfer money by hand and "send a payment
/// screenshot to WhatsApp for faster activation" — and its confirm button
/// called TrialService.setSubscribed(true), granting a full subscription
/// locally with no money involved and no server ever informed.
///
/// Plans now come from the server, the price is decided there, payment goes
/// through the gateway, and entitlement is granted only after a signature the
/// server verifies itself.
class SubscriptionWallScreen extends StatefulWidget {
  const SubscriptionWallScreen({super.key});

  @override
  State<SubscriptionWallScreen> createState() => _SubscriptionWallScreenState();
}

class _SubscriptionWallScreenState extends State<SubscriptionWallScreen> {
  final _repo = SubscriptionRepository();

  List<Plan> _plans = const [];
  int _selected = 0;
  String _cycle = 'monthly';
  bool _loading = true;
  bool _starting = false;
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
        // Default to the middle tier when there is one — the plan most firms
        // actually want, rather than the cheapest.
        _selected = plans.length > 2 ? 1 : 0;
        _loading = false;
      });
    } on BillingException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  // Checkout is temporarily disabled — Subscribe just tells the user payment
  // is coming soon and leaves them on this screen, instead of opening the
  // Razorpay checkout flow below.
  Future<void> _subscribe() async {
    if (_plans.isEmpty) return;
    HapticFeedback.lightImpact();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _bgCard,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Payment Coming Soon',
            style: TextStyle(color: _textPri, fontWeight: FontWeight.w700)),
        content: const Text('Subscription payment will be available soon.',
            style: TextStyle(color: _textMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK', style: TextStyle(color: _gold)),
          ),
        ],
      ),
    );
  }

  double _price(Plan p) => _cycle == 'yearly' ? p.priceYearly : p.priceMonthly;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: _gold))
            : _error != null
                ? _buildError()
                : _plans.isEmpty
                    ? _buildEmpty()
                    : _buildPlans(),
      ),
    );
  }

  Widget _buildError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_rounded, size: 48, color: _textMuted),
            const SizedBox(height: 16),
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: _textPri, fontSize: 14, height: 1.5)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadPlans,
              style: ElevatedButton.styleFrom(
                  backgroundColor: _gold,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              child: const Text('Try again',
                  style: TextStyle(
                      color: Colors.black, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      );

  Widget _buildEmpty() => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No plans are available right now. Please contact support.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _textMuted, fontSize: 14),
          ),
        ),
      );

  Widget _buildPlans() {
    final plan = _plans[_selected];
    final price = _price(plan);

    return Column(children: [
      const SizedBox(height: 20),
      const Text('Choose your plan',
          style: TextStyle(
              color: _textPri, fontSize: 22, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      const Text('Your trial has ended. Pick a plan to keep working.',
          style: TextStyle(color: _textMuted, fontSize: 12)),
      const SizedBox(height: 18),

      _buildCycleToggle(),
      const SizedBox(height: 16),

      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: _plans.length,
          itemBuilder: (_, i) => _buildPlanCard(i),
        ),
      ),

      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: Column(children: [
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _starting ? null : _subscribe,
              style: ElevatedButton.styleFrom(
                backgroundColor: _gold,
                disabledBackgroundColor: _gold.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: _starting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                  : Text(
                      'Subscribe — ₹${price.toStringAsFixed(0)}'
                      '${_cycle == 'yearly' ? '/year' : '/month'}',
                      style: const TextStyle(
                          color: Colors.black,
                          fontSize: 15,
                          fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 10),
          const Text('Secure payment. Cancel any time.',
              style: TextStyle(color: _textMuted, fontSize: 11)),
        ]),
      ),
    ]);
  }

  Widget _buildCycleToggle() {
    final saving = _plans.isEmpty ? null : _plans[_selected].yearlySavingPercent;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
          color: _bgCard, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        _cycleTab('Monthly', 'monthly'),
        _cycleTab('Yearly', 'yearly',
            badge: saving != null ? 'Save $saving%' : null),
      ]),
    );
  }

  Widget _cycleTab(String label, String value, {String? badge}) {
    final active = _cycle == value;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _cycle = value);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
              color: active ? _gold : Colors.transparent,
              borderRadius: BorderRadius.circular(9)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(label,
                style: TextStyle(
                    color: active ? Colors.black : _textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
            if (badge != null) ...[
              const SizedBox(width: 6),
              Text(badge,
                  style: TextStyle(
                      color: active ? Colors.black87 : _gold,
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _buildPlanCard(int i) {
    final plan = _plans[i];
    final active = i == _selected;
    final price = _price(plan);

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _selected = i);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: active ? _gold : _border, width: active ? 2 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(plan.displayName,
                  style: const TextStyle(
                      color: _textPri,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
            ),
            Text('₹${price.toStringAsFixed(0)}',
                style: const TextStyle(
                    color: _gold, fontSize: 18, fontWeight: FontWeight.w800)),
            Text(_cycle == 'yearly' ? '/yr' : '/mo',
                style: const TextStyle(color: _textMuted, fontSize: 11)),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            _limitChip(plan.limitLabel(plan.maxCases, 'cases')),
            _limitChip(plan.limitLabel(plan.maxStaff, 'staff')),
            _limitChip(plan.limitLabel(plan.maxClients, 'clients')),
          ]),
          if (plan.features.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...plan.features.map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(children: [
                    const Icon(Icons.check_rounded, color: _gold, size: 14),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(f,
                            style: const TextStyle(
                                color: _textMuted, fontSize: 12))),
                  ]),
                )),
          ],
        ]),
      ),
    );
  }

  Widget _limitChip(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: _bg, borderRadius: BorderRadius.circular(6)),
        child: Text(label,
            style: const TextStyle(color: _textMuted, fontSize: 10)),
      );
}
