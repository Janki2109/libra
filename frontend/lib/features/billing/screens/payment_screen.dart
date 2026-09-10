import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/dio_client.dart';

const _bg = Color(0xFFF0FAF6);
const _bgCard = Color(0xFFFFFFFF);
const _green = Color(0xFF0D6E4F);
const _greenLight = Color(0xFF1A9E72);
const _border = Color(0xFFB2DFD0);
const _textPri = Color(0xFF0A2E1F);
const _textMuted = Color(0xFF4A7A63);

class PaymentScreen extends StatefulWidget {
  final String invoiceId;
  final double amount;
  final String invoiceNumber;
  const PaymentScreen(
      {super.key,
      required this.invoiceId,
      required this.amount,
      required this.invoiceNumber});
  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  bool _loading = false;
  bool _loadingDetails = true;
  String _upiId = '',
      _accountName = '',
      _accountNumber = '',
      _ifsc = '',
      _bankName = '';
  double _subtotal = 0, _gstRate = 18, _gstAmount = 0, _platformFee = 100;
  final _transactionIdCtrl = TextEditingController();

  // Payment proof — a real uploaded file, not a pasted URL. Encoded the same
  // way documents/avatars already are (a data: URI in payment_slip_url,
  // still a plain TEXT column — no schema change needed) rather than typed
  // in by hand.
  Uint8List? _proofBytes;
  String _proofFileName = '';
  String _proofMimeType = '';
  bool _pickingProof = false;

  @override
  void initState() {
    super.initState();
    _loadInvoiceDetails();
  }

  @override
  void dispose() {
    _transactionIdCtrl.dispose();
    super.dispose();
  }

  static const Map<String, String> _proofExtToMime = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'pdf': 'application/pdf',
  };

  Future<void> _pickPaymentProof(void Function(void Function()) setDialogState) async {
    setDialogState(() => _pickingProof = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
        withData: true,
      );
      final file = result?.files.single;
      if (file?.bytes == null) {
        setDialogState(() => _pickingProof = false);
        return;
      }
      final ext = (file!.extension ?? '').toLowerCase();
      final mime = _proofExtToMime[ext];
      if (mime == null) {
        setDialogState(() => _pickingProof = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Please choose an image or PDF file.'),
              backgroundColor: Color(0xFFD9534F)));
        }
        return;
      }
      if (file.bytes!.length > 6 * 1024 * 1024) {
        setDialogState(() => _pickingProof = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('File is too large — please pick one under 6MB.'),
              backgroundColor: Color(0xFFD9534F)));
        }
        return;
      }
      setDialogState(() {
        _proofBytes = file.bytes;
        _proofFileName = file.name;
        _proofMimeType = mime;
        _pickingProof = false;
      });
    } catch (_) {
      setDialogState(() => _pickingProof = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not access the file picker.'),
            backgroundColor: Color(0xFFD9534F)));
      }
    }
  }

  Future<void> _loadInvoiceDetails() async {
    try {
      // /portal/my-invoices/:id, not the firm-staff-only /invoices/:id — a
      // client account never passes RequireFirmStaff, so the old call here
      // silently 403'd on every load and this screen never actually showed
      // bank details (or, now, the GST/platform-fee breakdown) to a client.
      final res =
          await DioClient.instance.get('/portal/my-invoices/${widget.invoiceId}');
      final data = res.data['data'] ?? {};
      setState(() {
        _upiId = data['upi_id'] ?? '';
        _accountName = data['bank_account_name'] ?? '';
        _accountNumber = data['bank_account_number'] ?? '';
        _ifsc = data['bank_ifsc'] ?? '';
        _bankName = data['bank_name'] ?? '';
        _subtotal = (data['subtotal'] ?? 0).toDouble();
        _gstRate = (data['gst_rate'] ?? 18).toDouble();
        _gstAmount = (data['gst_amount'] ?? 0).toDouble();
        _platformFee = (data['platform_fee'] ?? 100).toDouble();
        _loadingDetails = false;
      });
    } catch (e) {
      setState(() => _loadingDetails = false);
    }
  }

  String _getUpiUrl({String? app}) {
    final upiId = _upiId.isNotEmpty ? _upiId : 'lawyer@upi';
    final amount = widget.amount.toStringAsFixed(2);
    final note = Uri.encodeComponent('Payment for ${widget.invoiceNumber}');
    final name = Uri.encodeComponent(
        _accountName.isNotEmpty ? _accountName : 'Libra Law');
    switch (app) {
      case 'gpay':
        return 'tez://upi/pay?pa=$upiId&pn=$name&am=$amount&cu=INR&tn=$note';
      case 'phonepe':
        return 'phonepe://pay?pa=$upiId&pn=$name&am=$amount&cu=INR&tn=$note';
      case 'paytm':
        return 'paytmmp://pay?pa=$upiId&pn=$name&am=$amount&cu=INR&tn=$note';
      case 'bhim':
        return 'bhim://pay?pa=$upiId&pn=$name&am=$amount&cu=INR&tn=$note';
      default:
        return 'upi://pay?pa=$upiId&pn=$name&am=$amount&cu=INR&tn=$note';
    }
  }

  Future<void> _launchUPI(String app, String appName) async {
    try {
      final url = _getUpiUrl(app: app);
      const platform = MethodChannel('com.libra.law/upi');
      await platform.invokeMethod('launchUrl', {'url': url});
    } catch (_) {}
    if (mounted) _showPaymentProofDialog(appName);
  }

  void _showPaymentProofDialog(String method) {
    _transactionIdCtrl.clear();
    setState(() {
      _proofBytes = null;
      _proofFileName = '';
      _proofMimeType = '';
    });
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => StatefulBuilder(
              builder: (ctx, setS) => AlertDialog(
                backgroundColor: _bgCard,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                title: Column(children: [
                  Container(
                      width: 60,
                      height: 60,
                      decoration:
                          BoxDecoration(color: _green, shape: BoxShape.circle),
                      child: const Icon(Icons.receipt_long_rounded,
                          color: Colors.white, size: 30)),
                  const SizedBox(height: 12),
                  const Text('Submit Payment Proof',
                      style: TextStyle(
                          color: _textPri,
                          fontWeight: FontWeight.w700,
                          fontSize: 18)),
                  const SizedBox(height: 4),
                  const Text(
                      'Enter your transaction details.\nYour lawyer will verify & confirm.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _textMuted, fontSize: 12)),
                ]),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  _inputField(_transactionIdCtrl,
                      'Transaction ID / UTR Number *', Icons.tag_rounded),
                  const SizedBox(height: 10),
                  // Upload Payment Proof — replaces a URL field the client
                  // had to paste a link into by hand. The actual file is
                  // read here and uploaded as part of Submit Proof below,
                  // the same inline-storage approach documents/avatars use.
                  if (_proofBytes == null)
                    OutlinedButton.icon(
                      onPressed: _pickingProof
                          ? null
                          : () => _pickPaymentProof(setS),
                      icon: _pickingProof
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: _green))
                          : const Icon(Icons.upload_file_rounded,
                              color: _green, size: 18),
                      label: Text(
                          _pickingProof
                              ? 'Selecting…'
                              : 'Upload Payment Proof (optional)',
                          style: const TextStyle(color: _green)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: _border),
                        minimumSize: const Size(double.infinity, 44),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                          color: _green.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: _green.withValues(alpha: 0.3))),
                      child: Row(children: [
                        const Icon(Icons.check_circle_rounded,
                            color: _green, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(_proofFileName,
                                style: const TextStyle(
                                    color: _textPri, fontSize: 12.5),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis)),
                        TextButton(
                          onPressed: () => _pickPaymentProof(setS),
                          child: const Text('Replace',
                              style: TextStyle(
                                  color: _green, fontWeight: FontWeight.w700)),
                        ),
                      ]),
                    ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: const Color(0xFFD4A017).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: const Color(0xFFD4A017).withValues(alpha: 0.3))),
                    child: const Row(children: [
                      Icon(Icons.info_outline_rounded,
                          color: Color(0xFFD4A017), size: 16),
                      SizedBox(width: 8),
                      Expanded(
                          child: Text(
                              'Payment will be marked as "Pending Verification" until your lawyer confirms.',
                              style: TextStyle(
                                  color: Color(0xFFD4A017),
                                  fontSize: 11,
                                  height: 1.4))),
                    ]),
                  ),
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel',
                          style: TextStyle(color: _textMuted))),
                  ElevatedButton(
                    onPressed: _loading
                        ? null
                        : () async {
                            if (_transactionIdCtrl.text.trim().isEmpty) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                      content:
                                          Text('Transaction ID is required!'),
                                      backgroundColor: Color(0xFFD9534F)));
                              return;
                            }
                            Navigator.pop(ctx);
                            await _submitPaymentProof(method);
                          },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: _green,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    child: const Text('Submit Proof',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ));
  }

  TextField _inputField(
          TextEditingController ctrl, String label, IconData icon) =>
      TextField(
        controller: ctrl,
        style: const TextStyle(color: _textPri, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: _textMuted, fontSize: 13),
          prefixIcon: Icon(icon, color: _green, size: 18),
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
              borderSide: const BorderSide(color: _green, width: 1.5)),
        ),
      );

  Future<void> _submitPaymentProof(String method) async {
    setState(() => _loading = true);
    try {
      // A single call now does everything: records the payment claim, moves
      // the invoice into the lawyer's Payment Verification queue, and stores
      // the transaction id/slip URL on the invoice. This used to be a second
      // PUT /invoices/:id call, which is a firm-staff-only route — a client
      // calling it always got a 403, so the invoice never actually reached
      // the verification queue and the slip URL was silently lost, even
      // though this screen still told the client their payment was
      // submitted.
      await DioClient.instance.post('/payments', data: {
        'invoice_id': widget.invoiceId,
        'amount': widget.amount,
        'payment_date': DateTime.now().toIso8601String().substring(0, 10),
        'payment_method': method,
        'transaction_id': _transactionIdCtrl.text.trim(),
        'payment_slip_url': _proofBytes != null
            ? 'data:$_proofMimeType;base64,${base64Encode(_proofBytes!)}'
            : '',
        'notes': 'Paid via $method | TXN: ${_transactionIdCtrl.text.trim()}',
      });
      if (mounted) {
        setState(() => _loading = false);
        HapticFeedback.heavyImpact();
        _showPendingScreen();
      }
    } catch (e) {
      setState(() => _loading = false);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(DioClient.describeError(e)),
            backgroundColor: const Color(0xFFD9534F)));
    }
  }

  void _showPendingScreen() {
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
                        color: _green.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: _green.withValues(alpha: 0.4), width: 2)),
                    child:
                        Icon(Icons.pending_rounded, color: _green, size: 44)),
                const SizedBox(height: 16),
                const Text('Payment Submitted! ⏳',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: _textPri,
                        fontSize: 20,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text('₹${widget.amount.toStringAsFixed(2)}',
                    style: const TextStyle(
                        color: _green,
                        fontSize: 30,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: _green.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _border)),
                  child: Column(children: [
                    _StatusRow(Icons.pending_rounded,
                        'Awaiting lawyer verification', _green),
                    const SizedBox(height: 8),
                    _StatusRow(
                        Icons.receipt_rounded,
                        'TXN: ${_transactionIdCtrl.text.trim()}',
                        const Color(0xFFD4A017)),
                    const SizedBox(height: 8),
                    _StatusRow(Icons.notifications_rounded,
                        'Lawyer notified of your payment', _greenLight),
                  ]),
                ),
                const SizedBox(height: 12),
                const Text(
                    'Your invoice will be marked as PAID once your lawyer verifies the transaction.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: _textMuted, fontSize: 12, height: 1.5)),
              ]),
              actions: [
                SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        context.pop();
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _green,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12))),
                      child: const Text('OK, Got it!',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16)),
                    )),
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
                  colors: [Color(0xFF0A4A32), Color(0xFF0D6E4F)],
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
                        child: Text('Pay Invoice',
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
              child: _loadingDetails
                  ? const Center(
                      child: CircularProgressIndicator(color: _green))
                  : ListView(padding: const EdgeInsets.all(16), children: [
                      // Amount card
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [Color(0xFF0A4A32), Color(0xFF1A9E72)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                                color: _green.withValues(alpha: 0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 8))
                          ],
                        ),
                        child: Column(children: [
                          const Text('Amount to Pay',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 13)),
                          const SizedBox(height: 8),
                          Text('₹${widget.amount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 42,
                                  fontWeight: FontWeight.w900)),
                          const SizedBox(height: 4),
                          Text(widget.invoiceNumber,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 13)),
                          if (_accountName.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text('Pay to: $_accountName',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ]),
                      ),
                      const SizedBox(height: 16),

                      // Amount breakdown — the client must always see the
                      // full base + GST + platform-fee breakdown, never just
                      // a single total.
                      if (_subtotal > 0)
                        Container(
                          padding: const EdgeInsets.all(16),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                              color: _bgCard,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: _border, width: 0.8)),
                          child: Column(children: [
                            _BreakdownRow(
                                'Service Amount', _subtotal, _textPri),
                            _BreakdownRow(
                                'GST (${_gstRate.toStringAsFixed(0)}%)',
                                _gstAmount,
                                _textMuted),
                            _BreakdownRow(
                                'Platform Fee', _platformFee, _textMuted),
                            Divider(color: _border, height: 20),
                            _BreakdownRow(
                                'Total Payable', widget.amount, _green,
                                bold: true),
                          ]),
                        ),

                      // How it works
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            color: _green.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _border, width: 0.8)),
                        child: Column(children: [
                          const Row(children: [
                            Icon(Icons.info_outline_rounded,
                                color: _green, size: 16),
                            SizedBox(width: 8),
                            Text('How Payment Works',
                                style: TextStyle(
                                    color: _green,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                          ]),
                          const SizedBox(height: 8),
                          _StepRow('1', 'Pay via UPI or Bank Transfer'),
                          _StepRow('2', 'Enter your Transaction ID (UTR)'),
                          _StepRow('3', 'Lawyer verifies & confirms'),
                          _StepRow('4', 'Invoice marked as PAID ✅'),
                        ]),
                      ),
                      const SizedBox(height: 16),

                      // Bank details
                      if (_upiId.isNotEmpty || _accountNumber.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(16),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                              color: _bgCard,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: _border, width: 0.8),
                              boxShadow: [
                                BoxShadow(
                                    color: _green.withValues(alpha: 0.05),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2))
                              ]),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(children: [
                                  Icon(Icons.account_balance_rounded,
                                      color: _green, size: 18),
                                  SizedBox(width: 8),
                                  Text('Payment Details',
                                      style: TextStyle(
                                          color: _green,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14)),
                                ]),
                                const SizedBox(height: 12),
                                if (_upiId.isNotEmpty)
                                  _DetailTile(context, 'UPI ID', _upiId,
                                      copyable: true),
                                if (_accountName.isNotEmpty)
                                  _DetailTile(
                                      context, 'Account Name', _accountName),
                                if (_accountNumber.isNotEmpty)
                                  _DetailTile(
                                      context, 'Account No', _accountNumber,
                                      copyable: true),
                                if (_ifsc.isNotEmpty)
                                  _DetailTile(context, 'IFSC', _ifsc,
                                      copyable: true),
                                if (_bankName.isNotEmpty)
                                  _DetailTile(context, 'Bank', _bankName),
                              ]),
                        ),

                      // UPI Apps
                      const Text('Pay with UPI',
                          style: TextStyle(
                              color: _textPri,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      Row(children: [
                        _UPIBtn(
                            'GPay',
                            Icons.g_mobiledata_rounded,
                            const Color(0xFF4285F4),
                            () => _launchUPI('gpay', 'GPay')),
                        const SizedBox(width: 10),
                        _UPIBtn(
                            'PhonePe',
                            Icons.phone_android_rounded,
                            const Color(0xFF5F259F),
                            () => _launchUPI('phonepe', 'PhonePe')),
                        const SizedBox(width: 10),
                        _UPIBtn(
                            'Paytm',
                            Icons.account_balance_wallet_rounded,
                            const Color(0xFF00B9F1),
                            () => _launchUPI('paytm', 'Paytm')),
                        const SizedBox(width: 10),
                        _UPIBtn(
                            'BHIM',
                            Icons.currency_rupee_rounded,
                            const Color(0xFF00A85A),
                            () => _launchUPI('bhim', 'BHIM')),
                      ]),
                      const SizedBox(height: 20),

                      // Other methods
                      const Text('Other Methods',
                          style: TextStyle(
                              color: _textPri,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      _MethodTile(
                          Icons.qr_code_rounded,
                          'UPI / QR Code',
                          _upiId.isNotEmpty ? 'UPI: $_upiId' : 'Any UPI app',
                          _green, () {
                        _showPaymentProofDialog('UPI');
                      }),
                      const SizedBox(height: 10),
                      _MethodTile(
                          Icons.account_balance_rounded,
                          'Bank Transfer',
                          _bankName.isNotEmpty
                              ? '$_bankName • $_accountNumber'
                              : 'NEFT/RTGS',
                          const Color(0xFF4A90D9), () {
                        _showPaymentProofDialog('Bank Transfer');
                      }),
                      const SizedBox(height: 40),
                    ])),
        ]),
      ),
    );
  }

  Widget _DetailTile(BuildContext context, String label, String value,
          {bool copyable = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          SizedBox(
              width: 90,
              child: Text(label,
                  style: const TextStyle(color: _textMuted, fontSize: 12))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      color: _textPri,
                      fontWeight: FontWeight.w600,
                      fontSize: 13))),
          if (copyable)
            GestureDetector(
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: value));
                if (mounted)
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Copied!'),
                      backgroundColor: Color(0xFF2E8B57)));
              },
              child: const Icon(Icons.copy_rounded, color: _green, size: 16),
            ),
        ]),
      );

  Widget _UPIBtn(String name, IconData icon, Color color, VoidCallback onTap) =>
      Expanded(
          child: GestureDetector(
        onTap: () {
          HapticFeedback.heavyImpact();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
              color: _bgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(
                    color: _green.withValues(alpha: 0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 2))
              ]),
          child: Column(children: [
            Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 20)),
            const SizedBox(height: 6),
            Text(name,
                style: TextStyle(
                    color: color, fontSize: 10, fontWeight: FontWeight.w700)),
          ]),
        ),
      ));

  Widget _MethodTile(IconData icon, String title, String subtitle, Color color,
          VoidCallback onTap) =>
      GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: _bgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _border, width: 0.8),
              boxShadow: [
                BoxShadow(
                    color: _green.withValues(alpha: 0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 2))
              ]),
          child: Row(children: [
            Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color, size: 22)),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title,
                      style: const TextStyle(
                          color: _textPri,
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                  Text(subtitle,
                      style: const TextStyle(color: _textMuted, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ])),
            Icon(Icons.arrow_forward_ios_rounded,
                color: color.withValues(alpha: 0.5), size: 16),
          ]),
        ),
      );
}

Widget _BreakdownRow(String label, double amount, Color color, {bool bold = false}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label,
            style: TextStyle(
                color: bold ? color : _textMuted,
                fontSize: bold ? 14 : 12,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
        Text('₹${amount.toStringAsFixed(2)}',
            style: TextStyle(
                color: color,
                fontSize: bold ? 16 : 13,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
      ]),
    );

Widget _StatusRow(IconData icon, String text, Color color) => Row(children: [
      Icon(icon, color: color, size: 16),
      const SizedBox(width: 8),
      Expanded(
          child: Text(text,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w600))),
    ]);

Widget _StepRow(String step, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
                color: const Color(0xFF0D6E4F).withValues(alpha: 0.15),
                shape: BoxShape.circle),
            child: Center(
                child: Text(step,
                    style: const TextStyle(
                        color: Color(0xFF0D6E4F),
                        fontSize: 10,
                        fontWeight: FontWeight.w800)))),
        const SizedBox(width: 8),
        Text(text,
            style: const TextStyle(color: Color(0xFF4A7A63), fontSize: 12)),
      ]),
    );
