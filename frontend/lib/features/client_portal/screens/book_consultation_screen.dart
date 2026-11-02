import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/dio_client.dart';
import '../../../core/services/auto_refresh_service.dart';
import '../repositories/consultation_repository.dart';

const _bg = Color(0xFFF0FAF6);
const _bgCard = Color(0xFFFFFFFF);
const _green = Color(0xFF0D6E4F);
const _border = Color(0xFFB2DFD0);
const _textPri = Color(0xFF0A2E1F);
const _textMuted = Color(0xFF4A7A63);

class BookConsultationScreen extends StatefulWidget {
  final String lawyerId;
  final String lawyerName;
  const BookConsultationScreen(
      {super.key, required this.lawyerId, required this.lawyerName});
  @override
  State<BookConsultationScreen> createState() => _BookConsultationScreenState();
}

class _BookConsultationScreenState extends State<BookConsultationScreen> {
  int _step = 0; // 0=type, 1=date/time, 2=confirm
  String _selectedType = '';
  DateTime? _selectedDate;
  String _selectedTime = '';
  bool _loading = false;
  final _notesCtrl = TextEditingController();
  final _consultRepo = ConsultationRepository();

  // The lawyer's profile photo — this screen previously showed only the name
  // everywhere (header and the final confirmation summary), with no visual
  // confirmation of which lawyer this booking/payment is actually for.
  // /student/lawyer/:id is the existing lawyer-directory detail endpoint
  // (already reachable by a client — find_lawyer_screen.dart uses the list
  // form of the same route), so this reuses it rather than adding a new one.
  String _avatarUrl = '';

  // Which of this lawyer's slots on the selected date are already held by an
  // active booking (theirs or someone else's) — refetched every time the
  // date changes so the picker reflects reality instead of only finding out
  // a slot is gone when payment is attempted. The database is still the real
  // enforcement (see uq_consultations_active_slot / 409 handling in
  // _payAndConfirm's catch below); this is purely so the UI doesn't offer a
  // slot it already knows is taken.
  Set<String> _bookedTimes = {};
  bool _loadingSlots = false;

  @override
  void initState() {
    super.initState();
    _loadLawyerPhoto();
    // Slot availability has no push event of its own (another client booking
    // the same slot doesn't notify this device) — this is the one place the
    // global 3-second poll is the ONLY way to keep the picker from offering
    // a slot someone else just took, short of the server-side unique-slot
    // check at payment time.
    AutoRefreshService.instance.register('booked_slots', () {
      final date = _selectedDate;
      if (date == null) return Future.value();
      return _loadBookedSlots(date, silent: true);
    });
  }

  Future<void> _loadBookedSlots(DateTime date, {bool silent = false}) async {
    if (!silent) setState(() => _loadingSlots = true);
    try {
      final iso = date.toIso8601String().substring(0, 10);
      final res = await DioClient.instance
          .get('/portal/lawyers/${widget.lawyerId}/booked-slots',
              queryParameters: {'date': iso});
      final times = (res.data['data']?['booked_times'] as List?) ?? [];
      if (!mounted) return;
      setState(() {
        _bookedTimes = times.map((t) => t.toString()).toSet();
        _loadingSlots = false;
        // The previously selected time may have just become unavailable on
        // this date (or a different date was picked) — don't leave a now-
        // taken slot silently selected.
        if (_bookedTimes.contains(_selectedTime)) _selectedTime = '';
      });
    } catch (_) {
      // Best-effort — the real enforcement is server-side at payment time
      // regardless, so a failed fetch here just means the picker doesn't
      // pre-emptively grey anything out.
      if (!silent && mounted) setState(() => _loadingSlots = false);
    }
  }

  Future<void> _loadLawyerPhoto() async {
    try {
      final res =
          await DioClient.instance.get('/student/lawyer/${widget.lawyerId}');
      final url =
          (res.data['data']?['lawyer']?['avatar_url'] ?? '').toString();
      if (mounted && url.isNotEmpty) setState(() => _avatarUrl = url);
    } catch (_) {
      // No photo shown is a fine fallback — this is a nice-to-have, not
      // something that should block or error the booking flow.
    }
  }

  final List<Map<String, dynamic>> _consultTypes = [
    {
      'type': 'Chat',
      'icon': Icons.chat_rounded,
      'color': const Color(0xFF0D6E4F),
      'emoji': '💬',
      'desc': 'Text consultation online'
    },
    {
      'type': 'Audio Call',
      'icon': Icons.phone_rounded,
      'color': const Color(0xFF1565C0),
      'emoji': '📞',
      'desc': 'Voice call with lawyer'
    },
    {
      'type': 'Video Call',
      'icon': Icons.videocam_rounded,
      'color': const Color(0xFF7C3AED),
      'emoji': '📹',
      'desc': 'Face to face video call'
    },
    {
      'type': 'Office Visit',
      'icon': Icons.business_center_rounded,
      'color': const Color(0xFFD4A017),
      'emoji': '🏢',
      'desc': 'Visit lawyer at office'
    },
  ];

  final List<String> _timeSlots = [
    '9:00 AM',
    '9:30 AM',
    '10:00 AM',
    '10:30 AM',
    '11:00 AM',
    '11:30 AM',
    '12:00 PM',
    '12:30 PM',
    '2:00 PM',
    '2:30 PM',
    '3:00 PM',
    '3:30 PM',
    '4:00 PM',
    '4:30 PM',
    '5:00 PM',
    '5:30 PM',
  ];

  @override
  void dispose() {
    AutoRefreshService.instance.unregister('booked_slots');
    _notesCtrl.dispose();
    super.dispose();
  }

  /// Books the consultation directly, with no payment gateway — Razorpay
  /// checkout is turned off for clients for now. The booking is created and
  /// the lawyer notified in one request; no retry/poll logic is needed here
  /// since there's no external payment page to fail or cancel out of.
  Future<void> _payAndConfirm() async {
    setState(() => _loading = true);

    try {
      await _consultRepo.bookWithoutPayment(
        lawyerId: widget.lawyerId,
        consultationType: _selectedType,
        consultationDate: _selectedDate!.toIso8601String().substring(0, 10),
        consultationTime: _selectedTime,
        notes: _notesCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() => _loading = false);
      HapticFeedback.heavyImpact();
      _showSuccessDialog();
    } on ConsultationPaymentException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.message),
          backgroundColor: const Color(0xFFD9534F)));
    }
  }

  void _showSuccessDialog() {
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
              backgroundColor: _bgCard,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                        color: _green.withValues(alpha: 0.1), shape: BoxShape.circle),
                    child: const Icon(Icons.check_circle_rounded,
                        color: _green, size: 48)),
                const SizedBox(height: 16),
                const Text('Payment Successful',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: _textPri,
                        fontSize: 20,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text('Booking Confirmed!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: _green,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                    '₹5 paid. Your $_selectedType consultation with ${widget.lawyerName} on ${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year} at $_selectedTime is confirmed.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: _textMuted, fontSize: 13, height: 1.5)),
                const SizedBox(height: 20),
                Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: _green.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _border)),
                    child: const Row(children: [
                      Icon(Icons.info_outline_rounded, color: _green, size: 16),
                      SizedBox(width: 8),
                      Expanded(
                          child: Text(
                              'Your lawyer has been notified of the confirmed booking.',
                              style: TextStyle(color: _green, fontSize: 12))),
                    ])),
              ]),
              actions: [
                SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        context.pop();
                        context.pop();
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _green,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12))),
                      child: const Text('Done',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700)),
                    )),
              ],
            ));
  }

  /// Steps back through the wizard one screen at a time; only leaves the
  /// flow entirely (back to Find a Lawyer) once already on step 0. Used by
  /// both the header arrow and the system/gesture back button, so neither
  /// can skip the wizard and drop straight to Home.
  void _handleBack() {
    if (_step > 0) {
      setState(() => _step--);
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _step--);
      },
      child: Scaffold(
      backgroundColor: _bg,
      body: Column(children: [
        // Header
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [Color(0xFF0A4A32), Color(0xFF0D6E4F)],
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
                        onPressed: _handleBack),
                    Expanded(
                        child: Column(children: [
                      const Text('Book Consultation',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                      Text('with ${widget.lawyerName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12)),
                    ])),
                    _LawyerAvatar(
                        avatarUrl: _avatarUrl,
                        name: widget.lawyerName,
                        size: 36),
                  ]),
                ),
                // Step indicator
                Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    child: Row(children: [
                      _StepDot(step: 0, current: _step, label: 'Type'),
                      Expanded(
                          child: Container(
                              height: 2,
                              color: _step > 0
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.3))),
                      _StepDot(step: 1, current: _step, label: 'Date'),
                      Expanded(
                          child: Container(
                              height: 2,
                              color: _step > 1
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.3))),
                      _StepDot(step: 2, current: _step, label: 'Confirm'),
                    ])),
              ])),
        ),

        Expanded(
            child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: _step == 0
              ? _buildTypeStep()
              : _step == 1
                  ? _buildDateStep()
                  : _buildConfirmStep(),
        )),

        // Bottom button
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          decoration: BoxDecoration(
              color: _bgCard,
              border: Border(top: BorderSide(color: _border, width: 0.8)),
              boxShadow: [
                BoxShadow(
                    color: _green.withValues(alpha: 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, -3))
              ]),
          child: SafeArea(
              top: false,
              child: Row(children: [
                if (_step > 0) ...[
                  Expanded(
                      child: OutlinedButton(
                    onPressed: () => setState(() => _step--),
                    style: OutlinedButton.styleFrom(
                        side: BorderSide(color: _border),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    child:
                        const Text('Back', style: TextStyle(color: _textMuted)),
                  )),
                  const SizedBox(width: 12),
                ],
                Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _canProceed()
                          ? () {
                              if (_step < 2) {
                                setState(() => _step++);
                              } else {
                                _payAndConfirm();
                              }
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _green,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: _loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : Text(_step != 2 ? 'Next →' : 'Confirm Booking',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15)),
                    )),
              ])),
        ),
      ]),
      ),
    );
  }

  bool _canProceed() {
    if (_step == 0) return _selectedType.isNotEmpty;
    if (_step == 1) return _selectedDate != null && _selectedTime.isNotEmpty;
    return true;
  }

  // ── Step 1: Select consultation type ─────────────
  Widget _buildTypeStep() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Select Consultation Type',
            style: TextStyle(
                color: _textPri, fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('How would you like to consult?',
            style: TextStyle(color: _textMuted, fontSize: 13)),
        const SizedBox(height: 20),
        ..._consultTypes.map((t) {
          final sel = _selectedType == t['type'];
          final color = t['color'] as Color;
          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() => _selectedType = t['type']);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: sel ? color.withValues(alpha: 0.06) : _bgCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: sel ? color : _border, width: sel ? 2 : 0.8),
                boxShadow: [
                  BoxShadow(
                      color: _green.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ],
              ),
              child: Row(children: [
                Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14)),
                    child: Icon(t['icon'] as IconData, color: color, size: 26)),
                const SizedBox(width: 14),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(t['type'],
                          style: TextStyle(
                              color: sel ? color : _textPri,
                              fontWeight: FontWeight.w700,
                              fontSize: 15)),
                      Text(t['desc'],
                          style:
                              const TextStyle(color: _textMuted, fontSize: 12)),
                    ])),
                if (sel)
                  Icon(Icons.check_circle_rounded, color: color, size: 24)
                else
                  Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: _border, width: 1.5))),
              ]),
            ),
          );
        }),
      ]);

  // ── Step 2: Select date & time ────────────────────
  Widget _buildDateStep() {
    final now = DateTime.now();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Select Date & Time',
          style: TextStyle(
              color: _textPri, fontSize: 18, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      const Text('Pick your preferred slot',
          style: TextStyle(color: _textMuted, fontSize: 13)),
      const SizedBox(height: 20),

      // Date picker
      const Text('Date',
          style: TextStyle(
              color: _textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      SizedBox(
          height: 90,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: 14,
            itemBuilder: (_, i) {
              final date = now.add(Duration(days: i));
              final sel = _selectedDate?.day == date.day &&
                  _selectedDate?.month == date.month;
              final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
              final day = i == 0 ? 'Today' : days[date.weekday - 1];
              return GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() => _selectedDate = date);
                  _loadBookedSlots(date);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 10),
                  width: 62,
                  decoration: BoxDecoration(
                    color: sel ? _green : _bgCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: sel ? _green : _border, width: sel ? 2 : 0.8),
                  ),
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(day,
                            style: TextStyle(
                                color: sel ? Colors.white70 : _textMuted,
                                fontSize: 11)),
                        const SizedBox(height: 4),
                        Text('${date.day}',
                            style: TextStyle(
                                color: sel ? Colors.white : _textPri,
                                fontWeight: FontWeight.w800,
                                fontSize: 20)),
                        Text(_monthName(date.month),
                            style: TextStyle(
                                color: sel ? Colors.white70 : _textMuted,
                                fontSize: 10)),
                      ]),
                ),
              );
            },
          )),
      const SizedBox(height: 20),

      // Time slots
      Row(children: [
        const Text('Time',
            style: TextStyle(
                color: _textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
        if (_loadingSlots) ...[
          const SizedBox(width: 8),
          const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.6, color: _green)),
        ],
      ]),
      const SizedBox(height: 8),
      Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _timeSlots.map((time) {
            final sel = _selectedTime == time;
            final booked = _bookedTimes.contains(time);
            return GestureDetector(
              onTap: booked
                  ? null
                  : () {
                      HapticFeedback.lightImpact();
                      setState(() => _selectedTime = time);
                    },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: booked
                      ? _border.withValues(alpha: 0.4)
                      : sel
                          ? _green
                          : _bgCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: booked ? _border : (sel ? _green : _border),
                      width: sel && !booked ? 2 : 0.8),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(time,
                      style: TextStyle(
                          color: booked
                              ? _textMuted
                              : sel
                                  ? Colors.white
                                  : _textPri,
                          fontSize: 12,
                          decoration: booked
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                          fontWeight:
                              sel && !booked ? FontWeight.w700 : FontWeight.w400)),
                  if (booked)
                    const Text('Booked',
                        style: TextStyle(
                            color: _textMuted,
                            fontSize: 8,
                            fontWeight: FontWeight.w700)),
                ]),
              ),
            );
          }).toList()),
    ]);
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

  // ── Step 3: Confirm ───────────────────────────────
  Widget _buildConfirmStep() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Confirm Booking',
            style: TextStyle(
                color: _textPri, fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('Review your consultation details',
            style: TextStyle(color: _textMuted, fontSize: 13)),
        const SizedBox(height: 20),

        Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: _bgCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _green.withValues(alpha: 0.2)),
                boxShadow: [
                  BoxShadow(
                      color: _green.withValues(alpha: 0.06),
                      blurRadius: 10,
                      offset: const Offset(0, 3))
                ]),
            child: Column(children: [
              Row(children: [
                _LawyerAvatar(
                    avatarUrl: _avatarUrl, name: widget.lawyerName, size: 44),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(widget.lawyerName,
                        style: const TextStyle(
                            color: _textPri,
                            fontSize: 16,
                            fontWeight: FontWeight.w800),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis)),
              ]),
              Divider(color: _border, height: 20, thickness: 0.6),
              _ConfirmRow('Lawyer', widget.lawyerName, Icons.person_rounded),
              Divider(color: _border, height: 20, thickness: 0.6),
              _ConfirmRow('Type', _selectedType, Icons.category_rounded),
              Divider(color: _border, height: 20, thickness: 0.6),
              _ConfirmRow(
                  'Date',
                  '${_selectedDate?.day}/${_selectedDate?.month}/${_selectedDate?.year}',
                  Icons.calendar_today_rounded),
              Divider(color: _border, height: 20, thickness: 0.6),
              _ConfirmRow('Time', _selectedTime, Icons.access_time_rounded),
              Divider(color: _border, height: 20, thickness: 0.6),
              _ConfirmRow('Amount', '₹5', Icons.currency_rupee_rounded),
            ])),
        const SizedBox(height: 16),

        // Notes
        const Text('Additional Notes (Optional)',
            style: TextStyle(
                color: _textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: _notesCtrl,
          maxLines: 3,
          style: const TextStyle(color: _textPri, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Describe your legal issue briefly...',
            hintStyle: const TextStyle(color: _textMuted, fontSize: 13),
            filled: true,
            fillColor: _bgCard,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _border, width: 0.8)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _green, width: 1.5)),
          ),
        ),
        const SizedBox(height: 16),

        Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: _green.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border)),
            child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.notifications_active_outlined,
                      color: _green, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                      child: Text(
                          'Your booking is confirmed instantly and your lawyer is '
                          'notified right away.',
                          style: TextStyle(
                              color: _green, fontSize: 12, height: 1.4))),
                ])),
      ]);
}

/// Shows the lawyer's uploaded profile photo (same avatar_url/data-URI format
/// used everywhere else this app renders one — profile_screen.dart,
/// find_lawyer_screen.dart, dashboard_screen.dart), falling back to an
/// initial in a circle when there is none, exactly like those screens do.
class _LawyerAvatar extends StatelessWidget {
  final String avatarUrl;
  final String name;
  final double size;
  const _LawyerAvatar(
      {required this.avatarUrl, required this.name, required this.size});

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'L';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _green.withValues(alpha: 0.12),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: ClipOval(
        child: avatarUrl.isNotEmpty
            ? Image.memory(
                base64Decode(
                    avatarUrl.replaceFirst(RegExp(r'^data:image/\w+;base64,'), '')),
                fit: BoxFit.cover,
                width: size,
                height: size,
                errorBuilder: (_, __, ___) => _initialText(initial),
              )
            : _initialText(initial),
      ),
    );
  }

  Widget _initialText(String initial) => Center(
      child: Text(initial,
          style: TextStyle(
              color: _green,
              fontWeight: FontWeight.w800,
              fontSize: size * 0.4)));
}

class _ConfirmRow extends StatelessWidget {
  final String label, value;
  final IconData icon;
  const _ConfirmRow(this.label, this.value, this.icon);
  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                color: _green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: _green, size: 18)),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: _textMuted, fontSize: 11)),
          Text(value,
              style: const TextStyle(
                  color: _textPri, fontWeight: FontWeight.w600, fontSize: 14)),
        ])),
      ]);
}

class _StepDot extends StatelessWidget {
  final int step, current;
  final String label;
  const _StepDot(
      {required this.step, required this.current, required this.label});
  @override
  Widget build(BuildContext context) {
    final done = current > step;
    final active = current == step;
    return Column(children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: done || active ? Colors.white : Colors.white.withValues(alpha: 0.3),
          shape: BoxShape.circle,
        ),
        child: Center(
            child: done
                ? const Icon(Icons.check_rounded, color: _green, size: 16)
                : Text('${step + 1}',
                    style: TextStyle(
                        color: active ? _green : Colors.white.withValues(alpha: 0.5),
                        fontWeight: FontWeight.w800,
                        fontSize: 13))),
      ),
      const SizedBox(height: 4),
      Text(label,
          style: TextStyle(
              color:
                  active || done ? Colors.white : Colors.white.withValues(alpha: 0.5),
              fontSize: 10)),
    ]);
  }
}
