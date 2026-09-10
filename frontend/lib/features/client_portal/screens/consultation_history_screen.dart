import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/services/dio_client.dart';

const _bg = Color(0xFFF0FAF6);
const _bgCard = Color(0xFFFFFFFF);
const _green = Color(0xFF0D6E4F);
const _border = Color(0xFFB2DFD0);
const _textPri = Color(0xFF0A2E1F);
const _textMuted = Color(0xFF4A7A63);
const _gold = Color(0xFFD4A017);
const _red = Color(0xFFD9534F);
const _blue = Color(0xFF4A90D9);

/// Same case-insensitive mapping used everywhere else this needs deciding
/// (lawyer dashboard, lawyer consultations screen, client portal dashboard) —
/// kept identical here rather than shared, matching how those already
/// duplicate it independently.
String _historyAction(String rawType) {
  final t = rawType.toLowerCase();
  if (t.contains('audio')) return 'audio';
  if (t.contains('video')) return 'video';
  return 'chat';
}

String _formatDate(String isoDate) {
  try {
    return DateFormat('d MMM yyyy').format(DateTime.parse(isoDate));
  } catch (_) {
    return isoDate;
  }
}

/// 125 -> "02 min 05 sec" — same field and format the lawyer's consultations
/// screen shows, computed from the actual accumulated call_duration_seconds.
String _formatDuration(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '${m.toString().padLeft(2, '0')} min ${s.toString().padLeft(2, '0')} sec';
}

/// The real session start/end time (session_started_at / session_ended_at),
/// distinct from the booked appointment date/time.
String _formatSessionTime(String? isoTimestamp) {
  if (isoTimestamp == null || isoTimestamp.isEmpty) return '—';
  try {
    return DateFormat('d MMM, h:mm a').format(DateTime.parse(isoTimestamp).toLocal());
  } catch (_) {
    return '—';
  }
}

/// The client's Call/Communication History — every past and current chat,
/// audio and video consultation with any lawyer, newest first. There was no
/// client-facing view of this at all before; the lawyer side already has an
/// equivalent History tab in ConsultationManagementScreen. Reuses the
/// existing GetMyConsultations endpoint — no new backend route.
class ConsultationHistoryScreen extends StatefulWidget {
  const ConsultationHistoryScreen({super.key});
  @override
  State<ConsultationHistoryScreen> createState() =>
      _ConsultationHistoryScreenState();
}

class _ConsultationHistoryScreenState
    extends State<ConsultationHistoryScreen> {
  List<dynamic> _consultations = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await DioClient.instance.get('/portal/my-consultations');
      setState(() {
        _consultations = res.data['data'] ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = DioClient.describeError(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _green,
        foregroundColor: Colors.white,
        title: const Text('Call History',
            style: TextStyle(fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _green))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: _textMuted)),
                      const SizedBox(height: 12),
                      OutlinedButton(onPressed: _load, child: const Text('Retry')),
                    ]),
                  ),
                )
              : _consultations.isEmpty
                  ? Center(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                        Icon(Icons.history_rounded,
                            color: _green.withValues(alpha: 0.3), size: 56),
                        const SizedBox(height: 12),
                        const Text('No chat, audio or video history yet',
                            style: TextStyle(color: _textMuted, fontSize: 14)),
                      ]))
                  : RefreshIndicator(
                      color: _green,
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _consultations.length,
                        itemBuilder: (_, i) =>
                            _HistoryCard(consultation: _consultations[i]),
                      ),
                    ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final dynamic consultation;
  const _HistoryCard({required this.consultation});

  @override
  Widget build(BuildContext context) {
    final rawType = (consultation['consultation_type'] ?? '').toString();
    final action = _historyAction(rawType);
    final status = (consultation['status'] ?? 'pending').toString();
    final lawyerName = (consultation['lawyer_name'] ?? 'Lawyer').toString();
    final date = (consultation['consultation_date'] ?? '').toString();
    final time = (consultation['consultation_time'] ?? '').toString();
    final durationSeconds =
        ((consultation['call_duration_seconds'] ?? 0) as num).toInt();
    final startedAt = consultation['session_started_at']?.toString();
    final endedAt = consultation['session_ended_at']?.toString();

    final color = switch (status) {
      'confirmed' => _green,
      'completed' => _blue,
      'rejected' || 'cancelled' || 'expired' => _red,
      _ => _gold,
    };

    final icon = switch (action) {
      'video' => Icons.videocam_rounded,
      'audio' => Icons.phone_rounded,
      _ => Icons.chat_rounded,
    };
    final emoji = switch (action) { 'video' => '🎥', 'audio' => '📞', _ => '💬' };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border, width: 0.8),
        boxShadow: [
          BoxShadow(
              color: _green.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(lawyerName,
                  style: const TextStyle(
                      color: _textPri, fontWeight: FontWeight.w700, fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              Text('$emoji ${rawType.isNotEmpty ? rawType : 'Consultation'}',
                  style: TextStyle(
                      color: color, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Wrap(spacing: 10, runSpacing: 2, children: [
                if (date.isNotEmpty)
                  Text('${_formatDate(date)}${time.isNotEmpty ? " • $time" : ""}',
                      style: const TextStyle(color: _textMuted, fontSize: 11.5)),
                if (durationSeconds > 0)
                  Text('⏱ ${_formatDuration(durationSeconds)}',
                      style: const TextStyle(
                          color: _blue,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600)),
                if (startedAt != null)
                  Text('Started ${_formatSessionTime(startedAt)}',
                      style: const TextStyle(color: _textMuted, fontSize: 11)),
                if (endedAt != null)
                  Text('Ended ${_formatSessionTime(endedAt)}',
                      style: const TextStyle(color: _textMuted, fontSize: 11)),
              ]),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8)),
          child: Text(status.toUpperCase(),
              style: TextStyle(
                  color: color, fontSize: 9, fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }
}
