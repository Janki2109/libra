import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/portal_provider.dart';

const _bg = Color(0xFFF0FAF6);
const _bgCard = Color(0xFFFFFFFF);
const _green = Color(0xFF0D6E4F);
const _border = Color(0xFFB2DFD0);
const _textPri = Color(0xFF0A2E1F);
const _textMuted = Color(0xFF4A7A63);

class PortalInvoicesScreen extends StatefulWidget {
  const PortalInvoicesScreen({super.key});
  @override
  State<PortalInvoicesScreen> createState() => _PortalInvoicesScreenState();
}

class _PortalInvoicesScreenState extends State<PortalInvoicesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.read<PortalProvider>().refreshInvoices());
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'paid':
        return const Color(0xFF2E8B57);
      case 'partial':
        return const Color(0xFFD4A017);
      case 'overdue':
        return const Color(0xFFD9534F);
      case 'cancelled':
        return _textMuted;
      default:
        return _green;
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PortalProvider>();
    final invoices = provider.invoices;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light),
      child: Scaffold(
        backgroundColor: _bg,
        body: Column(children: [
          // Green header
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0A4A32), Color(0xFF0D6E4F)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
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
                        child: Text('My Invoices',
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
            child: provider.loading
                ? const Center(child: CircularProgressIndicator(color: _green))
                : invoices.isEmpty
                    ? Center(
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                            Icon(Icons.receipt_long_rounded,
                                color: _green.withValues(alpha: 0.3), size: 64),
                            const SizedBox(height: 16),
                            const Text('No Invoices Yet',
                                style: TextStyle(
                                    color: _textPri,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            const Text(
                                'Invoices from your lawyer will appear here.',
                                style:
                                    TextStyle(color: _textMuted, fontSize: 13)),
                          ]))
                    : RefreshIndicator(
                        color: _green,
                        backgroundColor: _bgCard,
                        onRefresh: () => provider.refreshInvoices(),
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: invoices.length,
                          itemBuilder: (_, i) {
                            final inv = invoices[i];
                            final status = inv['status'] ?? 'unpaid';
                            final total = (inv['total_amount'] ?? 0).toDouble();
                            final paid = (inv['paid_amount'] ?? 0).toDouble();
                            final pending = total - paid;
                            final isPendingPayment =
                                status == 'unpaid' || status == 'partial';
                            final sc = _statusColor(status);

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: _bgCard,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                    color: isPendingPayment
                                        ? _green.withValues(alpha: 0.3)
                                        : _border,
                                    width: 0.8),
                                boxShadow: [
                                  BoxShadow(
                                      color: _green.withValues(alpha: 0.06),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2))
                                ],
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(children: [
                                  Row(children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                          color: (isPendingPayment
                                                  ? _green
                                                  : const Color(0xFF2E8B57))
                                              .withValues(alpha: 0.1),
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                      child: Icon(
                                          isPendingPayment
                                              ? Icons.receipt_long_rounded
                                              : Icons.check_circle_rounded,
                                          color: isPendingPayment
                                              ? _green
                                              : const Color(0xFF2E8B57),
                                          size: 22),
                                    ),
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
                                                  fontSize: 14)),
                                          Text(
                                            'Issued: ${(inv['issue_date'] ?? '').toString().length >= 10 ? (inv['issue_date'] ?? '').toString().substring(0, 10) : ''}',
                                            style: const TextStyle(
                                                color: _textMuted,
                                                fontSize: 11),
                                          ),
                                        ])),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                          color: sc.withValues(alpha: 0.1),
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                      child: Text(status.toUpperCase(),
                                          style: TextStyle(
                                              color: sc,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700)),
                                    ),
                                  ]),
                                  const SizedBox(height: 14),
                                  Divider(
                                      color: _border,
                                      height: 1,
                                      thickness: 0.6),
                                  const SizedBox(height: 14),
                                  Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        _AmountCol(
                                            'Total',
                                            '₹${total.toStringAsFixed(0)}',
                                            _textPri),
                                        _AmountCol(
                                            'Paid',
                                            '₹${paid.toStringAsFixed(0)}',
                                            const Color(0xFF2E8B57)),
                                        _AmountCol(
                                            'Pending',
                                            '₹${pending.toStringAsFixed(0)}',
                                            isPendingPayment
                                                ? const Color(0xFFD9534F)
                                                : _textMuted),
                                      ]),
                                  if ((inv['gst_amount'] ?? 0) > 0 ||
                                      (inv['platform_fee'] ?? 0) > 0) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                        'Incl. GST (${(inv['gst_rate'] ?? 18).toStringAsFixed(0)}%): ₹${(inv['gst_amount'] ?? 0).toStringAsFixed(0)} '
                                        '+ Platform Fee: ₹${(inv['platform_fee'] ?? 0).toStringAsFixed(0)}',
                                        style: const TextStyle(
                                            color: _textMuted, fontSize: 10.5)),
                                  ],
                                  if (isPendingPayment) ...[
                                    const SizedBox(height: 14),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: () => context
                                            .push(
                                                '/billing/pay/${inv['id']}?amount=${pending.toStringAsFixed(2)}&invoice=${inv['invoice_number']}')
                                            .then((_) => context
                                                .read<PortalProvider>()
                                                .refreshInvoices()),
                                        icon: const Icon(Icons.payment_rounded,
                                            size: 18, color: Colors.white),
                                        label: const Text('Pay Now',
                                            style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: _green,
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 10),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10)),
                                        ),
                                      ),
                                    ),
                                  ],
                                ]),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ]),
      ),
    );
  }
}

class _AmountCol extends StatelessWidget {
  final String label, value;
  final Color color;
  const _AmountCol(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(label, style: const TextStyle(color: _textMuted, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w700, fontSize: 15)),
      ]);
}
