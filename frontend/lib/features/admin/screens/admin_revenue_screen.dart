import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/dio_client.dart';

const _bg = Color(0xFFF5ECD7);
const _bgCard = Color(0xFFFFFFFF);
const _brown = Color(0xFF5C3317);
const _brownDark = Color(0xFF3D2008);
const _gold = Color(0xFFB8860B);
const _border = Color(0xFFD4B896);
const _textPri = Color(0xFF2C1A0E);
const _green = Color(0xFF2E8B57);
const _blue = Color(0xFF4A90D9);

class AdminRevenueScreen extends StatefulWidget {
  const AdminRevenueScreen({super.key});
  @override
  State<AdminRevenueScreen> createState() => _AdminRevenueScreenState();
}

class _AdminRevenueScreenState extends State<AdminRevenueScreen> {
  Map<String, dynamic> _revenue = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await DioClient.instance.get('/admin/revenue');
      setState(() {
        _revenue = res.data['data'] ?? {};
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  String _fmt(dynamic v) {
    final n = (v as num?)?.toDouble() ?? 0;
    if (n >= 100000) return '₹${(n / 100000).toStringAsFixed(1)}L';
    if (n >= 1000) return '₹${(n / 1000).toStringAsFixed(1)}K';
    return '₹${n.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Column(children: [
        Container(
          decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [_brown, _brownDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight)),
          child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 16, 16),
                child: Row(children: [
                  IconButton(
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: Colors.white),
                      onPressed: () => context.pop()),
                  const Expanded(
                      child: Text('Revenue Analytics',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700))),
                  IconButton(
                      icon: const Icon(Icons.refresh_rounded,
                          color: Colors.white),
                      onPressed: _load),
                ]),
              )),
        ),
        Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _brown))
                : RefreshIndicator(
                    color: _brown,
                    backgroundColor: _bgCard,
                    onRefresh: _load,
                    child:
                        ListView(padding: const EdgeInsets.all(16), children: [
                      // Total revenue card
                      Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                  colors: [_brown, _brownDark]),
                              borderRadius: BorderRadius.circular(16)),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Total Revenue',
                                    style: TextStyle(
                                        color: Colors.white70, fontSize: 12)),
                                Text(_fmt(_revenue['total_revenue'] ?? 0),
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 32,
                                        fontWeight: FontWeight.w900)),
                                const SizedBox(height: 10),
                                Row(children: [
                                  _RevPill(
                                      'This Month',
                                      _fmt(_revenue['monthly_revenue'] ?? 0),
                                      _gold),
                                  const SizedBox(width: 10),
                                  _RevPill(
                                      'This Week',
                                      _fmt(_revenue['weekly_revenue'] ?? 0),
                                      const Color(0xFF90EE90)),
                                ]),
                              ])),
                      const SizedBox(height: 16),

                      // Revenue breakdown
                      const Text('Revenue Sources',
                          style: TextStyle(
                              color: _textPri,
                              fontSize: 16,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 12),
                      _RevCard(
                          '💳 Subscription Revenue',
                          _fmt(_revenue['subscription_revenue'] ?? 0),
                          _green,
                          Icons.subscriptions_rounded),
                      _RevCard(
                          '🤝 Consultation Commission',
                          _fmt(_revenue['consultation_revenue'] ?? 0),
                          _blue,
                          Icons.handshake_rounded),
                      _RevCard(
                          '⭐ Featured Listings',
                          _fmt(_revenue['featured_revenue'] ?? 0),
                          _gold,
                          Icons.star_rounded),
                      _RevCard(
                          '🎓 Certification Sales',
                          _fmt(_revenue['certification_revenue'] ?? 0),
                          const Color(0xFF7C3AED),
                          Icons.workspace_premium_rounded),
                      _RevCard(
                          '🏢 Law Firm Plans',
                          _fmt(_revenue['firm_revenue'] ?? 0),
                          _brown,
                          Icons.business_rounded),
                      const SizedBox(height: 20),

                      // Subscription breakdown
                      const Text('Subscriptions by Plan',
                          style: TextStyle(
                              color: _textPri,
                              fontSize: 16,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 12),
                      ...([
                        [
                          'Student Pro - ₹99',
                          _revenue['student_pro_count'] ?? 0,
                          _blue
                        ],
                        [
                          'Student Premium - ₹199',
                          _revenue['student_premium_count'] ?? 0,
                          const Color(0xFF7C3AED)
                        ],
                        [
                          'Lawyer Pro - ₹499',
                          _revenue['lawyer_pro_count'] ?? 0,
                          _brown
                        ],
                        [
                          'Lawyer Premium - ₹999',
                          _revenue['lawyer_premium_count'] ?? 0,
                          _gold
                        ],
                        [
                          'Law Firm - ₹2999',
                          _revenue['firm_count'] ?? 0,
                          _green
                        ],
                      ])
                          .map((item) => Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                  color: _bgCard,
                                  borderRadius: BorderRadius.circular(12),
                                  border:
                                      Border.all(color: _border, width: 0.8)),
                              child: Row(children: [
                                Expanded(
                                    child: Text(item[0] as String,
                                        style: const TextStyle(
                                            color: _textPri,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500))),
                                Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 4),
                                    decoration: BoxDecoration(
                                        color:
                                            (item[2] as Color).withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8)),
                                    child: Text('${item[1]} users',
                                        style: TextStyle(
                                            color: item[2] as Color,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12))),
                              ]))),
                      const SizedBox(height: 40),
                    ]))),
      ]),
    );
  }

  Widget _RevPill(String label, String value, Color color) => Expanded(
      child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 9)),
            Text(value,
                style: TextStyle(
                    color: color, fontSize: 15, fontWeight: FontWeight.w800)),
          ])));

  Widget _RevCard(String label, String value, Color color, IconData icon) =>
      Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: _bgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withValues(alpha: 0.2)),
              boxShadow: [
                BoxShadow(
                    color: _brown.withValues(alpha: 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2))
              ]),
          child: Row(children: [
            Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: color, size: 20)),
            const SizedBox(width: 14),
            Expanded(
                child: Text(label,
                    style: const TextStyle(
                        color: _textPri,
                        fontSize: 13,
                        fontWeight: FontWeight.w500))),
            Text(value,
                style: TextStyle(
                    color: color, fontSize: 16, fontWeight: FontWeight.w800)),
          ]));
}
