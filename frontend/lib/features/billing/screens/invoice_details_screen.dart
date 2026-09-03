import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/dio_client.dart';

class InvoiceDetailsScreen extends StatefulWidget {
  final String invoiceId;
  const InvoiceDetailsScreen({super.key, required this.invoiceId});
  @override
  State<InvoiceDetailsScreen> createState() => _InvoiceDetailsScreenState();
}

class _InvoiceDetailsScreenState extends State<InvoiceDetailsScreen> {
  Map<String, dynamic>? _invoice;
  bool _loading = true;

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
                    if (inv['status'] == 'unpaid' ||
                        inv['status'] == 'partial') ...[
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            final pending = _amount(inv['total_amount']) -
                                _amount(inv['paid_amount']);
                            context.push(
                                '/billing/pay/${inv['id']}?amount=${pending.toStringAsFixed(2)}&invoice=${inv['invoice_number']}');
                          },
                          icon: const Icon(Icons.payment_rounded,
                              color: AppColors.primary, size: 20),
                          label: const Text('Pay Now',
                              style: TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.gold,
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
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
