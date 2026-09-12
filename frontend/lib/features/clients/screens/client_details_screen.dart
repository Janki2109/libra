import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/dio_client.dart';
import '../../../core/services/realtime_events.dart';
import '../../documents/widgets/document_upload_sheet.dart';

const _bg = Color(0xFFF6F5FB);
const _bgCard = Color(0xFFFFFFFF);
const _brown = Color(0xFF150E3D);
const _brownLight = Color(0xFF3D2C8D);
const _border = Color(0xFFE6E3F4);
const _textPri = Color(0xFF2C1A0E);
const _textMuted = Color(0xFF3D2C8D);

class ClientDetailsScreen extends StatefulWidget {
  final String clientId;
  const ClientDetailsScreen({super.key, required this.clientId});
  @override
  State<ClientDetailsScreen> createState() => _ClientDetailsScreenState();
}

class _ClientDetailsScreenState extends State<ClientDetailsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic>? _client;
  List<dynamic> _cases = [];
  List<dynamic> _documents = [];
  List<dynamic> _hearings = [];
  List<dynamic> _bookings = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadClient();
    // New bookings and status transitions (pending/accepted/rejected/
    // completed/expired) push through the existing FCM-backed event bus —
    // refresh this client's booking history without a manual pull.
    RealtimeEvents.instance.addListener(_onRealtimeEvent);
  }

  void _onRealtimeEvent() {
    if (RealtimeEvents.instance.matches(
        ['booking_', 'incoming_call_', 'chat_session_started', 'call_response_'])) {
      _loadBookings();
    }
  }

  @override
  void dispose() {
    RealtimeEvents.instance.removeListener(_onRealtimeEvent);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadBookings() async {
    try {
      final res =
          await DioClient.instance.get('/clients/${widget.clientId}/bookings');
      if (mounted) {
        setState(() {
          _bookings = res.data['data'] as List? ?? [];
        });
      }
    } catch (e) {
      debugPrint('Bookings error: $e');
    }
  }

  Future<void> _loadClient() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await DioClient.instance.get('/clients/${widget.clientId}');
      if (res.data['success'] == true) {
        setState(() {
          _client = res.data['data'];
          _loading = false;
        });
      } else {
        setState(() {
          _error = res.data['message'] ?? 'Failed to load';
          _loading = false;
        });
      }
      // Filtered server-side by client_id now — the old client-side
      // name-matching silently showed nothing for two clients sharing a name
      // and broke the moment a client was renamed after a case was filed.
      try {
        final casesRes = await DioClient.instance
            .get('/cases', queryParameters: {'client_id': widget.clientId});
        setState(() {
          _cases = casesRes.data['data'] as List;
        });
      } catch (e) {
        debugPrint('Cases error: $e');
      }
      try {
        final docsRes = await DioClient.instance.get('/documents',
            queryParameters: {'client_id': widget.clientId});
        setState(() {
          _documents = docsRes.data['data'] as List;
        });
      } catch (e) {
        debugPrint('Documents error: $e');
      }
      try {
        final hearingsRes = await DioClient.instance.get('/hearings',
            queryParameters: {'client_id': widget.clientId});
        setState(() {
          _hearings = hearingsRes.data['data'] as List;
        });
      } catch (e) {
        debugPrint('Hearings error: $e');
      }
      await _loadBookings();
    } catch (e) {
      setState(() {
        _error = 'Failed to load client details';
        _loading = false;
      });
    }
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : 'C';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: CircularProgressIndicator(color: _brown)),
      );
    }

    if (_error != null || _client == null) {
      return Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _brown,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => context.pop(),
          ),
          title: const Text('Client Details',
              style: TextStyle(color: Colors.white)),
        ),
        body: Center(
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.error_outline_rounded,
              color: Color(0xFFD9534F), size: 60),
          const SizedBox(height: 16),
          Text(_error ?? 'Client not found',
              style: const TextStyle(color: _textMuted, fontSize: 16)),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loadClient,
            style: ElevatedButton.styleFrom(backgroundColor: _brown),
            child: const Text('Retry', style: TextStyle(color: Colors.white)),
          ),
        ])),
      );
    }

    final isActive = _client!['is_active'] ?? true;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _bg,
        body: CustomScrollView(slivers: [
          // ── Header ──
          SliverAppBar(
            expandedHeight: 210,
            pinned: true,
            backgroundColor: _brown,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () => context.pop(),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_rounded, color: Color(0xFFFFD700)),
                onPressed: () => context
                    .push('/clients/${widget.clientId}/edit')
                    .then((_) => _loadClient()),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF150E3D), Color(0xFF0B0726)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 90, 20, 20),
                  child: Row(children: [
                    // Initials circle
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.5), width: 2),
                      ),
                      child: Center(
                        child: Text(_getInitials(_client!['name'] ?? ''),
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 22)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                        child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_client!['name'] ?? '',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800)),
                        if ((_client!['email'] ?? '').isNotEmpty)
                          Text(_client!['email'],
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 12)),
                        if ((_client!['phone'] ?? '').isNotEmpty)
                          Text(_client!['phone'],
                              style: const TextStyle(
                                  color: Color(0xFFFFD700), fontSize: 13)),
                      ],
                    )),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: isActive
                            ? Colors.white.withValues(alpha: 0.2)
                            : Colors.red.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: isActive
                                ? Colors.white.withValues(alpha: 0.5)
                                : Colors.red),
                      ),
                      child: Text(isActive ? 'Active' : 'Inactive',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),
              ),
            ),
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: const Color(0xFFFFD700),
              indicatorWeight: 2.5,
              labelColor: const Color(0xFFFFD700),
              unselectedLabelColor: Colors.white.withValues(alpha: 0.6),
              tabs: const [
                Tab(text: 'Details'),
                Tab(text: 'Bookings'),
                Tab(text: 'Cases'),
                Tab(text: 'Documents'),
              ],
            ),
          ),

          SliverFillRemaining(
            child: TabBarView(
              controller: _tabController,
              children: [
                _DetailsTab(client: _client!, hearings: _hearings),
                _BookingsTab(bookings: _bookings, onRefresh: _loadBookings),
                _CasesTab(
                    cases: _cases,
                    clientId: widget.clientId,
                    clientName: _client!['name'] ?? '',
                    onRefresh: _loadClient),
                _DocumentsTab(
                    documents: _documents,
                    clientId: widget.clientId,
                    clientName: _client!['name'] ?? '',
                    onRefresh: _loadClient),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Details Tab ────────────────────────────────────
class _DetailsTab extends StatelessWidget {
  final Map<String, dynamic> client;
  final List<dynamic> hearings;
  const _DetailsTab({required this.client, required this.hearings});

  Map<String, dynamic>? get _nextHearing {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final upcoming = hearings.where((h) {
      if (h['status'] != 'scheduled') return false;
      final d = DateTime.tryParse(h['hearing_date'] ?? '');
      return d != null && !d.isBefore(todayDate);
    }).toList()
      ..sort((a, b) => DateTime.parse(a['hearing_date'])
          .compareTo(DateTime.parse(b['hearing_date'])));
    return upcoming.isEmpty ? null : upcoming.first as Map<String, dynamic>;
  }

  @override
  Widget build(BuildContext context) {
    final next = _nextHearing;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _InfoCard(
            title: 'Contact Information',
            icon: Icons.contact_phone_outlined,
            items: [
              _InfoItem(
                  icon: Icons.email_outlined,
                  label: 'Email',
                  value: client['email'] ?? '-'),
              _InfoItem(
                  icon: Icons.phone_outlined,
                  label: 'Phone',
                  value: client['phone'] ?? '-'),
              _InfoItem(
                  icon: Icons.phone_outlined,
                  label: 'Alt Phone',
                  value: client['alternate_phone'] ?? '-'),
            ]),
        const SizedBox(height: 14),
        _InfoCard(title: 'Address', icon: Icons.location_on_outlined, items: [
          _InfoItem(
              icon: Icons.home_outlined,
              label: 'Address',
              value: client['address'] ?? '-'),
          _InfoItem(
              icon: Icons.location_city_outlined,
              label: 'City',
              value: client['city'] ?? '-'),
          _InfoItem(
              icon: Icons.map_outlined,
              label: 'State',
              value: client['state'] ?? '-'),
          _InfoItem(
              icon: Icons.pin_outlined,
              label: 'Pincode',
              value: client['pincode'] ?? '-'),
        ]),
        const SizedBox(height: 14),
        _HearingCard(nextHearing: next, hearings: hearings),
        if ((client['notes'] ?? '').isNotEmpty) ...[
          const SizedBox(height: 14),
          _NotesCard(notes: client['notes']),
        ],
        const SizedBox(height: 80),
      ],
    );
  }
}

// ── Next Hearing + Hearing History card ─────────────
class _HearingCard extends StatelessWidget {
  final Map<String, dynamic>? nextHearing;
  final List<dynamic> hearings;
  const _HearingCard({required this.nextHearing, required this.hearings});

  String _fmtDate(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    if (d == null) return '-';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'completed':
        return const Color(0xFF2E8B57);
      case 'cancelled':
        return const Color(0xFFD9534F);
      case 'adjourned':
        return const Color(0xFFB8860B);
      default:
        return const Color(0xFF4A90D9);
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border, width: 0.8),
          boxShadow: [
            BoxShadow(
                color: _brown.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                    color: _brown, borderRadius: BorderRadius.circular(7)),
                child: const Icon(Icons.event_rounded,
                    color: Colors.white, size: 13)),
            const SizedBox(width: 8),
            const Text('Hearing Schedule',
                style: TextStyle(
                    color: _brown, fontSize: 13, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 2),
          Divider(color: _border, height: 20, thickness: 0.6),
          if (nextHearing == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text('No upcoming hearing scheduled',
                  style: TextStyle(color: _textMuted, fontSize: 13)),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: const Color(0xFF4A90D9).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.calendar_today_rounded,
                          color: Color(0xFF4A90D9), size: 14),
                      const SizedBox(width: 6),
                      Flexible(
                          child: Text(
                              'Next Hearing: ${_fmtDate(nextHearing!['hearing_date'])}',
                              style: const TextStyle(
                                  color: _textPri,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700))),
                    ]),
                    if ((nextHearing!['court_name'] ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(nextHearing!['court_name'],
                          style:
                              const TextStyle(color: _textMuted, fontSize: 12)),
                    ],
                    if ((nextHearing!['purpose'] ?? '').isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(nextHearing!['purpose'],
                          style:
                              const TextStyle(color: _textMuted, fontSize: 12)),
                    ],
                  ]),
            ),
          if (hearings.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('History',
                style: TextStyle(
                    color: _textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            ...hearings.map((h) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                            width: 90,
                            child: Text(_fmtDate(h['hearing_date']),
                                style: const TextStyle(
                                    color: _textPri,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500))),
                        Expanded(
                            child: Text(
                                (h['purpose'] ?? '').isNotEmpty
                                    ? h['purpose']
                                    : (h['court_name'] ?? '-'),
                                style: const TextStyle(
                                    color: _textMuted, fontSize: 12))),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              color: _statusColor(h['status'] ?? '')
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8)),
                          child: Text(h['status'] ?? '-',
                              style: TextStyle(
                                  color: _statusColor(h['status'] ?? ''),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                )),
          ] else
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('No hearing history yet',
                  style: TextStyle(color: _textMuted, fontSize: 12)),
            ),
        ]),
      );
}

// ── Notes card ───────────────────────────────────────
// Notes are free-form paragraphs, not a short label/value pair — jamming them
// through the same fixed-80px-label _InfoItem row (built for short fields
// like Email/Phone) squeezed long notes into a narrow column and let
// unbroken text (URLs, long case references) spill past the card edge. A
// full-width block with explicit soft-wrapping fixes both.
class _NotesCard extends StatelessWidget {
  final String notes;
  const _NotesCard({required this.notes});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border, width: 0.8),
          boxShadow: [
            BoxShadow(
                color: _brown.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                    color: _brown, borderRadius: BorderRadius.circular(7)),
                child: const Icon(Icons.note_outlined,
                    color: Colors.white, size: 13)),
            const SizedBox(width: 8),
            const Text('Notes',
                style: TextStyle(
                    color: _brown, fontSize: 13, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 2),
          Divider(color: _border, height: 20, thickness: 0.6),
          Text(notes,
              softWrap: true,
              style: const TextStyle(
                  color: _textPri, fontSize: 13, height: 1.5)),
        ]),
      );
}

class _InfoCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<_InfoItem> items;
  const _InfoCard(
      {required this.title, required this.icon, required this.items});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border, width: 0.8),
          boxShadow: [
            BoxShadow(
                color: _brown.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                    color: _brown, borderRadius: BorderRadius.circular(7)),
                child: Icon(icon, color: Colors.white, size: 13)),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(
                    color: _brown, fontSize: 13, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 2),
          Divider(color: _border, height: 20, thickness: 0.6),
          ...items,
        ]),
      );
}

class _InfoItem extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _InfoItem(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Icon(icon, color: _brownLight, size: 15),
          const SizedBox(width: 10),
          SizedBox(
              width: 80,
              child: Text(label,
                  style: const TextStyle(color: _textMuted, fontSize: 12))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      color: _textPri,
                      fontSize: 13,
                      fontWeight: FontWeight.w500))),
        ]),
      );
}

// ── Bookings Tab ───────────────────────────────────
// Real consultation/booking data for this client — which service they
// booked (chat/audio/video/visit), when, for how long, and the current
// status — pulled from the existing consultations table via
// GET /clients/:id/bookings, not just their name.
class _BookingsTab extends StatelessWidget {
  final List<dynamic> bookings;
  final Future<void> Function() onRefresh;
  const _BookingsTab({required this.bookings, required this.onRefresh});

  String _serviceLabel(String type) {
    switch (type) {
      case 'chat':
        return 'Chat';
      case 'audio':
        return 'Audio Call';
      case 'video':
        return 'Video Call';
      case 'visit':
        return 'In-Person Visit';
      default:
        return type.isEmpty ? '-' : type;
    }
  }

  IconData _serviceIcon(String type) {
    switch (type) {
      case 'chat':
        return Icons.chat_bubble_outline_rounded;
      case 'audio':
        return Icons.call_rounded;
      case 'video':
        return Icons.videocam_rounded;
      case 'visit':
        return Icons.meeting_room_outlined;
      default:
        return Icons.event_note_rounded;
    }
  }

  String _fmtDate(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    if (d == null) return iso ?? '-';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  String _fmtDuration(int seconds) {
    if (seconds <= 0) return '-';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return s > 0 ? '$m min $s sec' : '$m minutes';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'confirmed':
        return const Color(0xFF4A90D9);
      case 'completed':
        return const Color(0xFF2E8B57);
      case 'rejected':
      case 'cancelled':
        return const Color(0xFFD9534F);
      case 'expired':
        return const Color(0xFF7B7594);
      default:
        return const Color(0xFFB8860B); // pending
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'confirmed':
        return 'Accepted';
      case 'rejected':
        return 'Rejected';
      case 'completed':
        return 'Completed';
      case 'expired':
        return 'Expired';
      case 'cancelled':
        return 'Cancelled';
      default:
        return 'Pending';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (bookings.isEmpty) {
      return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.event_busy_rounded,
            color: _brownLight.withValues(alpha: 0.4), size: 52),
        const SizedBox(height: 12),
        const Text('No bookings yet',
            style: TextStyle(color: _textMuted, fontSize: 15)),
      ]));
    }
    return RefreshIndicator(
      color: _brown,
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: bookings.length,
        itemBuilder: (_, i) {
          final b = bookings[i];
          final type = b['consultation_type'] ?? '';
          final status = b['status'] ?? 'pending';
          final duration = b['call_duration_seconds'] ?? 0;
          final amountPaise = b['amount_paise'] ?? 0;
          final paymentStatus = b['payment_status'] ?? '';
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _bgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _border, width: 0.8),
              boxShadow: [
                BoxShadow(
                    color: _brown.withValues(alpha: 0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 2))
              ],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                        color: _brown.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10)),
                    child: Icon(_serviceIcon(type), color: _brown, size: 18)),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(_serviceLabel(type),
                        style: const TextStyle(
                            color: _textPri,
                            fontWeight: FontWeight.w700,
                            fontSize: 14))),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: _statusColor(status).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(_statusLabel(status),
                      style: TextStyle(
                          color: _statusColor(status),
                          fontSize: 10,
                          fontWeight: FontWeight.w600)),
                ),
              ]),
              const SizedBox(height: 10),
              Wrap(spacing: 14, runSpacing: 6, children: [
                _bookingFact(Icons.calendar_today_rounded,
                    _fmtDate(b['consultation_date'])),
                _bookingFact(
                    Icons.access_time_rounded, b['consultation_time'] ?? '-'),
                if (duration > 0)
                  _bookingFact(
                      Icons.timer_outlined, _fmtDuration(duration)),
                if (amountPaise > 0)
                  _bookingFact(Icons.payments_outlined,
                      '₹${(amountPaise / 100).toStringAsFixed(0)} • ${paymentStatus.isEmpty ? '-' : paymentStatus}'),
              ]),
            ]),
          );
        },
      ),
    );
  }

  Widget _bookingFact(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _textMuted, size: 13),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(color: _textMuted, fontSize: 12)),
        ],
      );
}

// ── Cases Tab ──────────────────────────────────────
class _CasesTab extends StatelessWidget {
  final List<dynamic> cases;
  final String clientId;
  final String clientName;
  final VoidCallback onRefresh;
  const _CasesTab(
      {required this.cases,
      required this.clientId,
      required this.clientName,
      required this.onRefresh});

  void _addCase(BuildContext context) {
    context
        .push('/cases/add', extra: {'clientId': clientId, 'clientName': clientName})
        .then((_) => onRefresh());
  }

  @override
  Widget build(BuildContext context) {
    if (cases.isEmpty) {
      return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.gavel_rounded,
            color: _brownLight.withValues(alpha: 0.4), size: 52),
        const SizedBox(height: 12),
        const Text('No cases yet',
            style: TextStyle(color: _textMuted, fontSize: 15)),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () => _addCase(context),
          icon: const Icon(Icons.add_rounded, color: Colors.white),
          label: const Text('Add Case', style: TextStyle(color: Colors.white)),
          style: ElevatedButton.styleFrom(
              backgroundColor: _brown,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
        ),
      ]));
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _addCase(context),
            icon: const Icon(Icons.add_rounded, color: Colors.white),
            label: const Text('Add Case',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
                backgroundColor: _brown,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
          ),
        ),
      ),
      Expanded(
        child: ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: cases.length,
      itemBuilder: (_, i) {
        final c = cases[i];
        return GestureDetector(
          onTap: () => context.push('/cases/${c['id']}'),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _bgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _border, width: 0.8),
              boxShadow: [
                BoxShadow(
                    color: _brown.withValues(alpha: 0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 2))
              ],
            ),
            child: Row(children: [
              Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: _brown.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child:
                      const Icon(Icons.gavel_rounded, color: _brown, size: 20)),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(c['case_title'] ?? '',
                        style: const TextStyle(
                            color: _textPri,
                            fontWeight: FontWeight.w600,
                            fontSize: 14)),
                    Text(c['court_name'] ?? '',
                        style:
                            const TextStyle(color: _textMuted, fontSize: 12)),
                  ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: const Color(0xFF2E8B57).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(c['status'] ?? 'active',
                    style: const TextStyle(
                        color: Color(0xFF2E8B57),
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        );
      },
        ),
      ),
    ]);
  }
}

// ── Documents Tab ──────────────────────────────────
class _DocumentsTab extends StatelessWidget {
  final List<dynamic> documents;
  final String clientId;
  final String clientName;
  final VoidCallback onRefresh;
  const _DocumentsTab(
      {required this.documents,
      required this.clientId,
      required this.clientName,
      required this.onRefresh});

  void _addDocument(BuildContext context) {
    showDocumentUploadSheet(
      context,
      clientId: clientId,
      description: 'Document for client: $clientName',
      onUploaded: onRefresh,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (documents.isEmpty) {
      return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.folder_open_rounded,
            color: _brownLight.withValues(alpha: 0.4), size: 52),
        const SizedBox(height: 12),
        const Text('No documents yet',
            style: TextStyle(color: _textMuted, fontSize: 15)),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () => _addDocument(context),
          icon: const Icon(Icons.upload_rounded, color: Colors.white),
          label: const Text('Add Document',
              style: TextStyle(color: Colors.white)),
          style: ElevatedButton.styleFrom(
              backgroundColor: _brown,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
        ),
      ]));
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _addDocument(context),
            icon: const Icon(Icons.add_rounded, color: Colors.white),
            label: const Text('Add Document',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
                backgroundColor: _brown,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
          ),
        ),
      ),
      Expanded(
        child: ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: documents.length,
      itemBuilder: (_, i) {
        final d = documents[i];
        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            HapticFeedback.lightImpact();
            context.push('/documents/${d['id']}');
          },
          child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border, width: 0.8),
            boxShadow: [
              BoxShadow(
                  color: _brown.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
            ],
          ),
          child: Row(children: [
            Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: const Color(0xFF4A90D9).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.description_rounded,
                    color: Color(0xFF4A90D9), size: 20)),
            const SizedBox(width: 12),
            Expanded(
                child: Text(d['file_name'] ?? '',
                    style: const TextStyle(
                        color: _textPri,
                        fontWeight: FontWeight.w600,
                        fontSize: 14))),
            const Icon(Icons.chevron_right_rounded, color: _textMuted, size: 20),
          ]),
          ),
        );
      },
        ),
      ),
    ]);
  }
}
