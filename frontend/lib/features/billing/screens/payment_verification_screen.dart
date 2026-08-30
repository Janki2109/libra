import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/services/dio_client.dart';

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

class _PaymentVerificationScreenState extends State<PaymentVerificationScreen> {
  List<dynamic> _pending = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res =
          await DioClient.instance.get('/invoices/pending-verification');
      setState(() {
        _pending = res.data['data'] ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _approve(String invoiceId, String paymentId) async {
    try {
      await DioClient.instance
          .put('/invoices/$invoiceId', data: {'status': 'paid'});
      await DioClient.instance
          .put('/payments/$paymentId/verify', data: {'status': 'approved'});
      HapticFeedback.heavyImpact();
      _load();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Payment approved! Invoice marked as PAID'),
          backgroundColor: Color(0xFF2E8B57),
          behavior: SnackBarBehavior.floating,
        ));
    } catch (e) {
      debugPrint('Approve error: $e');
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
                child: Padding(
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
                )),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _brown))
                : _pending.isEmpty
                    ? Center(
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                            Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                    color: const Color(0xFF2E8B57)
                                        .withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: const Color(0xFF2E8B57)
                                            .withValues(alpha: 0.3))),
                                child: const Icon(Icons.check_circle_rounded,
                                    color: Color(0xFF2E8B57), size: 44)),
                            const SizedBox(height: 16),
                            const Text('All caught up! ✅',
                                style: TextStyle(
                                    color: _textPri,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            const Text('No pending payment verifications',
                                style: TextStyle(color: _textMuted)),
                          ]))
                    : RefreshIndicator(
                        color: _brown,
                        backgroundColor: _bgCard,
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _pending.length,
                          itemBuilder: (_, i) {
                            final inv = _pending[i];
                            final amount = ((inv['total_amount'] ?? 0.0) as num)
                                .toDouble();
                            final txnId = inv['transaction_id'] ?? '';
                            final slipUrl = inv['payment_slip_url'] ?? '';
                            final paymentId = inv['payment_id'] ?? '';

                            return Container(
                              margin: const EdgeInsets.only(bottom: 14),
                              decoration: BoxDecoration(
                                  color: _bgCard,
                                  borderRadius: BorderRadius.circular(16),
                                  border:
                                      Border.all(color: _gold.withValues(alpha: 0.3)),
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
                                    borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(16)),
                                  ),
                                  child: Row(children: [
                                    Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                            color: _gold.withValues(alpha: 0.12),
                                            borderRadius:
                                                BorderRadius.circular(12)),
                                        child: const Icon(Icons.pending_rounded,
                                            color: _gold, size: 22)),
                                    const SizedBox(width: 12),
                                    Expanded(
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                          Text(inv['invoice_number'] ?? '',
                                              style: const TextStyle(
                                                  color: _textPri,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 15)),
                                          Text(inv['client_name'] ?? 'Client',
                                              style: const TextStyle(
                                                  color: _brownLight,
                                                  fontSize: 12)),
                                        ])),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                          color: _gold.withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          border: Border.all(
                                              color: _gold.withValues(alpha: 0.4))),
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
                                      _InfoRow(
                                          'Amount',
                                          '₹${amount.toStringAsFixed(2)}',
                                          _brown),
                                      const SizedBox(height: 8),
                                      _InfoRow(
                                          'Transaction ID',
                                          txnId.isNotEmpty
                                              ? txnId
                                              : 'Not provided',
                                          txnId.isNotEmpty
                                              ? _textPri
                                              : const Color(0xFFD9534F)),
                                      if (slipUrl.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        _InfoRow('Payment Slip', 'View slip →',
                                            const Color(0xFF4A90D9)),
                                      ],
                                      const SizedBox(height: 14),
                                      Row(children: [
                                        Expanded(
                                            child: OutlinedButton.icon(
                                          onPressed: () =>
                                              _reject(inv['id'], paymentId),
                                          icon: const Icon(Icons.close_rounded,
                                              color: Color(0xFFD9534F),
                                              size: 16),
                                          label: const Text('Reject',
                                              style: TextStyle(
                                                  color: Color(0xFFD9534F),
                                                  fontWeight: FontWeight.w700)),
                                          style: OutlinedButton.styleFrom(
                                            side: const BorderSide(
                                                color: Color(0xFFD9534F)),
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12)),
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 12),
                                          ),
                                        )),
                                        const SizedBox(width: 12),
                                        Expanded(
                                            flex: 2,
                                            child: ElevatedButton.icon(
                                              onPressed: () => _approve(
                                                  inv['id'], paymentId),
                                              icon: const Icon(
                                                  Icons.check_rounded,
                                                  color: Colors.white,
                                                  size: 16),
                                              label: const Text(
                                                  'Approve Payment',
                                                  style: TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.w700)),
                                              style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      const Color(0xFF2E8B57),
                                                  shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12)),
                                                  padding: const EdgeInsets
                                                      .symmetric(vertical: 12)),
                                            )),
                                      ]),
                                    ])),
                              ]),
                            );
                          },
                        ),
                      ),
          ),
        ]),
      ),
    );
  }

  Widget _InfoRow(String label, String value, Color color) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: _textMuted, fontSize: 13)),
          Text(value,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      );
}
