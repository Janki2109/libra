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
const _textMuted = Color(0xFF8B5E3C);
const _green = Color(0xFF2E8B57);
const _red = Color(0xFFD9534F);
const _blue = Color(0xFF4A90D9);

class AdminSubscriptionsScreen extends StatefulWidget {
  const AdminSubscriptionsScreen({super.key});
  @override
  State<AdminSubscriptionsScreen> createState() =>
      _AdminSubscriptionsScreenState();
}

class _AdminSubscriptionsScreenState extends State<AdminSubscriptionsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<dynamic> _subs = [];
  bool _loading = true;

  final List<Map<String, dynamic>> _plans = [
    {
      'name': 'Student Pro',
      'price': '₹99/month',
      'color': _blue,
      'icon': '🎓',
      'features': ['Legal Notes', 'Case Studies', 'Basic AI Tutor', 'Quizzes'],
      'target': 'Law Students',
    },
    {
      'name': 'Student Premium',
      'price': '₹199/month',
      'color': Color(0xFF7C3AED),
      'icon': '⭐',
      'features': [
        'Everything in Pro',
        'Unlimited AI Tutor',
        'Mock Court',
        'Certificates'
      ],
      'target': 'Law Students',
    },
    {
      'name': 'Lawyer Pro',
      'price': '₹499/month',
      'color': _brown,
      'icon': '⚖️',
      'features': [
        'Client Management',
        'Case Management',
        'Documents',
        'Billing',
        'Basic AI Research'
      ],
      'target': 'Advocates',
    },
    {
      'name': 'Lawyer Premium',
      'price': '₹999/month',
      'color': _gold,
      'icon': '🏆',
      'features': [
        'Everything in Pro',
        'Unlimited Cases',
        'Advanced AI Research',
        'AI Drafting',
        'Staff Management',
        'Video Consultation'
      ],
      'target': 'Senior Advocates',
    },
    {
      'name': 'Law Firm Plan',
      'price': '₹2999/month',
      'color': _green,
      'icon': '🏛️',
      'features': [
        'Multiple Lawyers',
        'Multiple Branches',
        'Team Collaboration',
        'Advanced Reports',
        'Revenue Analytics'
      ],
      'target': 'Law Firms',
    },
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await DioClient.instance.get('/admin/subscriptions');
      setState(() {
        _subs = res.data['data'] ?? [];
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
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
              child: Column(children: [
                Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
                    child: Row(children: [
                      IconButton(
                          icon: const Icon(Icons.arrow_back_rounded,
                              color: Colors.white),
                          onPressed: () => context.pop()),
                      const Expanded(
                          child: Text('Subscription Management',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700))),
                      const SizedBox(width: 48),
                    ])),
                TabBar(
                    controller: _tabCtrl,
                    indicatorColor: const Color(0xFFFFD700),
                    indicatorWeight: 3,
                    labelColor: const Color(0xFFFFD700),
                    unselectedLabelColor: Colors.white60,
                    tabs: [
                      Tab(text: '📋 Plans'),
                      Tab(text: '👥 Active Subs (${_subs.length})')
                    ]),
              ])),
        ),
        Expanded(
            child: TabBarView(controller: _tabCtrl, children: [
          _buildPlans(),
          _buildActiveSubs(),
        ])),
      ]),
    );
  }

  Widget _buildPlans() =>
      ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Subscription Plans',
            style: TextStyle(
                color: _textPri, fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('Current pricing structure',
            style: TextStyle(color: _textMuted, fontSize: 12)),
        const SizedBox(height: 16),
        ..._plans.map((plan) {
          final color = plan['color'] as Color;
          return Container(
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                  color: _bgCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: color.withValues(alpha: 0.25)),
                  boxShadow: [
                    BoxShadow(
                        color: _brown.withValues(alpha: 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2))
                  ]),
              child: Column(children: [
                Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.06),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(16))),
                    child: Row(children: [
                      Text(plan['icon'], style: const TextStyle(fontSize: 28)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(plan['name'],
                                style: TextStyle(
                                    color: color,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16)),
                            Text(plan['target'],
                                style: const TextStyle(
                                    color: _textMuted, fontSize: 11)),
                          ])),
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(20)),
                          child: Text(plan['price'],
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13))),
                    ])),
                Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ...(plan['features'] as List<String>)
                              .map((f) => Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Row(children: [
                                      Icon(Icons.check_circle_rounded,
                                          color: color, size: 14),
                                      const SizedBox(width: 8),
                                      Text(f,
                                          style: const TextStyle(
                                              color: _textPri, fontSize: 12)),
                                    ]),
                                  )),
                        ])),
              ]));
        }),
        const SizedBox(height: 40),
      ]);

  Widget _buildActiveSubs() => _loading
      ? const Center(child: CircularProgressIndicator(color: _brown))
      : _subs.isEmpty
          ? Center(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                  Icon(Icons.subscriptions_rounded,
                      color: _brown.withValues(alpha: 0.3), size: 56),
                  const SizedBox(height: 12),
                  const Text('No active subscriptions',
                      style: TextStyle(color: _textMuted, fontSize: 15)),
                ]))
          : RefreshIndicator(
              color: _brown,
              backgroundColor: _bgCard,
              onRefresh: _load,
              child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _subs.length,
                  itemBuilder: (_, i) {
                    final s = _subs[i];
                    final isActive = s['status'] == 'active';
                    return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            color: _bgCard,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: isActive
                                    ? _green.withValues(alpha: 0.2)
                                    : _border),
                            boxShadow: [
                              BoxShadow(
                                  color: _brown.withValues(alpha: 0.04),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2))
                            ]),
                        child: Row(children: [
                          Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                  color: _brown.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(10)),
                              child: const Icon(Icons.person_rounded,
                                  color: _brown, size: 22)),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(s['user_name'] ?? s['name'] ?? 'User',
                                    style: const TextStyle(
                                        color: _textPri,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14)),
                                Text(s['plan_name'] ?? 'Plan',
                                    style: const TextStyle(
                                        color: _brown,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600)),
                                Text(
                                    'Expires: ${(s['expires_at'] ?? '').toString().length >= 10 ? (s['expires_at'] ?? '').toString().substring(0, 10) : '-'}',
                                    style: const TextStyle(
                                        color: _textMuted, fontSize: 11)),
                              ])),
                          Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                  color: isActive
                                      ? _green.withValues(alpha: 0.1)
                                      : _red.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8)),
                              child: Text(isActive ? 'ACTIVE' : 'EXPIRED',
                                  style: TextStyle(
                                      color: isActive ? _green : _red,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800))),
                        ]));
                  }));
}
