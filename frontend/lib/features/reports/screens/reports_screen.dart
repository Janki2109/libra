import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/dio_client.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  Map<String, dynamic> _caseReport = {};
  Map<String, dynamic> _revenueReport = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() => _loading = true);
    try {
      final caseRes = await DioClient.instance.get('/reports/cases');
      final revenueRes = await DioClient.instance.get('/reports/revenue');
      setState(() {
        _caseReport = caseRes.data['data'] ?? {};
        _revenueReport = revenueRes.data['data'] ?? {};
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      debugPrint('Reports error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.primaryDark,
        title: const Text('Reports',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.gold),
            onPressed: () {
              HapticFeedback.lightImpact();
              _loadReports();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold))
          : RefreshIndicator(
              color: AppColors.gold,
              onRefresh: _loadReports,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Case Reports
                  _SectionHeader(
                      title: 'Case Reports', icon: Icons.gavel_rounded),
                  const SizedBox(height: 12),

                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.4,
                    children: [
                      _ReportCard(
                        title: 'Total Cases',
                        value: '${_caseReport['total'] ?? 0}',
                        icon: Icons.folder_rounded,
                        color: AppColors.info,
                      ),
                      _ReportCard(
                        title: 'Active',
                        value: '${_caseReport['active'] ?? 0}',
                        icon: Icons.play_circle_rounded,
                        color: AppColors.success,
                      ),
                      _ReportCard(
                        title: 'Closed',
                        value: '${_caseReport['closed'] ?? 0}',
                        icon: Icons.check_circle_rounded,
                        color: AppColors.textMuted,
                      ),
                      _ReportCard(
                        title: 'Won',
                        value: '${_caseReport['won'] ?? 0}',
                        icon: Icons.emoji_events_rounded,
                        color: AppColors.gold,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.bgCard,
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: AppColors.error.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.cancel_rounded,
                            color: AppColors.error, size: 20),
                        const SizedBox(width: 12),
                        const Text('Lost Cases',
                            style: TextStyle(
                                color: AppColors.textSecondary, fontSize: 14)),
                        const Spacer(),
                        Text('${_caseReport['lost'] ?? 0}',
                            style: const TextStyle(
                                color: AppColors.error,
                                fontSize: 20,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Case Progress
                  _SectionHeader(
                      title: 'Case Status Overview',
                      icon: Icons.pie_chart_rounded),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.bgCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      children: [
                        _ProgressRow(
                          label: 'Active',
                          value: _caseReport['active'] ?? 0,
                          total: _caseReport['total'] ?? 1,
                          color: AppColors.success,
                        ),
                        const SizedBox(height: 12),
                        _ProgressRow(
                          label: 'Closed',
                          value: _caseReport['closed'] ?? 0,
                          total: _caseReport['total'] ?? 1,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(height: 12),
                        _ProgressRow(
                          label: 'Won',
                          value: _caseReport['won'] ?? 0,
                          total: _caseReport['total'] ?? 1,
                          color: AppColors.gold,
                        ),
                        const SizedBox(height: 12),
                        _ProgressRow(
                          label: 'Lost',
                          value: _caseReport['lost'] ?? 0,
                          total: _caseReport['total'] ?? 1,
                          color: AppColors.error,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Revenue
                  _SectionHeader(
                      title: 'Revenue Reports',
                      icon: Icons.currency_rupee_rounded),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.bgCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.borderGold),
                    ),
                    child: Column(
                      children: [
                        _RevenueRow(
                          label: 'Total Invoiced',
                          value:
                              '₹${(_revenueReport['total_invoiced'] ?? 0).toStringAsFixed(0)}',
                          color: AppColors.info,
                          icon: Icons.receipt_long_rounded,
                        ),
                        const Divider(color: AppColors.border, height: 24),
                        _RevenueRow(
                          label: 'Total Collected',
                          value:
                              '₹${(_revenueReport['total_paid'] ?? 0).toStringAsFixed(0)}',
                          color: AppColors.success,
                          icon: Icons.check_circle_rounded,
                        ),
                        const Divider(color: AppColors.border, height: 24),
                        _RevenueRow(
                          label: 'Pending Collection',
                          value:
                              '₹${(_revenueReport['total_pending'] ?? 0).toStringAsFixed(0)}',
                          color: AppColors.warning,
                          icon: Icons.pending_rounded,
                        ),
                        const SizedBox(height: 16),
                        Builder(builder: (context) {
                          final invoiced =
                              (_revenueReport['total_invoiced'] ?? 0)
                                  .toDouble();
                          final paid =
                              (_revenueReport['total_paid'] ?? 0).toDouble();
                          final progress =
                              invoiced > 0 ? (paid / invoiced) : 0.0;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Collection Rate',
                                      style: TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 12)),
                                  Text(
                                    '${(progress * 100).toStringAsFixed(1)}%',
                                    style: const TextStyle(
                                        color: AppColors.gold,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: progress.clamp(0.0, 1.0),
                                  backgroundColor: AppColors.surface,
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                          AppColors.gold),
                                  minHeight: 8,
                                ),
                              ),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Quick Links
                  _SectionHeader(
                      title: 'Quick Actions', icon: Icons.flash_on_rounded),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _QuickLink(
                          icon: Icons.people_rounded,
                          label: 'View Clients',
                          color: AppColors.info,
                          onTap: () => context.push('/clients'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _QuickLink(
                          icon: Icons.receipt_long_rounded,
                          label: 'View Invoices',
                          color: AppColors.warning,
                          onTap: () => context.push('/billing'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _QuickLink(
                          icon: Icons.gavel_rounded,
                          label: 'View Cases',
                          color: AppColors.gold,
                          onTap: () => context.push('/cases'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _QuickLink(
                          icon: Icons.event_rounded,
                          label: 'View Hearings',
                          color: AppColors.success,
                          onTap: () => context.push('/hearings'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            gradient: AppColors.goldGradient,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppColors.primary, size: 16),
        ),
        const SizedBox(width: 10),
        Text(title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            )),
      ],
    );
  }
}

class _ReportCard extends StatelessWidget {
  final String title, value;
  final IconData icon;
  final Color color;
  const _ReportCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: TextStyle(
                      color: color, fontSize: 24, fontWeight: FontWeight.w800)),
              Text(title,
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  final String label;
  final int value, total;
  final Color color;
  const _ProgressRow({
    required this.label,
    required this.value,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final progress = total > 0 ? (value / total).clamp(0.0, 1.0) : 0.0;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
            Row(
              children: [
                Text('$value',
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                Text(' / $total',
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 12)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: AppColors.surface,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}

class _RevenueRow extends StatelessWidget {
  final String label, value;
  final Color color;
  final IconData icon;
  const _RevenueRow({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
        ),
        Text(value,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w800, fontSize: 16)),
      ],
    );
  }
}

class _QuickLink extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QuickLink({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
