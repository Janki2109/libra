import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/services/dio_client.dart';
import '../../../core/utils/file_opener.dart';

const _bg = Color(0xFFF6F5FB);
const _bgCard = Color(0xFFFFFFFF);
const _brown = Color(0xFF150E3D);
const _brownLight = Color(0xFF3D2C8D);
const _gold = Color(0xFFB8860B);
const _border = Color(0xFFE6E3F4);
const _textPri = Color(0xFF2C1A0E);
const _textMuted = Color(0xFF3D2C8D);

class PaymentVerificationScreen extends StatefulWidget {
  const PaymentVerificationScreen({super.key});
  @override
  State<PaymentVerificationScreen> createState() =>
      _PaymentVerificationScreenState();
}

class _PaymentVerificationScreenState extends State<PaymentVerificationScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> _pending = [];
  List<dynamic> _verified = [];
  bool _loading = true;
  final Set<String> _refunding = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        DioClient.instance.get('/invoices/pending-verification'),
        DioClient.instance.get('/payments', queryParameters: {
          'status': 'verified',
          'limit': 50,
        }),
      ]);
      setState(() {
        _pending = results[0].data['data'] ?? [];
        _verified = results[1].data['data'] ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  /// Opens the client's uploaded payment-proof image/document. The client
  /// side now uploads a real file (a data: URI, same inline-storage trick
  /// avatar_url/documents already use) instead of pasting a URL, so this can
  /// no longer assume it's a link to launch — that's also why this row used
  /// to do nothing at all when tapped.
  Future<void> _viewPaymentSlip(String slipUrl) async {
    if (!slipUrl.startsWith('data:')) {
      // A URL entered before this fix, or by an older client build — still
      // worth trying to open externally rather than failing silently.
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('This proof was submitted as a link; opening links '
              'from here is not supported — ask the client to re-upload.'),
          backgroundColor: Color(0xFFD9534F)));
      return;
    }
    try {
      final commaIndex = slipUrl.indexOf(',');
      final header = slipUrl.substring(5, commaIndex); // after "data:"
      final mimeType = header.split(';').first;
      final bytes = base64Decode(slipUrl.substring(commaIndex + 1));
      final ext = mimeType.contains('pdf') ? 'pdf' : 'jpg';
      final result = await openDocumentBytes(
          bytes: bytes, fileName: 'payment_proof.$ext', mimeType: mimeType);
      if (!result.success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(result.message ?? 'Could not open payment proof.'),
            backgroundColor: const Color(0xFFD9534F)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not open payment proof.'),
            backgroundColor: Color(0xFFD9534F)));
      }
    }
  }

  Future<void> _approve(String invoiceId, String paymentId) async {
    try {
      await DioClient.instance
          .put('/invoices/$invoiceId', data: {'status': 'paid'});
      // The verify endpoint only accepts 'verified' or 'rejected' — sending
      // 'approved' (the previous value here) made every approval fail with
      // a 400 even though the button showed no error, because the invoice
      // update above had already succeeded and _load() masked the mismatch
      // by simply re-fetching the (now-empty, since still 'pending' in
      // payments) pending list.
      await DioClient.instance
          .put('/payments/$paymentId/verify', data: {'status': 'verified'});
      HapticFeedback.heavyImpact();
      _load();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Payment approved! Invoice marked as PAID'),
          backgroundColor: Color(0xFF2E8B57),
          behavior: SnackBarBehavior.floating,
        ));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not approve payment: ${DioClient.describeError(e)}'),
          backgroundColor: const Color(0xFFD9534F),
          behavior: SnackBarBehavior.floating,
        ));
    }
  }

  Future<void> _payBack(Map payment) async {
    final amount = ((payment['amount'] ?? 0.0) as num).toDouble();
    final client = (payment['client_name'] ?? 'this client').toString();
    final paymentId = payment['id'].toString();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm Pay Back',
            style: TextStyle(color: _textPri, fontWeight: FontWeight.w700)),
        content: Text(
            'Are you sure you want to pay back ₹${amount.toStringAsFixed(2)} to $client?',
            style: const TextStyle(color: _textMuted, fontSize: 14)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: _textMuted))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD9534F),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            child: const Text('Confirm Pay Back',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (_refunding.contains(paymentId)) return; // already in flight
    setState(() => _refunding.add(paymentId));
    try {
      await DioClient.instance.post('/payments/$paymentId/refund');
      HapticFeedback.heavyImpact();
      await _load();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('₹${amount.toStringAsFixed(2)} paid back to $client'),
          backgroundColor: const Color(0xFF2E8B57),
          behavior: SnackBarBehavior.floating,
        ));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Pay back failed: ${DioClient.describeError(e)}'),
          backgroundColor: const Color(0xFFD9534F),
          behavior: SnackBarBehavior.floating,
        ));
    } finally {
      if (mounted) setState(() => _refunding.remove(paymentId));
    }
  }

  Future<void> _reject(String invoiceId, String paymentId) async {
    final reasonCtrl = TextEditingController();
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
              backgroundColor: _bgCard,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: const Text('Reject Payment',
                  style: TextStyle(
                      color: Color(0xFFD9534F), fontWeight: FontWeight.w700)),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('Reason for rejection:',
                    style: TextStyle(color: _textMuted)),
                const SizedBox(height: 10),
                TextField(
                    controller: reasonCtrl,
                    style: const TextStyle(color: _textPri),
                    decoration: InputDecoration(
                      hintText: 'e.g. Invalid transaction ID',
                      hintStyle: const TextStyle(color: _textMuted),
                      filled: true,
                      fillColor: _bg,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _border)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: Color(0xFFD9534F))),
                    )),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel',
                        style: TextStyle(color: _textMuted))),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    await DioClient.instance.put('/invoices/$invoiceId',
                        data: {'status': 'unpaid'});
                    await DioClient.instance
                        .put('/payments/$paymentId/verify', data: {
                      'status': 'rejected',
                      'rejection_reason': reasonCtrl.text.trim(),
                    });
                    _load();
                    if (mounted)
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Payment rejected. Client notified.'),
                        backgroundColor: Color(0xFFD9534F),
                        behavior: SnackBarBehavior.floating,
                      ));
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD9534F),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10))),
                  child: const Text('Reject',
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            ));
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light),
      child: Scaffold(
        backgroundColor: _bg,
        body: Column(children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [Color(0xFF150E3D), Color(0xFF0B0726)],
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
                    const SizedBox(width: 48),
                    Expanded(
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                          const Text('Payment Verification',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700)),
                          if (_pending.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                  color: _gold,
                                  borderRadius: BorderRadius.circular(10)),
                              child: Text('${_pending.length}',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12)),
                            ),
                          ],
                        ])),
                    IconButton(
                        icon: const Icon(Icons.refresh_rounded,
                            color: Colors.white),
                        onPressed: _load),
                  ]),
                ),
                TabBar(
                  controller: _tabController,
                  indicatorColor: _gold,
                  indicatorWeight: 3,
                  labelColor: _gold,
                  unselectedLabelColor: Colors.white60,
                  tabs: [
                    Tab(text: 'Pending (${_pending.length})'),
                    Tab(text: 'Verified (${_verified.length})'),
                  ],
                ),
              ])),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _brown))
                : TabBarView(
                    controller: _tabController,
                    children: [_buildPendingTab(), _buildVerifiedTab()],
                  ),
          ),
        ]),
      ),
    );
  }

  Widget _buildPendingTab() {
    if (_pending.isEmpty) {
      return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
                color: const Color(0xFF2E8B57).withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(
                    color: const Color(0xFF2E8B57).withValues(alpha: 0.3))),
            child: const Icon(Icons.check_circle_rounded,
                color: Color(0xFF2E8B57), size: 44)),
        const SizedBox(height: 16),
        const Text('All caught up! ✅',
            style: TextStyle(
                color: _textPri, fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text('No pending payment verifications',
            style: TextStyle(color: _textMuted)),
      ]));
    }
    return RefreshIndicator(
      color: _brown,
      backgroundColor: _bgCard,
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _pending.length,
        itemBuilder: (_, i) {
          final inv = _pending[i];
          final amount = ((inv['total_amount'] ?? 0.0) as num).toDouble();
          final txnId = inv['transaction_id'] ?? '';
          final slipUrl = inv['payment_slip_url'] ?? '';
          final paymentId = inv['payment_id'] ?? '';

          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
                color: _bgCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _gold.withValues(alpha: 0.3)),
                boxShadow: [
                  BoxShadow(
                      color: _brown.withValues(alpha: 0.07),
                      blurRadius: 10,
                      offset: const Offset(0, 3))
                ]),
            child: Column(children: [
              // Header
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.07),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(children: [
                  Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                          color: _gold.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.pending_rounded,
                          color: _gold, size: 22)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(inv['invoice_number'] ?? '',
                            style: const TextStyle(
                                color: _textPri,
                                fontWeight: FontWeight.w700,
                                fontSize: 15)),
                        Text(inv['client_name'] ?? 'Client',
                            style: const TextStyle(
                                color: _brownLight, fontSize: 12)),
                      ])),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                        color: _gold.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _gold.withValues(alpha: 0.4))),
                    child: const Text('PENDING',
                        style: TextStyle(
                            color: _gold,
                            fontSize: 10,
                            fontWeight: FontWeight.w800)),
                  ),
                ]),
              ),
              // Details
              Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(children: [
                    _InfoRow('Amount', '₹${amount.toStringAsFixed(2)}', _brown),
                    const SizedBox(height: 8),
                    _InfoRow(
                        'Transaction ID',
                        txnId.isNotEmpty ? txnId : 'Not provided',
                        txnId.isNotEmpty ? _textPri : const Color(0xFFD9534F)),
                    if (slipUrl.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () => _viewPaymentSlip(slipUrl),
                        child: _InfoRow('Payment Slip', 'View slip →',
                            const Color(0xFF4A90D9)),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(
                          child: OutlinedButton.icon(
                        onPressed: () => _reject(inv['id'], paymentId),
                        icon: const Icon(Icons.close_rounded,
                            color: Color(0xFFD9534F), size: 16),
                        label: const Text('Reject',
                            style: TextStyle(
                                color: Color(0xFFD9534F),
                                fontWeight: FontWeight.w700)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFD9534F)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      )),
                      const SizedBox(width: 12),
                      Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: () => _approve(inv['id'], paymentId),
                            icon: const Icon(Icons.check_rounded,
                                color: Colors.white, size: 16),
                            label: const Text('Approve Payment',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700)),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2E8B57),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12)),
                          )),
                    ]),
                  ])),
            ]),
          );
        },
      ),
    );
  }

  Widget _buildVerifiedTab() {
    if (_verified.isEmpty) {
      return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.receipt_long_rounded,
            color: _brown.withValues(alpha: 0.3), size: 48),
        const SizedBox(height: 16),
        const Text('No verified payments yet',
            style: TextStyle(
                color: _textPri, fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        const Text('Approved payments will appear here.',
            style: TextStyle(color: _textMuted, fontSize: 13)),
      ]));
    }
    return RefreshIndicator(
      color: _brown,
      backgroundColor: _bgCard,
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _verified.length,
        itemBuilder: (_, i) {
          final p = _verified[i];
          final amount = ((p['amount'] ?? 0.0) as num).toDouble();
          final refunded = (p['refund_status'] ?? '') == 'refunded';
          final refundedAmount = ((p['refunded_amount'] ?? 0.0) as num).toDouble();
          final paymentId = p['id'].toString();
          final busy = _refunding.contains(paymentId);

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: _bgCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: (refunded ? const Color(0xFFD9534F) : const Color(0xFF2E8B57))
                        .withValues(alpha: 0.25))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(
                          (p['invoice_number'] ?? '').toString().isNotEmpty
                              ? p['invoice_number']
                              : 'Payment',
                          style: const TextStyle(
                              color: _textPri,
                              fontWeight: FontWeight.w700,
                              fontSize: 15)),
                      Text((p['client_name'] ?? 'Client').toString(),
                          style: const TextStyle(
                              color: _brownLight, fontSize: 12)),
                    ])),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: (refunded
                              ? const Color(0xFFD9534F)
                              : const Color(0xFF2E8B57))
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10)),
                  child: Text(refunded ? 'REFUNDED' : 'VERIFIED',
                      style: TextStyle(
                          color: refunded
                              ? const Color(0xFFD9534F)
                              : const Color(0xFF2E8B57),
                          fontSize: 10,
                          fontWeight: FontWeight.w800)),
                ),
              ]),
              const SizedBox(height: 10),
              _InfoRow('Amount', '₹${amount.toStringAsFixed(2)}', _brown),
              if (refunded) ...[
                const SizedBox(height: 8),
                _InfoRow('Refunded', '₹${refundedAmount.toStringAsFixed(2)}',
                    const Color(0xFFD9534F)),
              ],
              const SizedBox(height: 14),
              if (!refunded)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : () => _payBack(p),
                    icon: busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Color(0xFFD9534F)))
                        : const Icon(Icons.replay_rounded,
                            color: Color(0xFFD9534F), size: 16),
                    label: Text(busy ? 'Processing...' : 'Pay Back',
                        style: const TextStyle(
                            color: Color(0xFFD9534F),
                            fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFD9534F)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
            ]),
          );
        },
      ),
    );
  }

  Widget _InfoRow(String label, String value, Color color) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: _textMuted, fontSize: 13)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.right,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w600, fontSize: 13)),
          ),
        ],
      );
}
