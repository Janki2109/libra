import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/dio_client.dart';
import '../utils/hearing_status.dart';

const _bg = Color(0xFFF6F5FB);
const _bgCard = Color(0xFFFFFFFF);
const _brown = Color(0xFF150E3D);
const _brownDark = Color(0xFF0B0726);
const _gold = Color(0xFFB8860B);
const _border = Color(0xFFE6E3F4);
const _textPri = Color(0xFF2C1A0E);
const _textMuted = Color(0xFF3D2C8D);

class HearingDetailsScreen extends StatefulWidget {
  final String hearingId;
  const HearingDetailsScreen({super.key, required this.hearingId});
  @override
  State<HearingDetailsScreen> createState() => _HearingDetailsScreenState();
}

class _HearingDetailsScreenState extends State<HearingDetailsScreen> {
  Map<String, dynamic>? _hearing;
  bool _loading = true;
  String? _error;
  List<dynamic> _caseHearings = [];
  List<dynamic> _caseDocuments = [];

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
      final res = await DioClient.instance.get('/hearings/${widget.hearingId}');
      final hearing = res.data['data'] as Map<String, dynamic>;
      setState(() {
        _hearing = hearing;
        _loading = false;
      });
      final caseId = (hearing['case_id'] ?? '').toString();
      if (caseId.isNotEmpty) {
        _loadCaseContext(caseId);
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = DioClient.describeError(e);
      });
    }
  }

  // Previous/next hearing timeline and relevant documents both live under
  // the case, not the hearing itself — loaded separately (and best-effort:
  // a failure here shouldn't block the hearing's own details from showing).
  Future<void> _loadCaseContext(String caseId) async {
    try {
      final res = await DioClient.instance.get('/cases/$caseId/hearings');
      if (mounted) setState(() => _caseHearings = res.data['data'] ?? []);
    } catch (_) {}
    try {
      final res =
          await DioClient.instance.get('/documents', queryParameters: {
        'case_id': caseId,
      });
      if (mounted) setState(() => _caseDocuments = res.data['data'] ?? []);
    } catch (_) {}
  }

  /// The case hearing immediately before this one by date — "what happened
  /// last time" context a lawyer would otherwise have to hunt for across the
  /// whole case's hearing list.
  Map? get _previousHearing {
    if (_hearing == null) return null;
    final thisDate = (_hearing!['hearing_date'] ?? '').toString();
    final earlier = _caseHearings
        .where((h) =>
            h['id'] != _hearing!['id'] &&
            (h['hearing_date'] ?? '').toString().compareTo(thisDate) < 0)
        .toList()
      ..sort((a, b) =>
          (b['hearing_date'] ?? '').toString().compareTo((a['hearing_date'] ?? '').toString()));
    return earlier.isNotEmpty ? earlier.first as Map : null;
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'completed':
        return const Color(0xFF2E8B57);
      case 'cancelled':
        return const Color(0xFFD9534F);
      case 'adjourned':
        return const Color(0xFFD4A017);
      default:
        return const Color(0xFF4A90D9);
    }
  }

  IconData _statusIcon(String s) {
    switch (s) {
      case 'completed':
        return Icons.check_circle_rounded;
      case 'cancelled':
        return Icons.cancel_rounded;
      case 'adjourned':
        return Icons.pending_rounded;
      default:
        return Icons.event_rounded;
    }
  }

  void _showUpdateSheet() {
    final orderSummaryCtrl =
        TextEditingController(text: _hearing?['order_summary'] ?? '');
    final remarksCtrl = TextEditingController(text: _hearing?['remarks'] ?? '');
    DateTime? nextDate;
    String selectedStatus = _hearing?['status'] ?? 'scheduled';
    bool loading = false;

    // Parse existing next_date
    final existingNext = _hearing?['next_date']?.toString() ?? '';
    if (existingNext.length >= 10) {
      try {
        nextDate = DateTime.parse(existingNext.substring(0, 10));
      } catch (_) {}
    }

    final statuses = ['scheduled', 'completed', 'adjourned', 'cancelled'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
          builder: (ctx, setS) => Padding(
                padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: 20,
                    bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Handle
                      Center(
                          child: Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                  color: _border,
                                  borderRadius: BorderRadius.circular(2)))),
                      const SizedBox(height: 16),

                      // Title
                      Row(children: [
                        Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                                color: _brown,
                                borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.update_rounded,
                                color: Colors.white, size: 20)),
                        const SizedBox(width: 12),
                        const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Update After Hearing',
                                  style: TextStyle(
                                      color: _textPri,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800)),
                              Text('Add order summary, next date & remarks',
                                  style: TextStyle(
                                      color: _textMuted, fontSize: 11)),
                            ]),
                      ]),
                      const SizedBox(height: 20),

                      // Status
                      const Text('Hearing Status',
                          style: TextStyle(
                              color: _textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      SizedBox(
                          height: 44,
                          child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: statuses.map((s) {
                                final sel = selectedStatus == s;
                                final color = _statusColor(s);
                                return GestureDetector(
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    setS(() => selectedStatus = s);
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    margin: const EdgeInsets.only(right: 8),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 8),
                                    decoration: BoxDecoration(
                                      color:
                                          sel ? color.withValues(alpha: 0.12) : _bg,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                          color: sel ? color : _border,
                                          width: sel ? 2 : 0.8),
                                    ),
                                    child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(_statusIcon(s),
                                              color: sel ? color : _textMuted,
                                              size: 14),
                                          const SizedBox(width: 5),
                                          Text(
                                              s[0].toUpperCase() +
                                                  s.substring(1),
                                              style: TextStyle(
                                                  color:
                                                      sel ? color : _textMuted,
                                                  fontSize: 12,
                                                  fontWeight: sel
                                                      ? FontWeight.w700
                                                      : FontWeight.w400)),
                                        ]),
                                  ),
                                );
                              }).toList())),
                      const SizedBox(height: 16),

                      // Order Summary
                      const Text('Order Summary',
                          style: TextStyle(
                              color: _textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: orderSummaryCtrl,
                        maxLines: 3,
                        style: const TextStyle(color: _textPri, fontSize: 14),
                        decoration: _inputDeco(
                            'What happened in this hearing...',
                            Icons.description_rounded),
                      ),
                      const SizedBox(height: 14),

                      // Next Date
                      const Text('Next Hearing Date',
                          style: TextStyle(
                              color: _textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: nextDate ??
                                DateTime.now().add(const Duration(days: 7)),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now()
                                .add(const Duration(days: 365 * 2)),
                            builder: (c, child) => Theme(
                              data: ThemeData.light().copyWith(
                                  colorScheme: const ColorScheme.light(
                                      primary: _brown, surface: _bg)),
                              child: child!,
                            ),
                          );
                          if (picked != null) setS(() => nextDate = picked);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: nextDate != null
                                ? _brown.withValues(alpha: 0.06)
                                : _bg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: nextDate != null ? _brown : _border,
                                width: nextDate != null ? 1.5 : 0.8),
                          ),
                          child: Row(children: [
                            Icon(Icons.event_repeat_rounded,
                                color: nextDate != null ? _brown : _textMuted,
                                size: 20),
                            const SizedBox(width: 12),
                            Text(
                              nextDate != null
                                  ? '${nextDate!.day}/${nextDate!.month}/${nextDate!.year}'
                                  : 'Select next hearing date',
                              style: TextStyle(
                                  color:
                                      nextDate != null ? _textPri : _textMuted,
                                  fontWeight: nextDate != null
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  fontSize: 14),
                            ),
                            const Spacer(),
                            if (nextDate != null)
                              GestureDetector(
                                onTap: () => setS(() => nextDate = null),
                                child: const Icon(Icons.clear_rounded,
                                    color: _textMuted, size: 16),
                              )
                            else
                              const Icon(Icons.edit_rounded,
                                  color: _textMuted, size: 16),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Remarks
                      const Text('Remarks',
                          style: TextStyle(
                              color: _textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: remarksCtrl,
                        maxLines: 2,
                        style: const TextStyle(color: _textPri, fontSize: 14),
                        decoration: _inputDeco(
                            'Any additional remarks...', Icons.notes_rounded),
                      ),
                      const SizedBox(height: 20),

                      // Save button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: loading
                              ? null
                              : () async {
                                  setS(() => loading = true);
                                  try {
                                    await DioClient.instance.put(
                                        '/hearings/${widget.hearingId}',
                                        data: {
                                          'status': selectedStatus,
                                          'order_summary':
                                              orderSummaryCtrl.text.trim(),
                                          'next_date': nextDate != null
                                              ? '${nextDate!.year}-${nextDate!.month.toString().padLeft(2, '0')}-${nextDate!.day.toString().padLeft(2, '0')}'
                                              : '',
                                          'remarks': remarksCtrl.text.trim(),
                                        });
                                    if (ctx.mounted) {
                                      Navigator.pop(ctx);
                                      HapticFeedback.heavyImpact();
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                        content: const Text(
                                            'Hearing updated successfully!'),
                                        backgroundColor:
                                            const Color(0xFF2E8B57),
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12)),
                                      ));
                                      _load(); // Refresh
                                    }
                                  } catch (e) {
                                    setS(() => loading = false);
                                    if (ctx.mounted)
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                        content: Text('Update failed: $e'),
                                        backgroundColor:
                                            const Color(0xFFD9534F),
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12)),
                                      ));
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                              backgroundColor: _brown,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14))),
                          child: loading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : const Text('Save Update',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15)),
                        ),
                      ),
                    ]),
              )),
    );
  }

  InputDecoration _inputDeco(String hint, IconData icon) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _textMuted, fontSize: 13),
        prefixIcon: Icon(icon, color: _brown, size: 18),
        filled: true,
        fillColor: _bg,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _border, width: 0.8)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _brown, width: 1.5)),
      );

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light),
      child: Scaffold(
        backgroundColor: _bg,
        body: Container(
          color: _bg,
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
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(children: [
                      IconButton(
                          icon: const Icon(Icons.arrow_back_rounded,
                              color: Colors.white),
                          onPressed: () => context.pop()),
                      const Expanded(
                          child: Text('Hearing Details',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700))),
                      if (!_loading && _hearing != null)
                        TextButton(
                          onPressed: _showUpdateSheet,
                          child: const Text('Update',
                              style: TextStyle(
                                  color: Color(0xFFFFD700),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14)),
                        )
                      else
                        const SizedBox(width: 70),
                    ]),
                  )),
            ),

            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: _brown))
                  : _hearing == null
                      ? Center(
                          child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                    _error != null
                                        ? Icons.wifi_off_rounded
                                        : Icons.event_busy_rounded,
                                    color: _textMuted.withValues(alpha: 0.5),
                                    size: 40),
                                const SizedBox(height: 12),
                                Text(
                                    _error != null
                                        ? 'Could not load this hearing'
                                        : 'Hearing not found',
                                    style: const TextStyle(
                                        color: _textPri,
                                        fontWeight: FontWeight.w600)),
                                if (_error != null) ...[
                                  const SizedBox(height: 6),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 32),
                                    child: Text(_error!,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                            color: _textMuted, fontSize: 12)),
                                  ),
                                  const SizedBox(height: 16),
                                  OutlinedButton.icon(
                                    onPressed: _load,
                                    icon: const Icon(Icons.refresh_rounded,
                                        size: 16),
                                    label: const Text('Retry'),
                                  ),
                                ],
                              ]))
                      : RefreshIndicator(
                          color: _brown,
                          backgroundColor: _bgCard,
                          onRefresh: _load,
                          child: ListView(
                              padding: const EdgeInsets.all(16),
                              children: [
                                // Status banner
                                Builder(builder: (context) {
                                  final info = hearingStatusInfo(_hearing!);
                                  return Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: info.color.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                          color:
                                              info.color.withValues(alpha: 0.3)),
                                    ),
                                    child: Row(children: [
                                      Icon(
                                          _statusIcon(_hearing!['status'] ??
                                              'scheduled'),
                                          color: info.color,
                                          size: 22),
                                      const SizedBox(width: 10),
                                      Expanded(
                                          child: Text(info.label.toUpperCase(),
                                              style: TextStyle(
                                                  color: info.color,
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 14))),
                                      GestureDetector(
                                        onTap: _showUpdateSheet,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 5),
                                          decoration: BoxDecoration(
                                              color: _brown,
                                              borderRadius:
                                                  BorderRadius.circular(8)),
                                          child: const Text('Update',
                                              style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700)),
                                        ),
                                      ),
                                    ]),
                                  );
                                }),
                                const SizedBox(height: 14),

                                // Case / client context
                                if (_nonempty(_hearing!['case_title']) ||
                                    _nonempty(_hearing!['client_name'])) ...[
                                  _Card(
                                      title: 'Case',
                                      icon: Icons.folder_rounded,
                                      children: [
                                        if (_nonempty(_hearing!['case_title']))
                                          _Row(Icons.gavel_rounded, 'Case',
                                              _hearing!['case_title']),
                                        if (_nonempty(_hearing!['case_number']))
                                          _Row(Icons.tag_rounded, 'Case Number',
                                              _hearing!['case_number']),
                                        if (_nonempty(_hearing!['client_name']))
                                          _Row(Icons.person_rounded, 'Client',
                                              _hearing!['client_name']),
                                      ]),
                                  const SizedBox(height: 10),
                                ],

                                // Date & Time
                                _Card(
                                    title: 'Date & Time',
                                    icon: Icons.event_rounded,
                                    children: [
                                      _Row(Icons.calendar_today_rounded, 'Date',
                                          _safe(_hearing!['hearing_date'])),
                                      if (_nonempty(_hearing!['hearing_time']))
                                        _Row(Icons.access_time_rounded, 'Time',
                                            _hearing!['hearing_time']),
                                    ]),
                                const SizedBox(height: 10),

                                // Court Details
                                _Card(
                                    title: 'Court Details',
                                    icon: Icons.account_balance_rounded,
                                    children: [
                                      _Row(
                                          Icons.account_balance_rounded,
                                          'Court Name',
                                          _hearing!['court_name'] ?? ''),
                                      if (_nonempty(_hearing!['court_room']))
                                        _Row(
                                            Icons.door_front_door_rounded,
                                            'Court Room',
                                            _hearing!['court_room']),
                                      if (_nonempty(_hearing!['judge_name']))
                                        _Row(Icons.person_rounded, 'Judge',
                                            _hearing!['judge_name']),
                                    ]),
                                const SizedBox(height: 10),

                                // Hearing Info
                                _Card(
                                    title: 'Hearing Details',
                                    icon: Icons.info_outline_rounded,
                                    children: [
                                      if (_nonempty(_hearing!['purpose']))
                                        _Row(Icons.topic_rounded, 'Purpose',
                                            _hearing!['purpose']),
                                      if (_nonempty(_hearing!['notes']))
                                        _Row(Icons.note_rounded, 'Notes',
                                            _hearing!['notes']),
                                    ]),

                                // Previous Hearing — what happened last time,
                                // so a lawyer opening this screen doesn't have
                                // to hunt through the case's full history.
                                if (_previousHearing != null) ...[
                                  const SizedBox(height: 10),
                                  _Card(
                                      title: 'Previous Hearing',
                                      icon: Icons.history_rounded,
                                      accentColor: const Color(0xFF7B7594),
                                      children: [
                                        _Row(
                                            Icons.calendar_today_rounded,
                                            'Date',
                                            _safe(_previousHearing![
                                                'hearing_date'])),
                                        if (_nonempty(
                                            _previousHearing!['purpose']))
                                          _Row(Icons.topic_rounded, 'Purpose',
                                              _previousHearing!['purpose']),
                                        _Row(
                                            Icons.flag_rounded,
                                            'Status',
                                            hearingStatusInfo(
                                                    _previousHearing!)
                                                .label),
                                        if (_nonempty(_previousHearing![
                                            'order_summary']))
                                          _Row(
                                              Icons.gavel_rounded,
                                              'Order Summary',
                                              _previousHearing![
                                                  'order_summary']),
                                      ]),
                                ],

                                // Order Summary (after hearing)
                                if (_nonempty(_hearing!['order_summary'])) ...[
                                  const SizedBox(height: 10),
                                  _Card(
                                      title: 'Order Summary',
                                      icon: Icons.gavel_rounded,
                                      accentColor: _gold,
                                      children: [
                                        Text(_hearing!['order_summary'],
                                            style: const TextStyle(
                                                color: _textPri,
                                                fontSize: 13,
                                                height: 1.5)),
                                      ]),
                                ],

                                // Next Date
                                if (_nonempty(_hearing!['next_date'])) ...[
                                  const SizedBox(height: 10),
                                  _Card(
                                      title: 'Next Hearing',
                                      icon: Icons.event_repeat_rounded,
                                      accentColor: const Color(0xFF4A90D9),
                                      children: [
                                        _Row(
                                            Icons.calendar_today_rounded,
                                            'Next Date',
                                            _safe(_hearing!['next_date'])),
                                      ]),
                                ],

                                // Remarks
                                if (_nonempty(_hearing!['remarks'])) ...[
                                  const SizedBox(height: 10),
                                  _Card(
                                      title: 'Remarks',
                                      icon: Icons.notes_rounded,
                                      children: [
                                        Text(_hearing!['remarks'],
                                            style: const TextStyle(
                                                color: _textPri,
                                                fontSize: 13,
                                                height: 1.5)),
                                      ]),
                                ],

                                // Relevant Documents — the case's documents,
                                // since a hearing has no file store of its
                                // own; this is what "relevant documents" maps
                                // to without inventing a separate attachment
                                // system just for hearings.
                                if (_caseDocuments.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  _Card(
                                      title: 'Relevant Documents',
                                      icon: Icons.attach_file_rounded,
                                      children: _caseDocuments
                                          .take(5)
                                          .map<Widget>((d) => InkWell(
                                                onTap: () => context
                                                    .push('/documents/${d['id']}'),
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                          vertical: 6),
                                                  child: Row(children: [
                                                    const Icon(
                                                        Icons
                                                            .description_outlined,
                                                        color: _gold,
                                                        size: 16),
                                                    const SizedBox(width: 10),
                                                    Expanded(
                                                        child: Text(
                                                            d['file_name'] ??
                                                                'Document',
                                                            style: const TextStyle(
                                                                color: _textPri,
                                                                fontSize: 13,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w500),
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis)),
                                                    const Icon(
                                                        Icons
                                                            .chevron_right_rounded,
                                                        color: _textMuted,
                                                        size: 16),
                                                  ]),
                                                ),
                                              ))
                                          .toList()),
                                ],

                                const SizedBox(height: 20),

                                // Update button at bottom
                                SizedBox(
                                  width: double.infinity,
                                  height: 50,
                                  child: ElevatedButton.icon(
                                    onPressed: _showUpdateSheet,
                                    icon: const Icon(Icons.update_rounded,
                                        color: Colors.white, size: 18),
                                    label: const Text('Update After Hearing',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15)),
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: _brown,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(14))),
                                  ),
                                ),
                                const SizedBox(height: 40),
                              ]),
                        ),
            ),
          ]),
        ),
      ),
    );
  }

  bool _nonempty(dynamic v) => v != null && v.toString().isNotEmpty;
  String _safe(dynamic v) {
    final s = v?.toString() ?? '';
    return s.length >= 10 ? s.substring(0, 10) : s;
  }
}

class _Card extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  final Color accentColor;
  const _Card(
      {required this.title,
      required this.icon,
      required this.children,
      this.accentColor = _brown});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: _bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border, width: 0.8),
            boxShadow: [
              BoxShadow(
                  color: _brown.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2))
            ]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                    color: accentColor, borderRadius: BorderRadius.circular(7)),
                child: Icon(icon, color: Colors.white, size: 14)),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(
                    color: _textPri,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
          ]),
          Divider(color: _border, height: 16, thickness: 0.6),
          ...children,
        ]),
      );
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _Row(this.icon, this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: _gold, size: 15),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(label,
                    style: const TextStyle(color: _textMuted, fontSize: 11)),
                Text(value,
                    style: const TextStyle(
                        color: _textPri,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
              ])),
        ]),
      );
}
