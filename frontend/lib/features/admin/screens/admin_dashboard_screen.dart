import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/services/dio_client.dart';
import '../../auth/providers/auth_provider.dart';

const _bg = Color(0xFFF5ECD7);
const _bgCard = Color(0xFFFFFFFF);
const _brown = Color(0xFF5C3317);
const _brownDark = Color(0xFF3D2008);
const _gold = Color(0xFFB8860B);
const _textPri = Color(0xFF2C1A0E);
const _textMuted = Color(0xFF8B5E3C);
const _green = Color(0xFF2E8B57);
const _red = Color(0xFFD9534F);
const _blue = Color(0xFF4A90D9);

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});
  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  Map<String, dynamic> _stats = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await DioClient.instance.get('/admin/stats');
      setState(() {
        _stats = res.data['data'] ?? {};
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
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      backgroundColor: _bg,
      body: Column(children: [
        // Header
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [_brown, _brownDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
          ),
          child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                shape: BoxShape.circle),
                            child: const Icon(
                                Icons.admin_panel_settings_rounded,
                                color: Colors.white,
                                size: 22)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              const Text('Super Admin',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 11)),
                              Text(auth.user?.name ?? 'Admin',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800)),
                            ])),
                        GestureDetector(
                            onTap: () async {
                              await auth.logout();
                              if (context.mounted) context.go('/login');
                            },
                            child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8)),
                                child: const Icon(Icons.logout_rounded,
                                    color: Colors.white, size: 18))),
                      ]),
                      const SizedBox(height: 16),
                      // Stats row
                      Row(children: [
                        _StatPill('${_stats['total_users'] ?? 0}', 'Users',
                            Colors.white),
                        const SizedBox(width: 8),
                        _StatPill('${_stats['total_lawyers'] ?? 0}', 'Lawyers',
                            _gold),
                        const SizedBox(width: 8),
                        _StatPill('${_stats['total_clients'] ?? 0}', 'Clients',
                            const Color(0xFF90EE90)),
                        const SizedBox(width: 8),
                        _StatPill('${_stats['total_students'] ?? 0}',
                            'Students', const Color(0xFFADD8E6)),
                      ]),
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
                      // Revenue cards
                      Row(children: [
                        Expanded(
                            child: _Card(
                                'Total Revenue',
                                _fmt(_stats['total_revenue']),
                                Icons.account_balance_wallet_rounded,
                                _green)),
                        const SizedBox(width: 10),
                        Expanded(
                            child: _Card(
                                'This Month',
                                _fmt(_stats['monthly_revenue']),
                                Icons.trending_up_rounded,
                                _blue)),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                            child: _Card(
                                'Active Subs',
                                '${_stats['active_subscriptions'] ?? 0}',
                                Icons.subscriptions_rounded,
                                _gold)),
                        const SizedBox(width: 10),
                        Expanded(
                            child: _Card(
                                'Pending Verify',
                                '${_stats['pending_verification'] ?? 0}',
                                Icons.pending_rounded,
                                _red)),
                      ]),
                      const SizedBox(height: 20),

                      // Quick Actions
                      const Text('Management',
                          style: TextStyle(
                              color: _textPri,
                              fontSize: 16,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 12),
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 1.8,
                        children: [
                          _ActionTile('👥 User Management', 'Manage all users',
                              _brown, () => context.push('/admin/users')),
                          _ActionTile(
                              '✅ Verify Lawyers',
                              'Review applications',
                              _green,
                              () => context.push('/admin/verify-lawyers')),
                          _ActionTile(
                              '🎓 Verify Students',
                              'Student verification',
                              _blue,
                              () => context.push('/admin/verify-students')),
                          _ActionTile('💳 Subscriptions', 'Manage plans', _gold,
                              () => context.push('/admin/subscriptions')),
                          _ActionTile('💰 Revenue', 'Analytics & reports',
                              _green, () => context.push('/admin/revenue')),
                          _ActionTile('📋 Audit Logs', 'System activity',
                              _textMuted, () => context.push('/admin/audit')),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Pending verifications alert
                      if ((_stats['pending_verification'] ?? 0) > 0)
                        GestureDetector(
                          onTap: () => context.push('/admin/verify-lawyers'),
                          child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                  color: _red.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(12),
                                  border:
                                      Border.all(color: _red.withValues(alpha: 0.3))),
                              child: Row(children: [
                                const Icon(Icons.warning_amber_rounded,
                                    color: _red, size: 22),
                                const SizedBox(width: 10),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      const Text('Pending Verifications!',
                                          style: TextStyle(
                                              color: _red,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14)),
                                      Text(
                                          '${_stats['pending_verification']} lawyers waiting for verification',
                                          style: const TextStyle(
                                              color: _textMuted, fontSize: 12)),
                                    ])),
                                const Icon(Icons.arrow_forward_ios_rounded,
                                    color: _red, size: 14),
                              ])),
                        ),
                      const SizedBox(height: 80),
                    ]))),
      ]),
    );
  }

  Widget _StatPill(String value, String label, Color color) => Expanded(
          child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10)),
        child: Column(children: [
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 16, fontWeight: FontWeight.w800)),
          Text(label,
              style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 9)),
        ]),
      ));

  Widget _Card(String label, String value, IconData icon, Color color) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: _bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.2)),
            boxShadow: [
              BoxShadow(
                  color: _brown.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
            ]),
        child: Row(children: [
          Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 20)),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(value,
                    style: TextStyle(
                        color: color,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
                Text(label,
                    style: const TextStyle(color: _textMuted, fontSize: 10)),
              ])),
        ]),
      );

  Widget _ActionTile(
          String title, String subtitle, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: _bgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withValues(alpha: 0.2)),
              boxShadow: [
                BoxShadow(
                    color: _brown.withValues(alpha: 0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 2))
              ]),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title,
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
                const SizedBox(height: 3),
                Text(subtitle,
                    style: const TextStyle(color: _textMuted, fontSize: 10)),
              ]),
        ),
      );
}
