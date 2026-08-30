import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/services/dio_client.dart';
import '../../../core/services/fcm_service.dart';

// Same case-insensitive mapping used on the client portal and lawyer
// dashboard sides, so "Audio Call"/"audio_call"/"audio" all resolve the same
// way without needing the API to change.
String _consultTypeAction(String rawType) {
  final t = rawType.toLowerCase();
  if (t.contains('audio')) return 'audio';
  if (t.contains('video')) return 'video';
  return 'chat';
}

/// "2026-08-30" -> "30 Aug 2026". Falls back to the raw string for anything
/// that doesn't parse (never crashes the card over a formatting edge case).
String _formatConsultDate(String isoDate) {
  try {
    return DateFormat('d MMM yyyy').format(DateTime.parse(isoDate));
  } catch (_) {
    return isoDate;
  }
}

/// True once the appointment is within 30 minutes (and not already past by
/// more than a few minutes) — used to surface a "Starting soon" highlight
/// instead of a background-scheduled OS notification, since the latter needs
/// the device's real IANA timezone wired up to fire at the correct wall-clock
/// time and this project doesn't have that plumbing.
bool _isStartingSoon(String isoDate, String timeLabel) {
  try {
    final date = DateTime.parse(isoDate);
    final time = DateFormat('h:mm a').parse(timeLabel);
    final when = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    final diff = when.difference(DateTime.now());
    return diff.inMinutes <= 30 && diff.inMinutes >= -15;
  } catch (_) {
    return false;
  }
}

const _bg = Color(0xFFF6F5FB);
const _bgCard = Color(0xFFFFFFFF);
const _brown = Color(0xFF150E3D);
const _brownDark = Color(0xFF0B0726);
const _gold = Color(0xFFD4AF37);
const _border = Color(0xFFE6E3F4);
const _textPri = Color(0xFF1B1533);
const _textMuted = Color(0xFF7B7594);
const _green = Color(0xFF2E8B57);
const _red = Color(0xFFD9534F);
const _blue = Color(0xFF4A90D9);

class ConsultationManagementScreen extends StatefulWidget {
  const ConsultationManagementScreen({super.key});
  @override
  State<ConsultationManagementScreen> createState() =>
      _ConsultationManagementScreenState();
}

class _ConsultationManagementScreenState
    extends State<ConsultationManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<dynamic> _consultations = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
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
      final res = await DioClient.instance.get('/consultations');
      setState(() {
        _consultations = res.data['data'] ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  List<dynamic> get _pending =>
      _consultations.where((c) => c['status'] == 'pending').toList();
  List<dynamic> get _confirmed =>
      _consultations.where((c) => c['status'] == 'confirmed').toList();
  List<dynamic> get _completed => _consultations
      .where((c) => c['status'] == 'completed' || c['status'] == 'cancelled')
      .toList();

  Future<void> _updateConsultation(dynamic c, String status,
      {String? notes, String? link}) async {
    try {
      await DioClient.instance.put('/consultations/${c['id']}', data: {
        'status': status,
        'lawyer_notes': notes ?? '',
        'meeting_link': link ?? '',
      });
      HapticFeedback.heavyImpact();
      _load();
      if (status == 'confirmed') {
        // Real booking data only — client, type, date and time as already
        // returned by GetLawyerConsultations, nothing invented.
        FcmService.instance.showLocalNotification(
          '🔔 Consultation Confirmed',
          'Client: ${c['client_name'] ?? 'Client'}\n'
              'Type: ${c['consultation_type'] ?? ''}\n'
              'Date: ${_formatConsultDate(c['consultation_date'] ?? '')}\n'
              'Time: ${c['consultation_time'] ?? ''}',
        );
      }
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Consultation $status successfully!'),
            backgroundColor: status == 'confirmed' ? _green : _red,
            behavior: SnackBarBehavior.floating));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Something went wrong. Please try again.'),
            backgroundColor: _red));
    }
  }

  /// Rings the client through the existing push-notification pipeline, then
  /// joins the real in-app WebRTC call session as the caller.
  Future<void> _ringClient(dynamic c) async {
    final id = c['id'];
    if (id == null) return;
    try {
      await DioClient.instance.post('/consultations/$id/call');
    } catch (_) {}
  }

  Future<void> _joinCall(dynamic c, {required bool video}) async {
    final id = c['id'];
    if (id == null) {
      _showSnack('This booking is missing its consultation id.');
      return;
    }
    unawaited(_ringClient(c));
    context.push('/call', extra: {
      'consultationId': id.toString(),
      'peerName': (c['client_name'] ?? 'Client').toString(),
      'video': video,
      'isCaller': true,
    });
  }

  Future<void> _callClient(dynamic c) => _joinCall(c, video: false);

  Future<void> _startVideoCall(dynamic c) => _joinCall(c, video: true);

  void _openChat() => context.push('/chat');

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: _red));
  }

  void _showActionSheet(dynamic c) {
    final notesCtrl = TextEditingController(text: c['lawyer_notes'] ?? '');
    final linkCtrl = TextEditingController(text: c['meeting_link'] ?? '');
    final status = c['status'] ?? 'pending';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                  child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: _border,
                          borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Text(
                  '${c['client_name'] ?? 'Client'} - ${c['consultation_type'] ?? ''}',
                  style: const TextStyle(
                      color: _textPri,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
              Text(
                  'Booked for ${_formatConsultDate(c['consultation_date'] ?? '')} • ${c['consultation_time'] ?? ''}',
                  style: const TextStyle(color: _textMuted, fontSize: 12)),
              if ((c['notes'] ?? '').isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: _blue.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _blue.withValues(alpha: 0.2))),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.notes_rounded,
                              color: _blue, size: 14),
                          const SizedBox(width: 6),
                          Expanded(
                              child: Text('Client Note: ${c['notes']}',
                                  style: const TextStyle(
                                      color: _textPri, fontSize: 12))),
                        ])),
              ],
              const SizedBox(height: 16),
              TextField(
                  controller: notesCtrl,
                  maxLines: 2,
                  style: const TextStyle(color: _textPri, fontSize: 13),
                  decoration: InputDecoration(
                      labelText: 'Your Notes/Response',
                      labelStyle:
                          const TextStyle(color: _textMuted, fontSize: 12),
                      filled: true,
                      fillColor: _bg,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _border)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: _border, width: 0.8)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: _brown, width: 1.5)))),
              if ((c['consultation_type'] ?? '').contains('Video') ||
                  (c['consultation_type'] ?? '').contains('Audio')) ...[
                const SizedBox(height: 10),
                TextField(
                    controller: linkCtrl,
                    style: const TextStyle(color: _textPri, fontSize: 13),
                    decoration: InputDecoration(
                        labelText: 'Meeting Link (Zoom/Meet)',
                        labelStyle:
                            const TextStyle(color: _textMuted, fontSize: 12),
                        prefixIcon: const Icon(Icons.link_rounded,
                            color: _brown, size: 16),
                        filled: true,
                        fillColor: _bg,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: _border)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: _border, width: 0.8)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: _brown, width: 1.5)))),
              ],
              const SizedBox(height: 16),
              if (status == 'pending')
                Row(children: [
                  Expanded(
                      child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _updateConsultation(c, 'confirmed',
                          notes: notesCtrl.text, link: linkCtrl.text);
                    },
                    icon: const Icon(Icons.check_rounded,
                        color: Colors.white, size: 16),
                    label: const Text('Confirm',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: _green,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12)),
                  )),
                  const SizedBox(width: 10),
                  Expanded(
                      child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _updateConsultation(c, 'cancelled',
                          notes: notesCtrl.text);
                    },
                    icon:
                        const Icon(Icons.close_rounded, color: _red, size: 16),
                    label: const Text('Decline',
                        style: TextStyle(
                            color: _red, fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: _red),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12)),
                  )),
                ])
              else if (status == 'confirmed')
                SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _updateConsultation(c, 'completed',
                            notes: notesCtrl.text);
                      },
                      icon: const Icon(Icons.done_all_rounded,
                          color: Colors.white, size: 16),
                      label: const Text('Mark Completed',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _brown,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12)),
                    )),
            ]),
      ),
    );
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
                end: Alignment.bottomRight),
          ),
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
                        child: Text('Consultations',
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
                ),
                TabBar(
                  controller: _tabCtrl,
                  indicatorColor: const Color(0xFFFFD700),
                  indicatorWeight: 3,
                  labelColor: const Color(0xFFFFD700),
                  unselectedLabelColor: Colors.white60,
                  tabs: [
                    Tab(text: 'Pending (${_pending.length})'),
                    Tab(text: 'Confirmed (${_confirmed.length})'),
                    Tab(text: 'History'),
                  ],
                ),
              ])),
        ),
        Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _brown))
                : TabBarView(controller: _tabCtrl, children: [
                    _buildList(_pending, 'No pending consultations',
                        Icons.hourglass_empty_rounded),
                    _buildList(_confirmed, 'No confirmed consultations',
                        Icons.event_available_rounded),
                    _buildList(
                        _completed, 'No history yet', Icons.history_rounded),
                  ])),
      ]),
    );
  }

  Widget _buildList(List<dynamic> list, String emptyMsg, IconData emptyIcon) {
    if (list.isEmpty)
      return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(emptyIcon, color: _brown.withValues(alpha: 0.3), size: 56),
        const SizedBox(height: 12),
        Text(emptyMsg, style: const TextStyle(color: _textMuted, fontSize: 15)),
      ]));

    return RefreshIndicator(
      color: _brown,
      backgroundColor: _bgCard,
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: list.length,
        itemBuilder: (_, i) {
          final c = list[i];
          final status = c['status'] ?? 'pending';
          final color = status == 'confirmed'
              ? _green
              : status == 'cancelled'
                  ? _red
                  : status == 'completed'
                      ? _blue
                      : _gold;
          final rawType = (c['consultation_type'] ?? '').toString();
          final isOfficeVisit = rawType.toLowerCase().contains('office');
          final action = _consultTypeAction(rawType);
          final typeIcon = isOfficeVisit
              ? Icons.business_center_rounded
              : action == 'video'
                  ? Icons.videocam_rounded
                  : action == 'audio'
                      ? Icons.phone_rounded
                      : Icons.chat_rounded;
          final typeEmoji = isOfficeVisit
              ? '🏢'
              : action == 'video'
                  ? '🎥'
                  : action == 'audio'
                      ? '📞'
                      : '💬';
          final consultDate = (c['consultation_date'] ?? '').toString();
          final consultTime = (c['consultation_time'] ?? '').toString();
          final startingSoon =
              status == 'confirmed' && _isStartingSoon(consultDate, consultTime);

          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              _showActionSheet(c);
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                  color: _bgCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: startingSoon
                          ? _gold
                          : color.withValues(alpha: 0.25),
                      width: startingSoon ? 1.6 : 1),
                  boxShadow: [
                    BoxShadow(
                        color: _brown.withValues(alpha: 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2))
                  ]),
              child: Column(children: [
                Container(
                    height: 4,
                    decoration: BoxDecoration(
                        color: color,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(16)))),
                Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12)),
                                child: Icon(typeIcon, color: color, size: 22)),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text(c['client_name'] ?? 'Client',
                                      style: const TextStyle(
                                          color: _textPri,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  Text('$typeEmoji ${rawType.isNotEmpty ? rawType : 'Consultation'}',
                                      style: TextStyle(
                                          color: color,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600)),
                                ])),
                            Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8)),
                                    child: Text(status.toUpperCase(),
                                        style: TextStyle(
                                            color: color,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w800)),
                                  ),
                                  const SizedBox(height: 4),
                                  const Icon(Icons.arrow_forward_ios_rounded,
                                      color: _textMuted, size: 12),
                                ]),
                          ]),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                                color: _bg,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: _border, width: 0.6)),
                            child: Wrap(
                              spacing: 14,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Row(mainAxisSize: MainAxisSize.min, children: [
                                  const Icon(Icons.calendar_today_rounded,
                                      color: _brown, size: 13),
                                  const SizedBox(width: 5),
                                  Text(
                                      consultDate.isNotEmpty
                                          ? _formatConsultDate(consultDate)
                                          : '—',
                                      style: const TextStyle(
                                          color: _textPri,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700)),
                                ]),
                                Row(mainAxisSize: MainAxisSize.min, children: [
                                  const Icon(Icons.access_time_rounded,
                                      color: _brown, size: 13),
                                  const SizedBox(width: 5),
                                  Text(consultTime.isNotEmpty ? consultTime : '—',
                                      style: const TextStyle(
                                          color: _textPri,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700)),
                                ]),
                                if (c['payment_status'] == 'paid')
                                  Row(mainAxisSize: MainAxisSize.min, children: [
                                    const Icon(Icons.check_circle_rounded,
                                        color: _green, size: 13),
                                    const SizedBox(width: 4),
                                    const Text('₹5 Paid',
                                        style: TextStyle(
                                            color: _green,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700)),
                                  ]),
                                if (startingSoon)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                        color: _gold.withValues(alpha: 0.15),
                                        borderRadius:
                                            BorderRadius.circular(6)),
                                    child: const Text('STARTING SOON',
                                        style: TextStyle(
                                            color: _gold,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w800)),
                                  ),
                              ],
                            ),
                          ),
                          if ((c['notes'] ?? '').isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                  color: _blue.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: _blue.withValues(alpha: 0.15))),
                              child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.notes_rounded,
                                        color: _blue, size: 12),
                                    const SizedBox(width: 4),
                                    Expanded(
                                        child: Text(c['notes'],
                                            style: const TextStyle(
                                                color: _textPri, fontSize: 11),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis)),
                                  ]),
                            ),
                          ],
                          if ((c['meeting_link'] ?? '').isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Row(children: [
                              const Icon(Icons.link_rounded,
                                  color: _green, size: 14),
                              const SizedBox(width: 4),
                              Expanded(
                                  child: Text(c['meeting_link'],
                                      style: const TextStyle(
                                          color: _green, fontSize: 11),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis)),
                            ]),
                          ],
                          if (status == 'pending') ...[
                            const SizedBox(height: 10),
                            Row(children: [
                              Expanded(
                                  child: GestureDetector(
                                onTap: () =>
                                    _updateConsultation(c, 'confirmed'),
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                      color: _green,
                                      borderRadius: BorderRadius.circular(8)),
                                  child: const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.check_rounded,
                                            color: Colors.white, size: 14),
                                        SizedBox(width: 4),
                                        Text('Confirm',
                                            style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 12)),
                                      ]),
                                ),
                              )),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: GestureDetector(
                                onTap: () => _showActionSheet(c),
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                      color: _bgCard,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: _border)),
                                  child: const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.reply_rounded,
                                            color: _brown, size: 14),
                                        SizedBox(width: 4),
                                        Text('Respond',
                                            style: TextStyle(
                                                color: _brown,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 12)),
                                      ]),
                                ),
                              )),
                            ]),
                          ],
                          if (status == 'confirmed' && !isOfficeVisit) ...[
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: Material(
                                color: color,
                                borderRadius: BorderRadius.circular(10),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () {
                                    HapticFeedback.heavyImpact();
                                    if (action == 'audio') {
                                      _callClient(c);
                                    } else if (action == 'video') {
                                      _startVideoCall(c);
                                    } else {
                                      _openChat();
                                    }
                                  },
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 10),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(typeIcon,
                                            color: Colors.white, size: 16),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                              action == 'audio'
                                                  ? 'Call Client'
                                                  : action == 'video'
                                                      ? 'Video Call'
                                                      : 'Chat with Client',
                                              textAlign: TextAlign.center,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 13)),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ])),
              ]),
            ),
          );
        },
      ),
    );
  }
}
