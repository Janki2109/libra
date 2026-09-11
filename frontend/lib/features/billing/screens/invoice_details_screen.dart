import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/dio_client.dart';
import '../../../core/utils/file_opener.dart';

class InvoiceDetailsScreen extends StatefulWidget {
  final String invoiceId;
  const InvoiceDetailsScreen({super.key, required this.invoiceId});
  @override
  State<InvoiceDetailsScreen> createState() => _InvoiceDetailsScreenState();
}

class _InvoiceDetailsScreenState extends State<InvoiceDetailsScreen> {
  Map<String, dynamic>? _invoice;
  bool _loading = true;
  bool _printing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // The API path is /invoices/:id. '/billing/...' is the app's own route
      // name, and calling it as an endpoint 404'd every time — this screen
      // could never load an invoice.
      final res =
          await DioClient.instance.get('/invoices/${widget.invoiceId}');
      setState(() {
        _invoice = res.data['data'];
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  /// Opens the client's uploaded proof (a data: URI, the same inline-storage
  /// trick documents/avatars already use). This row previously just sat
  /// there as inert text — nothing let a lawyer actually see what the
  /// client submitted.
  Future<void> _viewPaymentProof(String slipUrl) async {
    if (!slipUrl.startsWith('data:')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('This proof was submitted as a link; opening links '
              'from here is not supported — ask the client to re-upload.'),
          backgroundColor: AppColors.error));
      return;
    }
    try {
      final commaIndex = slipUrl.indexOf(',');
      final mimeType = slipUrl.substring(5, commaIndex).split(';').first;
      final bytes = base64Decode(slipUrl.substring(commaIndex + 1));
      final ext = mimeType.contains('pdf') ? 'pdf' : 'jpg';
      final result = await openDocumentBytes(
          bytes: bytes, fileName: 'payment_proof.$ext', mimeType: mimeType);
      if (!result.success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(result.message ?? 'Could not open payment proof.'),
            backgroundColor: AppColors.error));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not open payment proof.'),
            backgroundColor: AppColors.error));
      }
    }
  }

  // "Bill print" didn't exist anywhere in the app before this — the backend
  // renders the invoice as a real PDF, and this opens it in the device's own
  // PDF viewer, which has its own Print action already — no need for a
  // separate print package/dialog to get a physical or PDF printout.
  Future<void> _printInvoice() async {
    if (_printing) return;
    setState(() => _printing = true);
    try {
      final res = await DioClient.instance
          .get('/invoices/${widget.invoiceId}/pdf');
      final data = res.data['data'];
      final b64 = data?['file_base64'] as String?;
      final fileName = data?['file_name'] as String? ?? 'invoice.pdf';
      if (b64 == null) throw Exception('The server did not return a file');
      final bytes = base64Decode(b64);
      final result = await openDocumentBytes(
          bytes: bytes, fileName: fileName, mimeType: 'application/pdf');
      if (!mounted) return;
      if (!result.success) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(result.message ?? 'Could not open the invoice PDF.'),
            backgroundColor: AppColors.error));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Could not generate the invoice PDF: ${DioClient.describeError(e)}'),
            backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inv = _invoice;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.primaryDark,
        title: const Text('Invoice Details',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700)),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => context.pop()),
        actions: [
          if (_invoice != null)
            IconButton(
              icon: _printing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.print_rounded, color: Colors.white),
              tooltip: 'Print / Download PDF',
              onPressed: _printing ? null : _printInvoice,
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold))
          : inv == null
              ? const Center(
                  child: Text('Invoice not found',
                      style: TextStyle(color: AppColors.textMuted)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: AppColors.goldGradient,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(inv['invoice_number'] ?? '',
                                  style: const TextStyle(
                                      color: AppColors.primary,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800)),
                              if ((inv['client_name'] ?? '').toString().isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(inv['client_name'],
                                    style: const TextStyle(
                                        color: AppColors.primaryDark,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600)),
                              ],
                              const SizedBox(height: 4),
                              Text(
                                  'Issued: ${_safe(inv['issue_date'])}',
                                  style: const TextStyle(
                                      color: AppColors.primaryDark,
                                      fontSize: 12)),
                              if ((inv['due_date'] ?? '').isNotEmpty)
                                Text('Due: ${_safe(inv['due_date'])}',
                                    style: const TextStyle(
                                        color: AppColors.primaryDark,
                                        fontSize: 12)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                              (inv['status'] ?? '').toString().toUpperCase(),
                              style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13)),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    _Card(children: [
                      _AmountRow('Service Amount',
                          '₹${_amount(inv['subtotal'])}',
                          AppColors.textSecondary),
                      _AmountRow(
                          'GST (${_amount(inv['gst_rate']).toStringAsFixed(0)}%)',
                          '₹${_amount(inv['gst_amount'])}',
                          AppColors.textSecondary),
                      _AmountRow('Platform Fee',
                          '₹${_amount(inv['platform_fee'])}',
                          AppColors.textSecondary),
                      const Divider(color: AppColors.border),
                      _AmountRow('Total Payable',
                          '₹${_amount(inv['total_amount'])}',
                          AppColors.textPrimary),
                      const Divider(color: AppColors.border),
                      _AmountRow('Amount Paid',
                          '₹${_amount(inv['paid_amount'])}',
                          AppColors.success),
                      _AmountRow('Pending',
                          '₹${(_amount(inv['total_amount']) - _amount(inv['paid_amount'])).toStringAsFixed(2)}',
                          inv['status'] == 'paid'
                              ? AppColors.textMuted
                              : AppColors.error),
                    ]),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: AppColors.gold.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10)),
                      child: const Row(children: [
                        Icon(Icons.info_outline_rounded,
                            color: AppColors.gold, size: 14),
                        SizedBox(width: 6),
                        Expanded(
                            child: Text(
                                '18% GST and ₹100 platform fee are mandatory charges.',
                                style: TextStyle(
                                    color: AppColors.gold, fontSize: 11))),
                      ]),
                    ),
                    if ((inv['description'] ?? '').isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _Card(children: [
                        const Text('Description',
                            style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Text(inv['description'],
                            style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13)),
                      ]),
                    ],
                    // "Pay Now" is a Client-only action — a Lawyer never pays
                    // their own invoice, they verify what the client already
                    // paid. In its place: the transaction id and the actual
                    // uploaded payment proof, when the client has submitted
                    // one (already returned by GetInvoice, just never shown
                    // here before).
                    if ((inv['transaction_id'] ?? '').toString().isNotEmpty ||
                        (inv['payment_slip_url'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _Card(children: [
                        if ((inv['transaction_id'] ?? '').toString().isNotEmpty)
                          _AmountRow('Transaction ID', inv['transaction_id'],
                              AppColors.textSecondary),
                        if ((inv['payment_slip_url'] ?? '').toString().isNotEmpty) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => _viewPaymentProof(
                                  inv['payment_slip_url'].toString()),
                              icon: const Icon(Icons.receipt_long_rounded,
                                  color: AppColors.gold, size: 18),
                              label: const Text('View Payment Proof',
                                  style: TextStyle(
                                      color: AppColors.gold,
                                      fontWeight: FontWeight.w700)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppColors.gold),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ]),
                    ],
                  ]),
                ),
    );
  }

  double _amount(dynamic v) => (v ?? 0).toDouble();
  String _safe(dynamic v) {
    final s = v?.toString() ?? '';
    return s.length >= 10 ? s.substring(0, 10) : s;
  }
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );
}

class _AmountRow extends StatelessWidget {
  final String label, value;
  final Color color;
  const _AmountRow(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.textMuted, fontSize: 13)),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 15)),
        ]),
      );
}
