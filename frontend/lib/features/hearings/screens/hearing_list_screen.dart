import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/hearing_provider.dart';

const _bg = Color(0xFFF6F5FB);
const _bgCard = Color(0xFFFFFFFF);
const _brown = Color(0xFF150E3D);
const _brownDark = Color(0xFF0B0726);
const _border = Color(0xFFE6E3F4);
const _textPri = Color(0xFF1B1533);
const _textMuted = Color(0xFF7B7594);

class HearingListScreen extends StatefulWidget {
  const HearingListScreen({super.key});
  @override
  State<HearingListScreen> createState() => _HearingListScreenState();
}

class _HearingListScreenState extends State<HearingListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HearingProvider>().loadHearings();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HearingProvider>();
    final today = DateTime.now();
    final todayStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    final todayHearings = provider.hearings
        .where((h) =>
            (h['hearing_date'] ?? '').toString().substring(0, 10) == todayStr)
        .toList();
    final upcomingHearings = provider.hearings
        .where((h) =>
            (h['hearing_date'] ?? '')
                .toString()
                .substring(0, 10)
                .compareTo(todayStr) >
            0)
        .toList();

    return Scaffold(
      backgroundColor: _bg,
      body: Container(
        child: Column(children: [
          // Brown header
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [_brown, _brownDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
            ),
            child: SafeArea(
                bottom: false,
                child: Column(children: [
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(children: [
                      IconButton(
                          icon: const Icon(Icons.arrow_back_rounded,
                              color: Colors.white),
                          onPressed: () => context.pop()),
                      const Expanded(
                          child: Text('Hearings',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700))),
                      IconButton(
                        icon: const Icon(Icons.add_rounded,
                            color: Color(0xFFFFD700)),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          context.push('/hearings/add').then((_) =>
                              context.read<HearingProvider>().loadHearings());
                        },
                      ),
                    ]),
                  ),
                  TabBar(
                    controller: _tabController,
                    indicatorColor: const Color(0xFFFFD700),
                    indicatorWeight: 3,
                    labelColor: const Color(0xFFFFD700),
                    unselectedLabelColor: Colors.white60,
                    tabs: [
                      Tab(text: 'Today (${todayHearings.length})'),
                      Tab(text: 'Upcoming (${upcomingHearings.length})'),
                    ],
                  ),
                ])),
          ),

          Expanded(
            child: provider.loading
                ? const Center(child: CircularProgressIndicator(color: _brown))
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _HearingTabView(
                          hearings: todayHearings,
                          emptyMessage: 'No hearings today',
                          emptyIcon: Icons.event_available_rounded),
                      _HearingTabView(
                          hearings: upcomingHearings,
                          emptyMessage: 'No upcoming hearings',
                          emptyIcon: Icons.calendar_today_rounded),
                    ],
                  ),
          ),
        ]),
        // floatingActionButton: FloatingActionButton(
        //   onPressed: () {
        //     HapticFeedback.lightImpact();
        //     context
        //         .push('/hearings/add')
        //         .then((_) => context.read<HearingProvider>().loadHearings());
        //   },
        //   backgroundColor: _brown,
        //   child: const Icon(Icons.add_rounded, color: Colors.white),
        // ),
      ),
    );
  }
}

class _HearingTabView extends StatelessWidget {
  final List<dynamic> hearings;
  final String emptyMessage;
  final IconData emptyIcon;
  const _HearingTabView(
      {required this.hearings,
      required this.emptyMessage,
      required this.emptyIcon});

  @override
  Widget build(BuildContext context) {
    if (hearings.isEmpty) {
      return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
                color: _brown.withValues(alpha: 0.08), shape: BoxShape.circle),
            child: Icon(emptyIcon, color: _brown.withValues(alpha: 0.5), size: 40)),
        const SizedBox(height: 16),
        Text(emptyMessage,
            style: const TextStyle(
                color: _textPri, fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        const Text('Schedule a new hearing',
            style: TextStyle(color: _textMuted, fontSize: 13)),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: () => context.push('/hearings/add'),
          icon: const Icon(Icons.add_rounded, color: Colors.white),
          label: const Text('Schedule Hearing',
              style: TextStyle(color: Colors.white)),
          style: ElevatedButton.styleFrom(
              backgroundColor: _brown,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
        ),
      ]));
    }

    return RefreshIndicator(
      color: _brown,
      backgroundColor: _bgCard,
      onRefresh: () => context.read<HearingProvider>().loadHearings(),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: hearings.length,
        // ✅ FIXED: tap opens hearing details
        itemBuilder: (_, i) => _HearingCard(
          hearing: hearings[i],
          onTap: () => context
              .push('/hearings/${hearings[i]['id']}')
              .then((_) => context.read<HearingProvider>().loadHearings()),
        ),
      ),
    );
  }
}

class _HearingCard extends StatelessWidget {
  final dynamic hearing;
  final VoidCallback onTap;
  const _HearingCard({required this.hearing, required this.onTap});

  Color _statusColor(String s) {
    switch (s) {
      case 'completed':
        return const Color(0xFF2E8B57);
      case 'adjourned':
        return const Color(0xFFD4A017);
      case 'cancelled':
        return const Color(0xFFD9534F);
      default:
        return const Color(0xFF4A90D9);
    }
  }

  String _monthName(int m) => [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ][m - 1];

  @override
  Widget build(BuildContext context) {
    final status = hearing['status'] ?? 'scheduled';
    final statusColor = _statusColor(status);
    final date = (hearing['hearing_date'] ?? '').toString();
    final shortDate = date.length >= 10 ? date.substring(0, 10) : date;
    final day = shortDate.length >= 10 ? shortDate.substring(8, 10) : '--';
    final month = shortDate.length >= 7
        ? _monthName(int.tryParse(shortDate.substring(5, 7)) ?? 1)
        : '--';

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: statusColor.withValues(alpha: 0.25)),
          boxShadow: [
            BoxShadow(
                color: _brown.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(children: [
          // Top colored bar
          Container(
              height: 4,
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              )),
          Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                // Date box
                Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                          colors: [_brown, _brown.withValues(alpha: 0.7)]),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(day,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16)),
                          Text(month,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 10)),
                        ])),
                const SizedBox(width: 14),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(hearing['case_title'] ?? 'Case Hearing',
                          style: const TextStyle(
                              color: _textPri,
                              fontWeight: FontWeight.w700,
                              fontSize: 15),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text(hearing['purpose'] ?? '',
                          style:
                              const TextStyle(color: _textMuted, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ])),
                // Status badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: statusColor.withValues(alpha: 0.3))),
                  child: Text(status.toUpperCase(),
                      style: TextStyle(
                          color: statusColor,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5)),
                ),
              ]),
              const SizedBox(height: 12),
              Divider(color: _border, height: 1, thickness: 0.6),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: _Detail(Icons.account_balance_outlined, 'Court',
                        hearing['court_name'] ?? '-')),
                Expanded(
                    child: _Detail(Icons.access_time_rounded, 'Time',
                        hearing['hearing_time'] ?? 'TBD')),
                // ✅ Arrow to show it's tappable
                const Icon(Icons.arrow_forward_ios_rounded,
                    color: _textMuted, size: 13),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _Detail(this.icon, this.label, this.value);
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, color: _textMuted, size: 14),
        const SizedBox(width: 6),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: _textMuted, fontSize: 10)),
          Text(value,
              style: const TextStyle(
                  color: _textPri, fontSize: 12, fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ])),
      ]);
}
