import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/services/dio_client.dart';
import '../../clients/providers/client_provider.dart';

const _bg = Color(0xFFF6F5FB);
const _bgCard = Color(0xFFFFFFFF);
const _brown = Color(0xFF150E3D);
const _brownLight = Color(0xFF3D2C8D);
const _border = Color(0xFFE6E3F4);
const _textPri = Color(0xFF2C1A0E);
const _textMuted = Color(0xFF3D2C8D);

class CreateInvoiceScreen extends StatefulWidget {
  const CreateInvoiceScreen({super.key});
  @override
  State<CreateInvoiceScreen> createState() => _CreateInvoiceScreenState();
}

class _CreateInvoiceScreenState extends State<CreateInvoiceScreen> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedClientId;
  String? _selectedClientName;
  final _invoiceNumCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  DateTime _dueDate = DateTime.now().add(const Duration(days: 30));
  List<Map<String, dynamic>> _items = [
    {'description': '', 'amount': 0.0}
  ];
  double _taxPercent = 0;
  final _upiIdCtrl = TextEditingController();
  final _accountNameCtrl = TextEditingController();
  final _accountNumberCtrl = TextEditingController();
  final _ifscCtrl = TextEditingController();
  final _bankNameCtrl = TextEditingController();
  final _bankBranchCtrl = TextEditingController();
  bool _loading = false;
  bool _bankDetailsExpanded = true;

  @override
  void initState() {
    super.initState();
    _invoiceNumCtrl.text =
        'INV-${DateTime.now().year}-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ClientProvider>().loadClients();
      _loadFirmBankDetails();
    });
  }

  @override
  void dispose() {
    _invoiceNumCtrl.dispose();
    _notesCtrl.dispose();
    _upiIdCtrl.dispose();
    _accountNameCtrl.dispose();
    _accountNumberCtrl.dispose();
    _ifscCtrl.dispose();
    _bankNameCtrl.dispose();
    _bankBranchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFirmBankDetails() async {
    try {
      final res = await DioClient.instance.get('/firm/bank-details');
      final data = res.data['data'] ?? {};
      setState(() {
        _upiIdCtrl.text = data['upi_id'] ?? '';
        _accountNameCtrl.text = data['bank_account_name'] ?? '';
        _accountNumberCtrl.text = data['bank_account_number'] ?? '';
        _ifscCtrl.text = data['bank_ifsc'] ?? '';
        _bankNameCtrl.text = data['bank_name'] ?? '';
        _bankBranchCtrl.text = data['bank_branch'] ?? '';
      });
    } catch (e) {
      debugPrint('Bank details error: $e');
    }
  }

  double get _subtotal => _items.fold(0, (s, i) => s + (i['amount'] as double));
  double get _taxAmount => _subtotal * _taxPercent / 100;
  double get _total => _subtotal + _taxAmount;
  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedClientId == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Please select a client'),
        backgroundColor: const Color(0xFFD9534F),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => _loading = true);
    try {
      await DioClient.instance.post('/invoices', data: {
        'client_id': _selectedClientId,
        'invoice_number': _invoiceNumCtrl.text.trim(),
        'items': _items,
        'subtotal': _subtotal,
        'tax_percent': _taxPercent,
        'tax_amount': _taxAmount,
        'total_amount': _total,
        'due_date': _formatDate(_dueDate),
        'notes': _notesCtrl.text.trim(),
        'upi_id': _upiIdCtrl.text.trim(),
        'bank_account_name': _accountNameCtrl.text.trim(),
        'bank_account_number': _accountNumberCtrl.text.trim(),
        'bank_ifsc': _ifscCtrl.text.trim(),
        'bank_name': _bankNameCtrl.text.trim(),
      });
      await DioClient.instance.put('/firm/bank-details', data: {
        'upi_id': _upiIdCtrl.text.trim(),
        'bank_account_name': _accountNameCtrl.text.trim(),
        'bank_account_number': _accountNumberCtrl.text.trim(),
        'bank_ifsc': _ifscCtrl.text.trim(),
        'bank_name': _bankNameCtrl.text.trim(),
        'bank_branch': _bankBranchCtrl.text.trim(),
      });
      if (mounted) {
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Invoice sent to $_selectedClientName! They can now pay directly.'),
          backgroundColor: const Color(0xFF2E8B57),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
        context.pop();
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Failed to create invoice'),
          backgroundColor: const Color(0xFFD9534F),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final clients = context.watch<ClientProvider>().clients;
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
                    IconButton(
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: Colors.white),
                        onPressed: () => context.pop()),
                    const Expanded(
                        child: Text('Create Invoice',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w700))),
                    TextButton(
                        onPressed: _loading ? null : _submit,
                        child: const Text('Send Bill',
                            style: TextStyle(
                                color: Color(0xFFFFD700),
                                fontWeight: FontWeight.w700,
                                fontSize: 15))),
                  ]),
                )),
          ),
          Expanded(
              child: Form(
                  key: _formKey,
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    // Client
                    _SectionHeader(
                        title: 'Send Bill To', icon: Icons.person_rounded),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 2),
                      decoration: BoxDecoration(
                          color: _bgCard,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color:
                                  _selectedClientId != null ? _brown : _border,
                              width: _selectedClientId != null ? 1.5 : 0.8),
                          boxShadow: [
                            BoxShadow(
                                color: _brown.withValues(alpha: 0.04),
                                blurRadius: 6,
                                offset: const Offset(0, 2))
                          ]),
                      child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                        value: _selectedClientId,
                        hint: const Text('Select Client *',
                            style: TextStyle(color: _textMuted, fontSize: 13)),
                        dropdownColor: _bgCard,
                        style: const TextStyle(color: _textPri, fontSize: 14),
                        icon: const Icon(Icons.keyboard_arrow_down_rounded,
                            color: _brown),
                        isExpanded: true,
                        items: clients
                            .map<DropdownMenuItem<String>>((cl) =>
                                DropdownMenuItem(
                                  value: cl['id'],
                                  child: Row(children: [
                                    Container(
                                        width: 28,
                                        height: 28,
                                        decoration: const BoxDecoration(
                                            gradient: LinearGradient(colors: [
                                              Color(0xFF150E3D),
                                              Color(0xFF3D2C8D)
                                            ]),
                                            shape: BoxShape.circle),
                                        child: Center(
                                            child: Text(
                                                (cl['name'] ?? '').isNotEmpty
                                                    ? cl['name'][0]
                                                        .toUpperCase()
                                                    : 'C',
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 11)))),
                                    const SizedBox(width: 10),
                                    Expanded(
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                          Text(cl['name'] ?? '',
                                              style: const TextStyle(
                                                  color: _textPri,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13)),
                                          Text(cl['email'] ?? '',
                                              style: const TextStyle(
                                                  color: _textMuted,
                                                  fontSize: 11)),
                                        ])),
                                  ]),
                                ))
                            .toList(),
                        onChanged: (v) => setState(() {
                          _selectedClientId = v;
                          final cl = clients.firstWhere((c) => c['id'] == v,
                              orElse: () => {});
                          _selectedClientName = cl['name'];
                        }),
                      )),
                    ),
                    const SizedBox(height: 20),

                    // Invoice details
                    _SectionHeader(
                        title: 'Invoice Details', icon: Icons.receipt_rounded),
                    const SizedBox(height: 10),
                    _buildField(_invoiceNumCtrl, 'Invoice Number *',
                        Icons.numbers_rounded),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _dueDate,
                          firstDate: DateTime.now(),
                          lastDate:
                              DateTime.now().add(const Duration(days: 365)),
                          builder: (ctx, child) => Theme(
                              data: ThemeData.light().copyWith(
                                  colorScheme: const ColorScheme.light(
                                      primary: Color(0xFF150E3D),
                                      surface: Color(0xFFF6F5FB))),
                              child: child!),
                        );
                        if (picked != null) setState(() => _dueDate = picked);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                            color: _bgCard,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _border, width: 0.8),
                            boxShadow: [
                              BoxShadow(
                                  color: _brown.withValues(alpha: 0.04),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2))
                            ]),
                        child: Row(children: [
                          const Icon(Icons.calendar_today_rounded,
                              color: _brown, size: 20),
                          const SizedBox(width: 12),
                          Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Due Date',
                                    style: TextStyle(
                                        color: _textMuted, fontSize: 11)),
                                Text(
                                    '${_dueDate.day}/${_dueDate.month}/${_dueDate.year}',
                                    style: const TextStyle(
                                        color: _textPri,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15)),
                              ]),
                          const Spacer(),
                          const Icon(Icons.edit_rounded,
                              color: _textMuted, size: 16),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Fee items
                    _SectionHeader(
                        title: 'Fee Details', icon: Icons.list_rounded),
                    const SizedBox(height: 10),
                    ..._items.asMap().entries.map((e) {
                      final i = e.key;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            color: _bgCard,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _border, width: 0.8),
                            boxShadow: [
                              BoxShadow(
                                  color: _brown.withValues(alpha: 0.04),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2))
                            ]),
                        child: Column(children: [
                          Row(children: [
                            Text('Item ${i + 1}',
                                style: const TextStyle(
                                    color: _brownLight,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12)),
                            const Spacer(),
                            if (_items.length > 1)
                              GestureDetector(
                                  onTap: () =>
                                      setState(() => _items.removeAt(i)),
                                  child: const Icon(Icons.delete_rounded,
                                      color: Color(0xFFD9534F), size: 18)),
                          ]),
                          const SizedBox(height: 8),
                          TextFormField(
                            initialValue: _items[i]['description'],
                            style:
                                const TextStyle(color: _textPri, fontSize: 14),
                            onChanged: (v) => _items[i]['description'] = v,
                            decoration: InputDecoration(
                              labelText: 'Description *',
                              labelStyle: const TextStyle(
                                  color: _textMuted, fontSize: 13),
                              filled: true,
                              fillColor: _bg,
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: _border)),
                              enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                      color: _border, width: 0.8)),
                              focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                      color: _brown, width: 1.5)),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            initialValue: _items[i]['amount'] == 0
                                ? ''
                                : '${_items[i]['amount']}',
                            style:
                                const TextStyle(color: _textPri, fontSize: 14),
                            keyboardType: TextInputType.number,
                            onChanged: (v) => setState(() => _items[i]
                                ['amount'] = double.tryParse(v) ?? 0.0),
                            decoration: InputDecoration(
                              labelText: 'Amount (₹) *',
                              labelStyle: const TextStyle(
                                  color: _textMuted, fontSize: 13),
                              prefixIcon: const Icon(
                                  Icons.currency_rupee_rounded,
                                  color: _brown,
                                  size: 18),
                              filled: true,
                              fillColor: _bg,
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: _border)),
                              enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                      color: _border, width: 0.8)),
                              focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(
                                      color: _brown, width: 1.5)),
                            ),
                          ),
                        ]),
                      );
                    }),
                    GestureDetector(
                      onTap: () => setState(
                          () => _items.add({'description': '', 'amount': 0.0})),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            color: _brown.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _brown.withValues(alpha: 0.3))),
                        child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_rounded, color: _brown, size: 18),
                              SizedBox(width: 6),
                              Text('Add Fee Item',
                                  style: TextStyle(
                                      color: _brown,
                                      fontWeight: FontWeight.w600)),
                            ]),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Tax
                    Row(children: [
                      const Text('Tax (%)',
                          style: TextStyle(color: _textPri, fontSize: 14)),
                      Expanded(
                          child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                            activeTrackColor: _brown,
                            thumbColor: _brown,
                            inactiveTrackColor: _border),
                        child: Slider(
                            value: _taxPercent,
                            min: 0,
                            max: 28,
                            divisions: 28,
                            label: '${_taxPercent.toInt()}%',
                            onChanged: (v) => setState(() => _taxPercent = v)),
                      )),
                      Text('${_taxPercent.toInt()}%',
                          style: const TextStyle(
                              color: _brown, fontWeight: FontWeight.w700)),
                    ]),

                    // Total
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [Color(0xFF150E3D), Color(0xFF0B0726)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(children: [
                        _TotalRow('Subtotal',
                            '₹${_subtotal.toStringAsFixed(2)}', Colors.white),
                        if (_taxPercent > 0)
                          _TotalRow(
                              'Tax (${_taxPercent.toInt()}%)',
                              '₹${_taxAmount.toStringAsFixed(2)}',
                              Colors.white70),
                        Divider(color: Colors.white.withValues(alpha: 0.3)),
                        _TotalRow('Total Amount',
                            '₹${_total.toStringAsFixed(2)}', Colors.white,
                            bold: true),
                      ]),
                    ),
                    const SizedBox(height: 20),

                    // Bank details
                    GestureDetector(
                      onTap: () => setState(
                          () => _bankDetailsExpanded = !_bankDetailsExpanded),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                            color: _bgCard,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color:
                                    const Color(0xFF2E8B57).withValues(alpha: 0.3)),
                            boxShadow: [
                              BoxShadow(
                                  color: _brown.withValues(alpha: 0.04),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2))
                            ]),
                        child: Row(children: [
                          Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                  color:
                                      const Color(0xFF2E8B57).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10)),
                              child: const Icon(Icons.account_balance_rounded,
                                  color: Color(0xFF2E8B57), size: 18)),
                          const SizedBox(width: 12),
                          const Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text('Payment Details',
                                    style: TextStyle(
                                        color: Color(0xFF2E8B57),
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14)),
                                Text(
                                    'Add UPI & bank details for client payment',
                                    style: TextStyle(
                                        color: _textMuted, fontSize: 11)),
                              ])),
                          Icon(
                              _bankDetailsExpanded
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              color: const Color(0xFF2E8B57)),
                        ]),
                      ),
                    ),
                    if (_bankDetailsExpanded) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                            color: _bgCard,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color:
                                    const Color(0xFF2E8B57).withValues(alpha: 0.2)),
                            boxShadow: [
                              BoxShadow(
                                  color: _brown.withValues(alpha: 0.04),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2))
                            ]),
                        child: Column(children: [
                          _buildFieldColored(
                              _upiIdCtrl,
                              'UPI ID (e.g. lawyer@upi)',
                              Icons.phone_android_rounded,
                              const Color(0xFF2E8B57)),
                          const SizedBox(height: 10),
                          Divider(color: _border, thickness: 0.6),
                          const SizedBox(height: 10),
                          const Align(
                              alignment: Alignment.centerLeft,
                              child: Text('Bank Account Details',
                                  style: TextStyle(
                                      color: _textMuted,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600))),
                          const SizedBox(height: 10),
                          _buildFieldColored(
                              _accountNameCtrl,
                              'Account Holder Name',
                              Icons.person_rounded,
                              const Color(0xFF4A90D9)),
                          const SizedBox(height: 10),
                          _buildFieldColored(
                              _accountNumberCtrl,
                              'Account Number',
                              Icons.numbers_rounded,
                              const Color(0xFF4A90D9),
                              keyboardType: TextInputType.number),
                          const SizedBox(height: 10),
                          _buildFieldColored(_ifscCtrl, 'IFSC Code',
                              Icons.code_rounded, const Color(0xFF4A90D9)),
                          const SizedBox(height: 10),
                          _buildFieldColored(
                              _bankNameCtrl,
                              'Bank Name',
                              Icons.account_balance_rounded,
                              const Color(0xFF4A90D9)),
                          const SizedBox(height: 10),
                          _buildFieldColored(
                              _bankBranchCtrl,
                              'Branch Name',
                              Icons.location_on_rounded,
                              const Color(0xFF4A90D9)),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 16),

                    // Notes
                    TextFormField(
                      controller: _notesCtrl,
                      maxLines: 3,
                      style: const TextStyle(color: _textPri, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Notes for client (optional)',
                        hintStyle:
                            const TextStyle(color: _textMuted, fontSize: 13),
                        prefixIcon: const Icon(Icons.note_rounded,
                            color: _brown, size: 18),
                        filled: true,
                        fillColor: _bgCard,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: _border)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: _border, width: 0.8)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: _brown, width: 1.5)),
                      ),
                    ),
                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: _brown,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            elevation: 0),
                        child: _loading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                    const Icon(Icons.send_rounded,
                                        color: Colors.white, size: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                        'Send Invoice to ${_selectedClientName ?? 'Client'}',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15)),
                                  ]),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ]))),
        ]),
      ),
    );
  }

  Widget _buildField(TextEditingController ctrl, String label, IconData icon) =>
      TextFormField(
          controller: ctrl,
          style: const TextStyle(color: _textPri, fontSize: 14),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: _textMuted, fontSize: 13),
            prefixIcon: Icon(icon, color: _brown, size: 18),
            filled: true,
            fillColor: _bgCard,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _border, width: 0.8)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _brown, width: 1.5)),
          ));

  Widget _buildFieldColored(
          TextEditingController ctrl, String label, IconData icon, Color color,
          {TextInputType? keyboardType}) =>
      TextFormField(
          controller: ctrl,
          keyboardType: keyboardType,
          style: const TextStyle(color: _textPri, fontSize: 14),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: _textMuted, fontSize: 13),
            prefixIcon: Icon(icon, color: color, size: 18),
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
                borderSide: BorderSide(color: color, width: 1.5)),
          ));
}

class _TotalRow extends StatelessWidget {
  final String label, value;
  final Color color;
  final bool bold;
  const _TotalRow(this.label, this.value, this.color, {this.bold = false});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: bold ? 15 : 13,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: bold ? 18 : 14,
                  fontWeight: bold ? FontWeight.w900 : FontWeight.w600)),
        ]),
      );
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon});
  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
                color: _brown, borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: Colors.white, size: 15)),
        const SizedBox(width: 10),
        Text(title,
            style: const TextStyle(
                color: _textPri, fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        Expanded(child: Container(height: 0.6, color: _border)),
      ]);
}
