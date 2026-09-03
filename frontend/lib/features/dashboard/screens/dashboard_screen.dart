import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/services/dio_client.dart';
import '../../../core/services/trial_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/dashboard_provider.dart';
import '../../notifications/providers/notification_provider.dart';

// Normalizes whatever `consultation_type` holds ("Audio Call", "audio_call",
// "Video Call", "Chat", ...) into a fixed action key, the same mapping used
// on the client portal side, so the right button/label renders regardless of
// exact casing/formatting without needing an API change.
String _bookingAction(String rawType) {
  final t = rawType.toLowerCase();
  if (t.contains('audio')) return 'audio';
  if (t.contains('video')) return 'video';
  return 'chat';
}

/// "2026-08-30" -> "30 Aug 2026". Falls back to the raw string if it doesn't
/// parse, so a card never breaks over a formatting edge case.
String _formatBookingDate(String isoDate) {
  try {
    return DateFormat('d MMM yyyy').format(DateTime.parse(isoDate));
  } catch (_) {
    return isoDate;
  }
}

// ── Premium Navy/Gold Theme ─────────────────────────
// Retheme only — every identifier below is used unchanged throughout this
// file, so swapping the values here restyles the whole dashboard (header,
// cards, badges, icons, nav) to the new Libra Law design system without
// touching any layout, data binding, route, or business logic.
const _bg = Color(0xFFF6F5FB);
const _bgCard = Color(0xFFFFFFFF);
const _brown = Color(0xFF150E3D); // primary navy
const _brownDark = Color(0xFF0B0726); // deep navy (header gradient end)
const _brownLight = Color(0xFF3D2C8D); // rich purple
const _textPrimary = Color(0xFF1B1533);
const _textMuted = Color(0xFF7B7594);
const _border = Color(0xFFE6E3F4);
const _gold = Color(0xFFD4AF37);

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  late AnimationController _headerCtrl;
  late AnimationController _cardsCtrl;
  late Animation<double> _headerAnim;
  late Animation<double> _cardsAnim;

  List<dynamic> _upcomingBookings = [];

  Future<void> _loadUpcomingBookings() async {
    try {
      // Same endpoint the existing Consultations screen already uses
      // (GetLawyerConsultations) — just read here too so the dashboard can
      // surface the most relevant one without waiting for a navigation.
      final res = await DioClient.instance.get('/consultations');
      final all = (res.data['data'] as List?) ?? [];
      final upcoming = all
          .where((c) => c['status'] == 'confirmed' || c['status'] == 'pending')
          .toList()
        ..sort((a, b) {
          final da = '${a['consultation_date']} ${a['consultation_time']}';
          final db = '${b['consultation_date']} ${b['consultation_time']}';
          return da.compareTo(db);
        });
      if (mounted) setState(() => _upcomingBookings = upcoming);
    } catch (_) {
      // Booking card is a dashboard convenience, not critical path — if it
      // fails to load, the rest of the dashboard still works and the lawyer
      // can still reach consultations from Quick Actions.
    }
  }

  @override
  void initState() {
    super.initState();
    _headerCtrl = AnimationController(
        duration: const Duration(milliseconds: 900), vsync: this)
      ..forward();
    _cardsCtrl = AnimationController(
        duration: const Duration(milliseconds: 700), vsync: this);
    _headerAnim = CurvedAnimation(parent: _headerCtrl, curve: Curves.easeOut);
    _cardsAnim = CurvedAnimation(parent: _cardsCtrl, curve: Curves.easeOut);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Entitlement comes from the server now — there is no local trial clock
      // to initialise, and clearing app data no longer resets it.
      final status = await TrialService.refresh();
      if (!mounted) return;
      if (status.requiresPlan) {
        context.go('/subscription-wall');
        return;
      }
      context.read<DashboardProvider>().loadDashboard().then((_) {
        if (mounted) _cardsCtrl.forward();
      });
      context.read<NotificationProvider>().loadNotifications();
      _loadUpcomingBookings();
    });
  }

  @override
  void dispose() {
    _headerCtrl.dispose();
    _cardsCtrl.dispose();
    super.dispose();
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good Morning';
    if (h < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  String _fmt(double v) {
    if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(1)}K';
    return '₹${v.toStringAsFixed(0)}';
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take Photo'),
            onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from Gallery'),
            onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (source == null) return;

    final picker = ImagePicker();
    final picked =
        await picker.pickImage(source: source, imageQuality: 70, maxWidth: 400);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final base64Photo = 'data:image/jpeg;base64,${base64Encode(bytes)}';
    if (mounted) {
      final auth = context.read<AuthProvider>();
      final synced = await auth.updateProfilePhoto(base64Photo);
      setState(() {});
      if (!synced && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Photo updated on this device, but could not sync — others may not see it yet.'),
            backgroundColor: Color(0xFFD4A017)));
      }
    }
  }

  String _dayName() {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[DateTime.now().weekday - 1];
  }

  String _monthName() {
    const months = [
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
    ];
    return months[DateTime.now().month - 1];
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final dash = context.watch<DashboardProvider>();
    final notif = context.watch<NotificationProvider>();
    final stats = dash.stats;
    final hasPhoto = auth.user?.profilePhoto.isNotEmpty == true;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: _bg,
        bottomNavigationBar: _BottomNav(),
        body: Column(
          children: [
            // ── FIXED HEADER (light top bar + logo/tagline + icons) ──
            FadeTransition(
              opacity: _headerAnim,
              child: Container(
                color: _bgCard,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: _brown,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.asset('assets/logo/app logo.png',
                                  width: 36, height: 36, fit: BoxFit.cover),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Libra Law',
                                  style: TextStyle(
                                      color: _textPrimary,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.2)),
                              Text('Your Trust, Our Duty',
                                  style: TextStyle(
                                      color: _textMuted.withValues(alpha: 0.9),
                                      fontSize: 9,
                                      fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ]),
                        Row(children: [
                          _IconBtnDark(Icons.chat_bubble_outline_rounded,
                              () => context.push('/chat'),
                              badge: notif.unreadCount),
                          const SizedBox(width: 8),
                          _IconBtnDark(Icons.notifications_none_rounded,
                              () => context.push('/notifications'),
                              badge: notif.unreadCount),
                          const SizedBox(width: 8),
                          _IconBtnDark(Icons.person_outline_rounded,
                              () => context.push('/profile')),
                        ]),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── SCROLLABLE BODY ───────────────────
            Expanded(
              child: RefreshIndicator(
                color: _brown,
                backgroundColor: _bgCard,
                onRefresh: () => Future.wait([
                  context.read<DashboardProvider>().loadDashboard(),
                  _loadUpcomingBookings(),
                ]),
                child: FadeTransition(
                  opacity: _cardsAnim,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                    children: [
                      // ── Hero card (navy, rounded, self-contained) ──
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(18, 20, 14, 34),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFF0B0726),
                                  Color(0xFF150E3D),
                                  Color(0xFF3D2C8D)
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                    color: _brown.withValues(alpha: 0.25),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8)),
                              ],
                            ),
                            child: Stack(
                              children: [
                                Positioned(
                                  right: -10,
                                  top: 0,
                                  bottom: 0,
                                  child: Opacity(
                                    opacity: 0.16,
                                    child: CustomPaint(
                                        size: const Size(110, 140),
                                        painter: _ScalesIconPainter()),
                                  ),
                                ),
                                _ProfileBanner(
                                  auth: auth,
                                  hasPhoto: hasPhoto,
                                  greeting: _greeting(),
                                  onPickPhoto: _pickPhoto,
                                ),
                              ],
                            ),
                          ),
                          // Stat strip overlapping the bottom edge of the hero
                          Positioned(
                            left: 10,
                            right: 10,
                            bottom: -55,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12, horizontal: 6),
                              decoration: BoxDecoration(
                                color: _bgCard,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: _border, width: 0.6),
                                boxShadow: [
                                  BoxShadow(
                                      color: _brown.withValues(alpha: 0.10),
                                      blurRadius: 14,
                                      offset: const Offset(0, 4)),
                                ],
                              ),
                              child: Row(children: [
                                _DateStatCell('Today',
                                    '${_dayName()}, ${DateTime.now().day} ${_monthName()}'),
                                _statDivider(),
                                _StatCard('${stats.totalClients}', 'Clients',
                                    const Color(0xFF4A90D9),
                                    icon: Icons.people_alt_rounded),
                                _statDivider(),
                                _StatCard(
                                    '${stats.activeCases}', 'Cases', _brown,
                                    icon: Icons.folder_rounded),
                                _statDivider(),
                                _StatCard('${stats.upcomingHearings}',
                                    'Hearings', _brownLight,
                                    icon: Icons.gavel_rounded),
                              ]),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 65),

                      // New/Upcoming Booking — placed first so a client's
                      // consultation is the first thing a lawyer sees,
                      // above stats and Quick Actions, with no scrolling.
                      if (_upcomingBookings.isNotEmpty) ...[
                        _NewBookingSection(bookings: _upcomingBookings),
                        const SizedBox(height: 20),
                      ],

                      // Overview
                      _SectionLabel('Overview'),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                            child: _OverviewCard(
                                label: 'Active Cases',
                                value: '${stats.activeCases}',
                                icon: Icons.gavel_rounded,
                                color: _brown,
                                onTap: () => context.push('/cases'))),
                        const SizedBox(width: 10),
                        Expanded(
                            child: _OverviewCard(
                                label: "Today's Hearings",
                                value: '${stats.todayHearings}',
                                icon: Icons.event_rounded,
                                color: const Color(0xFF4A90D9),
                                onTap: () => context.push('/hearings'))),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                            child: _OverviewCard(
                                label: 'Won Cases',
                                value: '${stats.wonCases}',
                                icon: Icons.emoji_events_rounded,
                                color: const Color(0xFF2E8B57),
                                onTap: () => context.push('/cases'))),
                        const SizedBox(width: 10),
                        Expanded(
                            child: _OverviewCard(
                                label: 'Pending Bills',
                                value: _fmt(stats.pendingBills),
                                icon: Icons.receipt_long_rounded,
                                color: const Color(0xFFD9534F),
                                onTap: () => context.push('/billing'))),
                      ]),
                      const SizedBox(height: 24),

                      // Quick Actions
                      _SectionLabel('Quick Actions'),
                      const SizedBox(height: 12),
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 4,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 1.05,
                        children: [
                          _ActionTile(
                              'Add Client',
                              Icons.person_add_outlined,
                              const Color(0xFF4A90D9),
                              () => context.push('/clients/add')),
                          _ActionTile('New Case', Icons.gavel_rounded, _brown,
                              () => context.push('/cases/add')),
                          _ActionTile('Hearing', Icons.event_note_rounded,
                              _brownLight, () => context.push('/hearings/add')),
                          _ActionTile(
                              'Invoice',
                              Icons.receipt_rounded,
                              const Color(0xFF2E8B57),
                              () => context.push('/billing/create')),
                          _ActionTile(
                              'Messages',
                              Icons.chat_bubble_outline_rounded,
                              _brownDark,
                              () => context.push('/chat')),
                          _ActionTile('Documents', Icons.folder_open_rounded,
                              _brownLight, () => context.push('/documents')),
                          _ActionTile(
                              'Verify Pay',
                              Icons.verified_rounded,
                              const Color(0xFF2E8B57),
                              () => context.push('/billing/verify')),
                          _ActionTile(
                              'AI Research',
                              Icons.auto_stories_rounded,
                              const Color(0xFF7C3AED),
                              () => context.push('/lawyer/ai-research')),
                          _ActionTile(
                              'Smart Draft',
                              Icons.edit_document,
                              const Color(0xFF0288D1),
                              () => context.push('/lawyer/ai-drafting')),
                          _ActionTile(
                              'eCourts',
                              Icons.account_balance_outlined,
                              _brownLight,
                              () => launchUrl(
                                  Uri.parse('https://services.ecourts.gov.in'),
                                  mode: LaunchMode.externalApplication)),
                          _ActionTile(
                              'Consults',
                              Icons.calendar_today_rounded,
                              const Color(0xFF2E8B57),
                              () => context.push('/lawyer/consultations')),
                        ],
                      ),
                      const SizedBox(height: 20),

                      _UpgradeBanner(
                          onTap: () => context.push('/subscription')),
                      const SizedBox(height: 24),

                      if (stats.pendingBills > 0)
                        _AlertBanner(
                            icon: Icons.warning_amber_rounded,
                            color: _brown,
                            title: 'Pending Bills',
                            subtitle:
                                '${_fmt(stats.pendingBills)} pending from clients',
                            onTap: () => context.push('/billing')),

                      if (dash.todayHearings.isNotEmpty) ...[
                        _SectionHeader("Today's Hearings",
                            () => context.push('/hearings')),
                        const SizedBox(height: 10),
                        ...dash.todayHearings.map((h) => _HearingTile(h)),
                        const SizedBox(height: 24),
                      ],

                      if (dash.recentCases.isNotEmpty) ...[
                        _SectionHeader(
                            'Recent Cases', () => context.push('/cases')),
                        const SizedBox(height: 10),
                        ...dash.recentCases.map((c) => _CaseTile(c)),
                      ],

                      const SizedBox(height: 100),
                    ],
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

// ── New / Upcoming Booking Section ─────────────────
// The most recent client booking, shown prominently at the top of the
// dashboard. Reuses the same GET /consultations data the Consultations
// screen already renders — no new endpoint, no new booking logic.
class _NewBookingSection extends StatelessWidget {
  final List<dynamic> bookings;
  const _NewBookingSection({required this.bookings});

  @override
  Widget build(BuildContext context) {
    final top = bookings.first;
    final rest = bookings.skip(1).take(3).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SectionLabel('New Booking'),
      const SizedBox(height: 10),
      _BookingCard(booking: top, prominent: true),
      if (rest.isNotEmpty) ...[
        const SizedBox(height: 10),
        ...rest.map((b) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _BookingCard(booking: b, prominent: false))),
      ],
      if (bookings.length > 4)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: GestureDetector(
            onTap: () => context.push('/lawyer/consultations'),
            child: Text('+ ${bookings.length - 4} more booking(s)',
                style: const TextStyle(
                    color: _brown, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ),
    ]);
  }
}

class _BookingCard extends StatelessWidget {
  final dynamic booking;
  final bool prominent;
  const _BookingCard({required this.booking, required this.prominent});

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message), backgroundColor: const Color(0xFFD9534F)));
  }

  /// Rings the client through the existing push-notification pipeline (see
  /// InitiateConsultationCall on the backend), then joins the real in-app
  /// WebRTC call session as the caller. If the ring itself fails (e.g. the
  /// client has no registered device) the lawyer still joins the call —
  /// the client can still accept a missed-notification call from their own
  /// Consultations screen.
  Future<void> _ringClient() async {
    final id = booking['id'];
    if (id == null) return;
    try {
      await DioClient.instance.post('/consultations/$id/call');
    } catch (_) {}
  }

  Future<void> _joinCall(BuildContext context, {required bool video}) async {
    final id = booking['id'];
    if (id == null) {
      _showError(context, 'This booking is missing its consultation id.');
      return;
    }
    unawaited(_ringClient());
    context.push('/call', extra: {
      'consultationId': id.toString(),
      'peerName': (booking['client_name'] ?? 'Client').toString(),
      'video': video,
      'isCaller': true,
    });
  }

  Future<void> _callClient(BuildContext context) => _joinCall(context, video: false);

  Future<void> _startVideoCall(BuildContext context) =>
      _joinCall(context, video: true);

  void _openChat(BuildContext context) {
    // The lawyer side has one chat entry point today (the conversation list
    // — the same place "Messages" in Quick Actions leads to); a client who
    // has messaged from their portal already has a room waiting there.
    context.push('/chat');
  }

  @override
  Widget build(BuildContext context) {
    final status = (booking['status'] ?? 'pending').toString();
    final rawType = (booking['consultation_type'] ?? '').toString();
    final action = _bookingAction(rawType);
    final isConfirmed = status == 'confirmed';
    final statusColor =
        isConfirmed ? const Color(0xFF2E8B57) : const Color(0xFFD4A017);

    final actionColor = action == 'audio'
        ? const Color(0xFF4A90D9)
        : action == 'video'
            ? const Color(0xFF7C3AED)
            : _brown;
    final actionIcon = action == 'audio'
        ? Icons.phone_rounded
        : action == 'video'
            ? Icons.videocam_rounded
            : Icons.chat_rounded;
    final actionLabel = action == 'audio'
        ? 'Call Client'
        : action == 'video'
            ? 'Video Call'
            : 'Chat with Client';
    final typeEmoji = action == 'audio'
        ? '📞'
        : action == 'video'
            ? '🎥'
            : '💬';
    final typeLabel = rawType.isNotEmpty ? rawType : 'Consultation';

    final date = (booking['consultation_date'] ?? '').toString();
    final time = (booking['consultation_time'] ?? '').toString();
    final clientName = (booking['client_name'] ?? 'Client').toString();

    return Container(
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: statusColor.withValues(alpha: 0.35),
            width: prominent ? 1.4 : 0.8),
        boxShadow: [
          BoxShadow(
              color: _brown.withValues(alpha: prominent ? 0.10 : 0.05),
              blurRadius: prominent ? 14 : 8,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(children: [
        Container(
            height: 4,
            decoration: BoxDecoration(
                color: statusColor,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)))),
        Padding(
          padding: EdgeInsets.all(prominent ? 14 : 12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6)),
                child: Text(status.toUpperCase(),
                    style: TextStyle(
                        color: statusColor,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4)),
              ),
              const Spacer(),
              Icon(Icons.event_available_rounded,
                  color: statusColor.withValues(alpha: 0.6), size: 14),
            ]),
            const SizedBox(height: 8),
            Text(clientName,
                style: TextStyle(
                    color: _textPrimary,
                    fontSize: prominent ? 16 : 14,
                    fontWeight: FontWeight.w800),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('$typeEmoji $typeLabel',
                    style: TextStyle(
                        color: actionColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ],
            ),
            if (date.isNotEmpty || time.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 14, runSpacing: 4, children: [
                if (date.isNotEmpty)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.calendar_today_rounded,
                        color: _brown, size: 13),
                    const SizedBox(width: 5),
                    Text(_formatBookingDate(date),
                        style: const TextStyle(
                            color: _textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ]),
                if (time.isNotEmpty)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.access_time_rounded,
                        color: _brown, size: 13),
                    const SizedBox(width: 5),
                    Text(time,
                        style: const TextStyle(
                            color: _textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ]),
              ]),
            ],
            if (isConfirmed) ...[
              SizedBox(height: prominent ? 12 : 10),
              SizedBox(
                width: double.infinity,
                child: Material(
                  color: actionColor,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      HapticFeedback.heavyImpact();
                      if (action == 'audio') {
                        _callClient(context);
                      } else if (action == 'video') {
                        _startVideoCall(context);
                      } else {
                        _openChat(context);
                      }
                    },
                    child: Padding(
                      padding:
                          EdgeInsets.symmetric(vertical: prominent ? 11 : 9),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(actionIcon, color: Colors.white, size: 16),
                          const SizedBox(width: 6),
                          Flexible(
                              child: Text(actionLabel,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13))),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}

// ── Profile Banner ─────────────────────────────────
class _ProfileBanner extends StatelessWidget {
  final AuthProvider auth;
  final bool hasPhoto;
  final String greeting;
  final VoidCallback onPickPhoto;
  const _ProfileBanner({
    required this.auth,
    required this.hasPhoto,
    required this.greeting,
    required this.onPickPhoto,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // ── Big cutout photo - no box, no border ──────
        GestureDetector(
          onTap: onPickPhoto,
          child: Stack(clipBehavior: Clip.none, children: [
            SizedBox(
              width: 110,
              height: 155,
              child: hasPhoto
                  ? Image.memory(
                      base64Decode(auth.user!.profilePhoto
                          .replaceFirst('data:image/jpeg;base64,', '')),
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      errorBuilder: (_, __, ___) => _initials(),
                    )
                  : _initials(),
            ),
            Positioned(
                bottom: 6,
                right: 6,
                child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Colors.black26, blurRadius: 4)
                        ]),
                    child: const Icon(Icons.camera_alt_rounded,
                        color: _brown, size: 13))),
          ]),
        ),
        const SizedBox(width: 14),

        // ── Info ────────────────────────────────────
        Expanded(
            child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(greeting,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 11)),
              const SizedBox(height: 3),
              // Big bold name
              Text(auth.user?.name ?? 'Advocate',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              // Advocate badge — gold accent per the premium branding
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                    color: _gold.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _gold.withValues(alpha: 0.5))),
                child: const Text('ADVOCATE',
                    style: TextStyle(
                        color: _gold,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2)),
              ),
              const SizedBox(height: 8),
              // Verified + Active
              Row(children: [
                _Pill(Icons.verified_rounded, 'Verified',
                    const Color(0xFF4CAF50)),
                const SizedBox(width: 6),
                _Pill(Icons.circle, 'Active', const Color(0xFFB79AF0)),
              ]),
            ],
          ),
        )),
      ],
    );
  }

  Widget _Pill(IconData icon, String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.5))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 9),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 10, fontWeight: FontWeight.w700)),
        ]),
      );

  Widget _initials() => SizedBox(
      width: 110,
      height: 155,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle),
            child: Center(
                child: Text(auth.user?.initials ?? 'L',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 32)))),
      ]));
}

// ── Date cell (first item of the hero stat strip only) ──
// Same icon style/size and cell layout as _StatCard, just two labeled lines
// ("Today" / "Sat, 29 Aug") instead of one bold value + muted label.
class _DateStatCell extends StatelessWidget {
  final String today, dateLabel;
  const _DateStatCell(this.today, this.dateLabel);

  @override
  Widget build(BuildContext context) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.calendar_today_rounded, color: _brown, size: 16),
            const SizedBox(height: 4),
            Text(today,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _textMuted, fontSize: 9)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(dateLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: _brown,
                      fontSize: 13,
                      fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
      );
}

// ── Stat Card (compact, used inline inside the hero stat strip) ──
class _StatCard extends StatelessWidget {
  final String value, label;
  final Color color;
  final IconData? icon;
  const _StatCard(this.value, this.label, this.color, {this.icon});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon, color: color, size: 16),
              const SizedBox(height: 4),
            ],
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: color, fontSize: 13, fontWeight: FontWeight.w800)),
            ),
            if (label.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(label,
                  style: const TextStyle(color: _textMuted, fontSize: 9),
                  overflow: TextOverflow.ellipsis),
            ],
          ]),
        ),
      );
}

Widget _statDivider() => Container(
      width: 0.8,
      height: 32,
      color: _border,
    );

// ── Small justice-scales glyph used as a decorative watermark ──
class _ScalesIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    final cx = size.width * 0.5;
    final cy = size.height * 0.42;
    final s = size.width * 0.38;

    canvas.drawLine(Offset(cx, cy - s * 1.1), Offset(cx, cy + s * 0.3), paint);
    canvas.drawLine(Offset(cx - s * 0.05, cy + s * 0.35),
        Offset(cx + s * 0.05, cy + s * 0.35), paint);
    canvas.drawLine(Offset(cx - s, cy), Offset(cx + s, cy), paint);
    canvas.drawLine(
        Offset(cx - s, cy), Offset(cx - s * 1.35, cy + s * 0.85), paint);
    canvas.drawLine(
        Offset(cx - s, cy), Offset(cx - s * 0.65, cy + s * 0.85), paint);
    canvas.drawArc(
        Rect.fromCenter(
            center: Offset(cx - s, cy + s * 0.85),
            width: s * 0.7,
            height: s * 0.26),
        math.pi,
        math.pi,
        false,
        paint);
    canvas.drawLine(
        Offset(cx + s, cy), Offset(cx + s * 1.35, cy + s * 0.85), paint);
    canvas.drawLine(
        Offset(cx + s, cy), Offset(cx + s * 0.65, cy + s * 0.85), paint);
    canvas.drawArc(
        Rect.fromCenter(
            center: Offset(cx + s, cy + s * 0.85),
            width: s * 0.7,
            height: s * 0.26),
        math.pi,
        math.pi,
        false,
        paint);
    canvas.drawLine(
        Offset(cx, cy + s * 1.35), Offset(cx - s * 0.5, cy + s * 1.55), paint);
    canvas.drawLine(
        Offset(cx, cy + s * 1.35), Offset(cx + s * 0.5, cy + s * 1.55), paint);
    canvas.drawLine(Offset(cx - s * 0.6, cy + s * 1.55),
        Offset(cx + s * 0.6, cy + s * 1.55), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Icon Button (dark icon on light header) ───────────
class _IconBtnDark extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final int badge;
  const _IconBtnDark(this.icon, this.onTap, {this.badge = 0});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Stack(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _brown.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border, width: 0.8),
            ),
            child: Icon(icon, color: _brown, size: 18),
          ),
          if (badge > 0)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: 13,
                height: 13,
                decoration: const BoxDecoration(
                    color: Color(0xFFD9534F), shape: BoxShape.circle),
                child: Center(
                  child: Text('$badge',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 7,
                          fontWeight: FontWeight.w800)),
                ),
              ),
            ),
        ]),
      );
}

// ── Section Label ──────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
                color: _brown, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(text,
            style: const TextStyle(
                color: _textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2)),
      ]);
}

// ── Section Header ─────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback onSeeAll;
  const _SectionHeader(this.title, this.onSeeAll);
  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _SectionLabel(title),
          GestureDetector(
            onTap: onSeeAll,
            child: const Text('See All',
                style: TextStyle(
                    color: _brown, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ],
      );
}

// ── Overview Card ──────────────────────────────────
class _OverviewCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _OverviewCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(16),
            border:
                Border.all(color: color.withValues(alpha: 0.18), width: 0.8),
          ),
          child: Stack(children: [
            Positioned(
              right: -6,
              bottom: -6,
              child: Icon(icon, color: color.withValues(alpha: 0.10), size: 46),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(10)),
                    child: Icon(icon, color: color, size: 17),
                  ),
                  const Spacer(),
                ]),
                const SizedBox(height: 10),
                Text(value,
                    style: const TextStyle(
                        color: _textPrimary,
                        fontSize: 19,
                        fontWeight: FontWeight.w800)),
                Text(label,
                    style: const TextStyle(color: _textMuted, fontSize: 11),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('View Details',
                      style: TextStyle(
                          color: color,
                          fontSize: 10,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(width: 2),
                  Icon(Icons.arrow_forward_rounded, color: color, size: 12),
                ]),
              ],
            ),
          ]),
        ),
      );
}

// ── Action Tile ────────────────────────────────────
class _ActionTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionTile(this.label, this.icon, this.color, this.onTap);

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          decoration: BoxDecoration(
            color: _bgCard,
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: color.withValues(alpha: 0.15), width: 0.8),
            boxShadow: [
              BoxShadow(
                  color: color.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 3)),
            ],
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    color.withValues(alpha: 0.18),
                    color.withValues(alpha: 0.08)
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 15),
            ),
            const SizedBox(height: 5),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(label,
                  style: TextStyle(
                      color: _textPrimary,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center),
            ),
          ]),
        ),
      );
}

// ── Alert Banner ───────────────────────────────────
// ── Upgrade to Premium banner (links to the existing /subscription route) ──
class _UpgradeBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _UpgradeBanner({required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              colors: [Color(0xFF0B0726), Color(0xFF150E3D), Color(0xFF3D2C8D)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                  color: _brown.withValues(alpha: 0.2),
                  blurRadius: 12,
                  offset: const Offset(0, 4)),
            ],
          ),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.2), shape: BoxShape.circle),
              child: const Icon(Icons.workspace_premium_rounded,
                  color: _gold, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Upgrade to Premium',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800)),
                  Text('Unlock advanced features and grow your practice',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 10),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                  color: _gold, borderRadius: BorderRadius.circular(10)),
              child: const Text('Upgrade',
                  style: TextStyle(
                      color: Color(0xFF150E3D),
                      fontSize: 11,
                      fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
      );
}

class _AlertBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, subtitle;
  final VoidCallback onTap;
  const _AlertBanner({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
          ),
          child: Row(children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
                Text(subtitle,
                    style: const TextStyle(color: _textMuted, fontSize: 11)),
              ],
            )),
            Icon(Icons.arrow_forward_ios_rounded, color: color, size: 12),
          ]),
        ),
      );
}

// ── Hearing Tile ───────────────────────────────────
class _HearingTile extends StatelessWidget {
  final dynamic h;
  const _HearingTile(this.h);
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border, width: 0.6),
          boxShadow: [
            BoxShadow(
                color: _brown.withValues(alpha: 0.05),
                blurRadius: 6,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: const Color(0xFF4A90D9).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.event_rounded,
                color: Color(0xFF4A90D9), size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(h['case_title'] ?? 'Hearing',
                  style: const TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              Text(h['court_name'] ?? '',
                  style: const TextStyle(color: _textMuted, fontSize: 10)),
            ],
          )),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: const Color(0xFF4A90D9).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6)),
            child: Text(h['status'] ?? 'scheduled',
                style: const TextStyle(
                    color: Color(0xFF4A90D9),
                    fontSize: 9,
                    fontWeight: FontWeight.w600)),
          ),
        ]),
      );
}

// ── Case Tile ──────────────────────────────────────
class _CaseTile extends StatelessWidget {
  final dynamic c;
  const _CaseTile(this.c);
  @override
  Widget build(BuildContext context) {
    final status = c['status'] ?? 'active';
    final Color sc;
    switch (status) {
      case 'won':
        sc = _brown;
        break;
      case 'lost':
        sc = const Color(0xFFD9534F);
        break;
      case 'pending':
        sc = _brownLight;
        break;
      default:
        sc = const Color(0xFF2E8B57);
    }
    return GestureDetector(
      onTap: () => context.push('/cases/${c['id']}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border, width: 0.6),
          boxShadow: [
            BoxShadow(
                color: _brown.withValues(alpha: 0.05),
                blurRadius: 6,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: sc.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.gavel_rounded, color: sc, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c['case_title'] ?? '',
                  style: const TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              Text(c['client_name'] ?? '',
                  style: const TextStyle(color: _textMuted, fontSize: 10)),
            ],
          )),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: sc.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6)),
            child: Text(status,
                style: TextStyle(
                    color: sc, fontSize: 9, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }
}

// ── Bottom Nav ─────────────────────────────────────
class _BottomNav extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: _bgCard,
          border: const Border(top: BorderSide(color: _border, width: 0.8)),
          boxShadow: [
            BoxShadow(
                color: _brown.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, -3)),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(Icons.dashboard_rounded, 'Home', true, () {}),
                _NavItem(Icons.people_rounded, 'Clients', false,
                    () => context.push('/clients')),
                _NavItem(Icons.gavel_rounded, 'Cases', false,
                    () => context.push('/cases')),
                _NavItem(Icons.chat_bubble_outline_rounded, 'Chat', false,
                    () => context.push('/chat')),
                _NavItem(Icons.account_balance_wallet_rounded, 'Billing',
                    false, () => context.push('/lawyer/earnings')),
                _NavItem(Icons.person_outline_rounded, 'Profile', false,
                    () => context.push('/profile')),
              ],
            ),
          ),
        ),
      );
}

/// The tools grid that used to open from the bottom nav's "More" tab.
/// "More" was replaced with "Profile" in the bottom nav (Home | Clients |
/// Cases | Chat | Billing | Profile) — everything that lived here (Hearings,
/// Documents, Verify Pay, AI Research, Smart Draft, eCourts, Consults,
/// Profile, Notifications, Settings) stays reachable via a "More Tools" row
/// on the Profile screen, so nothing that was here becomes unreachable.
void showLawyerMoreMenu(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: _bgCard,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheetCtx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: _border, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 4,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1.05,
            children: [
              _moreTile(sheetCtx, 'Hearings', Icons.event_note_rounded,
                  _brownLight, () => context.push('/hearings')),
              _moreTile(sheetCtx, 'Billing', Icons.receipt_long_rounded,
                  const Color(0xFF2E8B57), () => context.push('/billing')),
              _moreTile(sheetCtx, 'Documents', Icons.folder_open_rounded,
                  _brownLight, () => context.push('/documents')),
              _moreTile(
                  sheetCtx,
                  'Verify Pay',
                  Icons.verified_rounded,
                  const Color(0xFF2E8B57),
                  () => context.push('/billing/verify')),
              _moreTile(
                  sheetCtx,
                  'AI Research',
                  Icons.auto_stories_rounded,
                  const Color(0xFF7C3AED),
                  () => context.push('/lawyer/ai-research')),
              _moreTile(
                  sheetCtx,
                  'Smart Draft',
                  Icons.edit_document,
                  const Color(0xFF0288D1),
                  () => context.push('/lawyer/ai-drafting')),
              _moreTile(
                  sheetCtx,
                  'eCourts',
                  Icons.account_balance_outlined,
                  _brownLight,
                  () => launchUrl(Uri.parse('https://services.ecourts.gov.in'),
                      mode: LaunchMode.externalApplication)),
              _moreTile(
                  sheetCtx,
                  'Consults',
                  Icons.calendar_today_rounded,
                  const Color(0xFF2E8B57),
                  () => context.push('/lawyer/consultations')),
              _moreTile(sheetCtx, 'Profile', Icons.person_outline_rounded,
                  _brown, () => context.push('/profile')),
              _moreTile(
                  sheetCtx,
                  'Notifications',
                  Icons.notifications_none_rounded,
                  const Color(0xFF4A90D9),
                  () => context.push('/notifications')),
              _moreTile(sheetCtx, 'Settings', Icons.settings_outlined,
                  _textMuted, () => context.push('/settings')),
            ],
          ),
        ]),
      ),
    ),
  );
}

Widget _moreTile(BuildContext sheetCtx, String label, IconData icon,
        Color color, VoidCallback onTap) =>
    _ActionTile(label, icon, color, () {
      Navigator.of(sheetCtx).pop();
      onTap();
    });

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _NavItem(this.icon, this.label, this.selected, this.onTap);
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          // Tightened from horizontal:12 to fit 6 items (was 5) without
          // crowding on narrow phones — same colors/shape/AnimatedContainer,
          // just less padding per item.
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? _brown : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: selected ? Colors.white : _textMuted, size: 20),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    color: selected ? Colors.white : _textMuted,
                    fontSize: 9,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400)),
          ]),
        ),
      );
}
