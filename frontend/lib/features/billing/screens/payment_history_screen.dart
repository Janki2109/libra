import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/dio_client.dart';
import '../../lawyer/utils/android_download.dart';
import '../../../core/utils/file_opener.dart';

class PaymentHistoryScreen extends StatefulWidget {
  const PaymentHistoryScreen({super.key});
  @override
  State<PaymentHistoryScreen> createState() => _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends State<PaymentHistoryScreen> {
  List<dynamic> _payments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // /billing/payments is not an API path — see invoice_details_screen.
      final res = await DioClient.instance.get('/payments');
      setState(() {
        _payments = res.data['data'] ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.primaryDark,
        title: const Text('Payment History',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700)),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => context.pop()),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold))
          : _payments.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.receipt_long_rounded,
                          color: AppColors.textMuted, size: 64),
                      SizedBox(height: 16),
                      Text('No Payments Yet',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 16)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: AppColors.gold,
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _payments.length,
                    itemBuilder: (_, i) {
                      final p = _payments[i];
                      final amount =
                          (p['amount'] ?? 0).toDouble();
                      final method =
                          (p['payment_method'] ?? 'manual').toString();
                      final status =
                          (p['verification_status'] ?? 'success').toString();
                      final clientName = (p['client_name'] ?? '').toString();
                      final invoiceNumber =
                          (p['invoice_number'] ?? '').toString();
                      final txnId = (p['transaction_id'] ?? '').toString();
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.bgCard,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              gradient: AppColors.successGradient,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.check_circle_outline_rounded,
                                color: Colors.white, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('₹${amount.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                        color: AppColors.success,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16)),
                                if (clientName.isNotEmpty)
                                  Text(
                                      invoiceNumber.isNotEmpty
                                          ? '$clientName • $invoiceNumber'
                                          : clientName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600)),
                                Text(
                                    '${_methodLabel(method)} • ${_safe(p['payment_date'])}',
                                    style: const TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 11)),
                                if (txnId.isNotEmpty)
                                  Text('Txn: $txnId',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 10)),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.success.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(status.toUpperCase(),
                                    style: const TextStyle(
                                        color: AppColors.success,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700)),
                              ),
                              const SizedBox(height: 6),
                              GestureDetector(
                                onTap: () => _downloadReceipt(
                                    (p['id'] ?? '').toString()),
                                child: const Icon(Icons.download_rounded,
                                    color: AppColors.gold, size: 20),
                              ),
                            ],
                          ),
                        ]),
                      );
                    },
                  ),
                ),
    );
  }

  Future<void> _downloadReceipt(String paymentId) async {
    if (paymentId.isEmpty) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
          child: CircularProgressIndicator(color: AppColors.gold)),
    );
    try {
      final res =
          await DioClient.instance.get('/payments/$paymentId/receipt');
      final data = res.data['data'] as Map<String, dynamic>?;
      final b64 = (data?['file_base64'] ?? '').toString();
      final fileName = (data?['file_name'] ?? 'receipt.pdf').toString();
      if (mounted) Navigator.pop(context);
      if (b64.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Receipt has no content to download'),
              backgroundColor: AppColors.error));
        }
        return;
      }
      final bytes = base64Decode(b64);
      if (await saveToAndroidDownloads(bytes, fileName, 'application/pdf')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('$fileName saved to Downloads'),
              backgroundColor: AppColors.success));
        }
        return;
      }
      final result = await openDocumentBytes(
          bytes: bytes, fileName: fileName, mimeType: 'application/pdf');
      if (!result.success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(result.message ?? 'Could not open the receipt'),
            backgroundColor: AppColors.error));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Could not download receipt: $e'),
            backgroundColor: AppColors.error));
      }
    }
  }

  String _methodLabel(String m) {
    switch (m) {
      case 'razorpay': return 'Razorpay';
      case 'upi': return 'UPI';
      case 'cash': return 'Cash';
      case 'bank_transfer': return 'Bank Transfer';
      case 'consultation': return 'Consultation';
      case 'manual_test': return 'Invoice Payment';
      default: return m;
    }
  }

  String _safe(dynamic v) {
    final s = v?.toString() ?? '';
    return s.length >= 10 ? s.substring(0, 10) : s;
  }
}
