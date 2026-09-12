import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/services/dio_client.dart';
import '../../../core/services/realtime_events.dart';

// Same palette as lawyer_earnings_screen.dart / dashboard_screen.dart — this
// is a detail view of the same Billing ledger, not a new screen design.
const _bg = Color(0xFFF6F5FB);
const _bgCard = Color(0xFFFFFFFF);
const _brown = Color(0xFF150E3D);
const _brownDark = Color(0xFF0B0726);
const _border = Color(0xFFE6E3F4);
const _textPri = Color(0xFF1B1533);
const _textMuted = Color(0xFF7B7594);
const _green = Color(0xFF2E8B57);
const _red = Color(0xFFD9534F);
const _gold = Color(0xFFD4AF37);
const _blue = Color(0xFF4A90D9);

/// Full bill/transaction details for one consultation booking, opened by
/// tapping a card in the lawyer's Billing → Transaction History list.
/// Reuses the existing GET /consultations/:id endpoint (already used by both
/// the lawyer and client consultation screens) — no separate/fake billing
/// record is created here, this only surfaces fields already on
/// `consultations` in more detail than the list card shows.
class BillDetailsScreen extends StatefulWidget {
  final String consultationId;
  const BillDetailsScreen({super.key, required this.consultationId});

  @override
  State<BillDetailsScreen> createState() => _BillDetailsScreenState();
}

class _BillDetailsScreenState extends State<BillDetailsScreen> {
  Map<String, dynamic>? _bill;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    // A status change (pending→paid, refund) or a live call ending (which
    // records session duration) pushes through the existing FCM-backed event
    // bus — refresh this bill without a manual pull.
    RealtimeEvents.instance.addListener(_onRealtimeEvent);
  }

  void _onRealtimeEvent() {
    if (RealtimeEvents.instance.matches(
        ['booking_', 'incoming_call_', 'chat_session_started', 'call_response_'])) {
      _load(silent: true);
    }
  }

  @override
  void dispose() {
    RealtimeEvents.instance.removeListener(_onRealtimeEvent);
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final res = await DioClient.instance
          .get('/consultations/${widget.consultationId}');
      if (!mounted) return;
      setState(() {
        _bill = res.data['data'] as Map<String, dynamic>?;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _error = 'Failed to load bill details';
      });
    }
  }

  String _serviceLabel(String type) {
    switch (type) {
      case 'chat':
        return 'Chat';
      case 'audio':
        return 'Audio Call';
      case 'video':
        return 'Video Call';
      case 'visit':
      case 'office_visit':
        return 'Visit';
      default:
        return type.isEmpty ? '-' : type;
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

  Color _paymentStatusColor(String s) => switch (s) {
        'paid' => _green,
        'refunded' => _red,
        'failed' => _red,
        _ => _gold,
      };

  String _fmtDateTime(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    if (d == null) return '-';
    return DateFormat('d MMM yyyy, h:mm a').format(d.toLocal());
  }

  String _fmtDuration(int seconds) {
    if (seconds <= 0) return 'Not started';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return s > 0 ? '$m min $s sec' : '$m minutes';
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
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 16, 16),
                child: Row(children: [
                  IconButton(
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: Colors.white),
                      onPressed: () => context.pop()),
                  const Expanded(
                      child: Text('Bill Details',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700))),
                  const SizedBox(width: 48),
                ]),
              )),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: _brown))
              : _error != null || _bill == null
                  ? _buildError()
                  : RefreshIndicator(
                      color: _brown,
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: _buildContent(_bill!),
                      ),
                    ),
        ),
      ]),
    );
  }

  Widget _buildError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline_rounded, size: 44, color: _red),
            const SizedBox(height: 16),
            Text(_error ?? 'Bill not found',
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: _textPri, fontSize: 14, height: 1.5)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _load,
              style: ElevatedButton.styleFrom(
                  backgroundColor: _brown,
                  shape:
                      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('Retry', style: TextStyle(color: Colors.white)),
            ),
          ]),
        ),
      );

  List<Widget> _buildContent(Map<String, dynamic> b) {
    final amountPaise = (b['amount_paise'] ?? 0) as num;
    final totalAmount = amountPaise.toDouble() / 100;
    final paymentStatus = (b['payment_status'] ?? 'pending').toString();
    final amountPaid = paymentStatus == 'paid' ? totalAmount : 0.0;
    final amountDue = paymentStatus == 'paid' ? 0.0 : totalAmount;
    final status = (b['status'] ?? 'pending').toString();
    final duration = (b['call_duration_seconds'] ?? 0) as int;
    final proofColor = _textMuted;

    return [
      // ── Booking ID + status header ──
      Container(
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
            Expanded(
                child: Text('Booking ID: ${b['id'] ?? '-'}',
                    style: const TextStyle(
                        color: _brown,
                        fontSize: 13,
                        fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: _blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Text('Booking: ${_statusLabel(status)}',
                  style: const TextStyle(
                      color: _blue, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: _paymentStatusColor(paymentStatus).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Text('Payment: ${paymentStatus.toUpperCase()}',
                  style: TextStyle(
                      color: _paymentStatusColor(paymentStatus),
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
        ]),
      ),
      const SizedBox(height: 14),

      _sectionCard('Client Details', Icons.person_outline_rounded, [
        _row('Client Name', b['client_name'] ?? '-'),
        if ((b['client_email'] ?? '').toString().isNotEmpty)
          _row('Email', b['client_email']),
        if ((b['client_phone'] ?? '').toString().isNotEmpty)
          _row('Phone', b['client_phone']),
      ]),
      const SizedBox(height: 14),

      _sectionCard('Booking Details', Icons.event_note_rounded, [
        _row('Service Type', _serviceLabel(b['consultation_type'] ?? '')),
        _row('Booking Date', b['consultation_date'] ?? '-'),
        _row('Booking Time', b['consultation_time'] ?? '-'),
        _row('Session Duration', _fmtDuration(duration)),
        _row('Booking Created', _fmtDateTime(b['created_at']?.toString())),
      ]),
      const SizedBox(height: 14),

      _sectionCard('Payment Details', Icons.payments_outlined, [
        _row('Total Amount', '₹${totalAmount.toStringAsFixed(2)}',
            valColor: _brown, bold: true),
        _row('Amount Paid', '₹${amountPaid.toStringAsFixed(2)}',
            valColor: _green),
        if (amountDue > 0)
          _row('Amount Pending', '₹${amountDue.toStringAsFixed(2)}',
              valColor: _red),
        _row('Payment Status', paymentStatus.toUpperCase(),
            valColor: _paymentStatusColor(paymentStatus)),
        if (b['paid_at'] != null)
          _row('Payment Date', _fmtDateTime(b['paid_at']?.toString())),
        if ((b['payment_method'] ?? '').toString().isNotEmpty)
          _row('Payment Method', b['payment_method']),
        if ((b['razorpay_payment_id'] ?? '').toString().isNotEmpty)
          _row('Payment/Transaction ID', b['razorpay_payment_id']),
        if ((b['razorpay_order_id'] ?? '').toString().isNotEmpty)
          _row('Razorpay Order ID', b['razorpay_order_id']),
      ]),
      const SizedBox(height: 14),

      if ((b['notes'] ?? '').toString().isNotEmpty ||
          (b['lawyer_notes'] ?? '').toString().isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: _sectionCard('Notes', Icons.note_outlined, [
            if ((b['notes'] ?? '').toString().isNotEmpty)
              _noteBlock('Client Notes', b['notes']),
            if ((b['lawyer_notes'] ?? '').toString().isNotEmpty)
              _noteBlock('Lawyer Notes', b['lawyer_notes']),
          ]),
        ),

      // ── Payment Proof ──
      // Consultation payments go through Razorpay only — there is no
      // client-uploaded-slip flow on this booking type (that only exists for
      // the firm's manual invoices), so a real, honest "not uploaded" state
      // is shown rather than fabricating a proof.
      Container(
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
                child: const Icon(Icons.receipt_long_rounded,
                    color: Colors.white, size: 13)),
            const SizedBox(width: 8),
            const Text('Payment Proof',
                style: TextStyle(
                    color: _brown, fontSize: 13, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 2),
          Divider(color: _border, height: 20, thickness: 0.6),
          Row(children: [
            Icon(Icons.info_outline_rounded, color: proofColor, size: 16),
            const SizedBox(width: 8),
            Expanded(
                child: Text(
                    paymentStatus == 'paid'
                        ? 'Payment Proof Not Uploaded — verified automatically via Razorpay'
                        : 'Payment Proof Not Uploaded',
                    style: TextStyle(color: proofColor, fontSize: 13))),
          ]),
        ]),
      ),
      const SizedBox(height: 40),
    ];
  }

  Widget _sectionCard(String title, IconData icon, List<Widget> children) =>
      Container(
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
          ...children,
        ]),
      );

  Widget _row(String label, dynamic value, {Color? valColor, bool bold = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: const TextStyle(color: _textMuted, fontSize: 13)),
          Flexible(
              child: Text('$value',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      color: valColor ?? _textPri,
                      fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                      fontSize: bold ? 15 : 13))),
        ]),
      );

  Widget _noteBlock(String label, dynamic value) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(
                  color: _textMuted, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text('$value',
              style: const TextStyle(color: _textPri, fontSize: 13, height: 1.4)),
        ]),
      );
}
