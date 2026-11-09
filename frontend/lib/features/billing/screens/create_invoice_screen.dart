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
  // GST and the platform fee are mandatory and fixed — the lawyer cannot
  // remove or change either. These mirror the backend's
  // services.ComputeInvoiceBreakdown constants for display only; the
  // authoritative calculation happens server-side in CreateInvoice, which
  // recomputes both from the submitted subtotal and ignores any tax/total
  // figure a client might send.
  static const double _gstPercent = 18;
  static const double _platformFee = 100;
  final _upiIdCtrl = TextEditingController();
  final _accountNameCtrl = TextEditingController();
  final _accountNumberCtrl = TextEditingController();
  final _ifscCtrl = TextEditingController();
  final _bankNameCtrl = TextEditingController();
  final _bankBranchCtrl = TextEditingController();
  bool _loading = false;
  bool _bankDetailsExpanded = true;
  List<Map<String, dynamic>> _paymentProfiles = [];
  String? _selectedProfileId; // null = "New details" (or nothing selected yet)
  bool _profilesLoading = false;

  @override
  void initState() {
    super.initState();
    _invoiceNumCtrl.text =
        'INV-${DateTime.now().year}-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ClientProvider>().loadClients();
      _loadFirmBankDetails();
      _loadPaymentProfiles();
    });
  }

  Future<void> _loadPaymentProfiles() async {
    setState(() => _profilesLoading = true);
    try {
      final res = await DioClient.instance.get('/firm/payment-profiles');
      final list = (res.data['data'] as List?) ?? [];
      setState(() {
        _paymentProfiles = list.cast<Map<String, dynamic>>();
        _profilesLoading = false;
      });
      // Pre-select the firm's default profile, if one exists and nothing
      // else has been typed yet (the firm-wide bank details load already
      // ran and may have filled the form from /firm/bank-details — this
      // only applies the saved-profile selection on top of that silently
      // when a default profile exists, so the lawyer sees it pre-picked
      // rather than having to find and tap it themselves).
      final defaultProfile = _paymentProfiles
          .cast<Map<String, dynamic>?>()
          .firstWhere((p) => p?['is_default'] == true, orElse: () => null);
      if (defaultProfile != null && _selectedProfileId == null) {
        _applyProfile(defaultProfile['id'] as String, markSelected: true);
      }
    } catch (e) {
      if (mounted) setState(() => _profilesLoading = false);
      debugPrint('Payment profiles load error: $e');
    }
  }

  // Takes the profile's id, not the list item itself: ListPaymentProfiles
  // masks the account number (e.g. "XXXXXX7890") for display, and prefilling
  // the invoice form from that masked value — or just leaving the field
  // blank, as this used to do — defeated the entire point of "automatically
  // fetch saved bank details": the lawyer still had to retype their own
  // account number on every single invoice. GET /firm/payment-profiles/:id
  // returns the real number for the lawyer's own saved profile, which is
  // exactly what's needed here since it's about to be reused, not displayed
  // in a list.
  Future<void> _applyProfile(String profileId,
      {bool markSelected = true}) async {
    try {
      final res = await DioClient.instance
          .get('/firm/payment-profiles/$profileId');
      final p = res.data['data'] as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _upiIdCtrl.text = (p['upi_id'] ?? '').toString();
        _accountNameCtrl.text = (p['bank_account_name'] ?? '').toString();
        _accountNumberCtrl.text = (p['bank_account_number'] ?? '').toString();
        _ifscCtrl.text = (p['bank_ifsc'] ?? '').toString();
        _bankNameCtrl.text = (p['bank_name'] ?? '').toString();
        _bankBranchCtrl.text = (p['bank_branch'] ?? '').toString();
        if (markSelected) _selectedProfileId = profileId;
        _bankDetailsExpanded = true;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Could not load saved payment details: ${DioClient.describeError(e)}'),
          backgroundColor: const Color(0xFFD9534F)));
    }
  }

  void _useNewDetails() {
    setState(() {
      _selectedProfileId = null;
      _upiIdCtrl.clear();
      _accountNameCtrl.clear();
      _accountNumberCtrl.clear();
      _ifscCtrl.clear();
      _bankNameCtrl.clear();
      _bankBranchCtrl.clear();
      _bankDetailsExpanded = true;
    });
  }

  Future<void> _saveCurrentAsProfile({String? updateId}) async {
    final nameCtrl = TextEditingController(
        text: updateId == null
            ? ''
            : (_paymentProfiles.firstWhere(
                    (p) => p['id'] == updateId)['name'] ??
                '') as String);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(updateId == null ? 'Save Payment Profile' : 'Update Profile',
            style: const TextStyle(color: _textPri, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'e.g. Primary Bank Account',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E8B57)),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;

    final body = {
      'name': name,
      'upi_id': _upiIdCtrl.text.trim(),
      'bank_account_name': _accountNameCtrl.text.trim(),
      'bank_account_number': _accountNumberCtrl.text.trim(),
      'bank_ifsc': _ifscCtrl.text.trim().toUpperCase(),
      'bank_name': _bankNameCtrl.text.trim(),
      'bank_branch': _bankBranchCtrl.text.trim(),
      'is_default': _paymentProfiles.isEmpty, // first profile defaults itself
    };
    try {
      if (updateId == null) {
        await DioClient.instance.post('/firm/payment-profiles', data: body);
      } else {
        await DioClient.instance
            .put('/firm/payment-profiles/$updateId', data: body);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('Payment profile saved'),
            backgroundColor: const Color(0xFF2E8B57)));
      }
      await _loadPaymentProfiles();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(DioClient.describeError(e)),
            backgroundColor: const Color(0xFFD9534F)));
      }
    }
  }

  Future<void> _setDefaultProfile(String id) async {
    try {
      await DioClient.instance.put('/firm/payment-profiles/$id/default');
      await _loadPaymentProfiles();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(DioClient.describeError(e)),
            backgroundColor: const Color(0xFFD9534F)));
      }
    }
  }

  Future<void> _deleteProfile(String id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete profile?',
            style: TextStyle(color: _textPri, fontWeight: FontWeight.w700)),
        content: Text('Delete "$name"? Invoices already sent using it are unaffected.',
            style: const TextStyle(color: _textMuted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD9534F)),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await DioClient.instance.delete('/firm/payment-profiles/$id');
      if (_selectedProfileId == id) _useNewDetails();
      await _loadPaymentProfiles();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(DioClient.describeError(e)),
            backgroundColor: const Color(0xFFD9534F)));
      }
    }
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
  double get _taxAmount => double.parse((_subtotal * _gstPercent / 100).toStringAsFixed(2));
  double get _total => double.parse((_subtotal + _taxAmount + _platformFee).toStringAsFixed(2));
  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _submit() async {
    // The payment-details fields live inside a collapsible section
    // (_bankDetailsExpanded) — when collapsed, those TextFormFields are
    // unmounted entirely, so Form.validate() silently skips them instead of
    // blocking submission. Checking the controllers directly here (not
    // through the Form) means a collapsed, empty section still blocks
    // Send Bill, and expanding it on failure shows the lawyer exactly why.
    //
    // Mirrors the backend's validatePaymentDetails rule exactly: at least
    // one complete method is required -- UPI, or full bank details -- not
    // both. Whichever method has any content at all must be fully valid;
    // leaving a method completely untouched is fine.
    final upi = _upiIdCtrl.text.trim();
    final hasAnyBankField = _accountNameCtrl.text.trim().isNotEmpty ||
        _accountNumberCtrl.text.trim().isNotEmpty ||
        _ifscCtrl.text.trim().isNotEmpty ||
        _bankNameCtrl.text.trim().isNotEmpty ||
        _bankBranchCtrl.text.trim().isNotEmpty;

    String? paymentError;
    if (upi.isEmpty && !hasAnyBankField) {
      paymentError =
          'Add a UPI ID or complete bank account details so the client can pay you';
    } else if (upi.isNotEmpty) {
      paymentError = _validateUpi(_upiIdCtrl.text);
    }
    if (paymentError == null && hasAnyBankField) {
      if (_accountNameCtrl.text.trim().isEmpty) {
        paymentError = 'Account holder name is required';
      } else if (_accountNumberCtrl.text.trim().isEmpty) {
        paymentError = 'Bank account number is required';
      } else if (_ifscCtrl.text.trim().isEmpty) {
        paymentError = 'IFSC code is required';
      } else if (_bankNameCtrl.text.trim().isEmpty) {
        paymentError = 'Bank name is required';
      } else if (_bankBranchCtrl.text.trim().isEmpty) {
        paymentError = 'Branch name is required';
      } else {
        paymentError = _validateAccountNumber(_accountNumberCtrl.text) ??
            _validateIfsc(_ifscCtrl.text);
      }
    }
    if (paymentError != null) {
      setState(() => _bankDetailsExpanded = true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(paymentError),
        backgroundColor: const Color(0xFFD9534F),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      return;
    }
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
      // Only 'subtotal' (the service amount the lawyer entered) is sent as a
      // money figure. GST and the platform fee are computed and applied by
      // the backend — CreateInvoice ignores any tax/total the client sends,
      // exactly so this request can never understate what the client owes.
      await DioClient.instance.post('/invoices', data: {
        'client_id': _selectedClientId,
        'invoice_number': _invoiceNumCtrl.text.trim(),
        'items': _items,
        'subtotal': _subtotal,
        'due_date': _formatDate(_dueDate),
        'notes': _notesCtrl.text.trim(),
        'upi_id': _upiIdCtrl.text.trim(),
        'bank_account_name': _accountNameCtrl.text.trim(),
        'bank_account_number': _accountNumberCtrl.text.trim(),
        'bank_ifsc': _ifscCtrl.text.trim().toUpperCase(),
        'bank_name': _bankNameCtrl.text.trim(),
        'bank_branch': _bankBranchCtrl.text.trim(),
      });
      await DioClient.instance.put('/firm/bank-details', data: {
        'upi_id': _upiIdCtrl.text.trim(),
        'bank_account_name': _accountNameCtrl.text.trim(),
        'bank_account_number': _accountNumberCtrl.text.trim(),
        'bank_ifsc': _ifscCtrl.text.trim().toUpperCase(),
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
          content: Text(DioClient.describeError(e)),
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

                    // Mandatory charges note
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
                                '18% GST and ₹100 platform fee are mandatory charges.',
                                style: TextStyle(
                                    color: Color(0xFFD4A017),
                                    fontSize: 12,
                                    height: 1.4))),
                      ]),
                    ),
                    const SizedBox(height: 16),

                    // Total — Consultation/Service Amount, GST (18%, fixed),
                    // Platform Fee (₹100, fixed), Total Payable. Neither
                    // charge is editable: there is no input here, only the
                    // computed display — the actual enforcement is
                    // server-side in CreateInvoice.
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
                        _TotalRow('Consultation / Service Amount',
                            '₹${_subtotal.toStringAsFixed(2)}', Colors.white),
                        _TotalRow('GST (18%) · mandatory',
                            '₹${_taxAmount.toStringAsFixed(2)}', Colors.white70),
                        _TotalRow('Platform Fee · mandatory',
                            '₹${_platformFee.toStringAsFixed(2)}', Colors.white70),
                        Divider(color: Colors.white.withValues(alpha: 0.3)),
                        _TotalRow('TOTAL PAYABLE',
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
                      if (_profilesLoading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Center(
                              child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF2E8B57)))),
                        )
                      else if (_paymentProfiles.isNotEmpty) ...[
                        const Align(
                            alignment: Alignment.centerLeft,
                            child: Text('Select Saved Payment Details',
                                style: TextStyle(
                                    color: _textMuted,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600))),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 108,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              _NewDetailsChip(
                                  selected: _selectedProfileId == null,
                                  onTap: _useNewDetails),
                              ..._paymentProfiles.map((p) => _ProfileChip(
                                    profile: p,
                                    selected: _selectedProfileId == p['id'],
                                    onTap: () =>
                                        _applyProfile(p['id'] as String),
                                    onSetDefault: () =>
                                        _setDefaultProfile(p['id'] as String),
                                    onDelete: () => _deleteProfile(
                                        p['id'] as String,
                                        (p['name'] ?? '').toString()),
                                  )),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
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
                              const Color(0xFF2E8B57),
                              validator: _validateUpi),
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
                              const Color(0xFF4A90D9),
                              validator: (v) =>
                                  _validateName(v, 'Account holder name')),
                          const SizedBox(height: 10),
                          _buildFieldColored(
                              _accountNumberCtrl,
                              'Account Number',
                              Icons.numbers_rounded,
                              const Color(0xFF4A90D9),
                              keyboardType: TextInputType.number,
                              validator: _validateAccountNumber),
                          const SizedBox(height: 10),
                          _buildFieldColored(_ifscCtrl, 'IFSC Code',
                              Icons.code_rounded, const Color(0xFF4A90D9),
                              validator: _validateIfsc),
                          const SizedBox(height: 10),
                          _buildFieldColored(
                              _bankNameCtrl,
                              'Bank Name',
                              Icons.account_balance_rounded,
                              const Color(0xFF4A90D9),
                              validator: (v) => _validateName(v, 'Bank name')),
                          const SizedBox(height: 10),
                          _buildFieldColored(
                              _bankBranchCtrl,
                              'Branch Name',
                              Icons.location_on_rounded,
                              const Color(0xFF4A90D9),
                              validator: (v) =>
                                  _validateName(v, 'Branch name')),
                          const SizedBox(height: 14),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () => _saveCurrentAsProfile(
                                  updateId: _selectedProfileId),
                              icon: const Icon(Icons.save_rounded,
                                  size: 16, color: Color(0xFF2E8B57)),
                              label: Text(
                                  _selectedProfileId == null
                                      ? 'Save as New Profile'
                                      : 'Update This Profile',
                                  style: const TextStyle(
                                      color: Color(0xFF2E8B57),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12)),
                            ),
                          ),
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
          {TextInputType? keyboardType, String? Function(String?)? validator}) =>
      TextFormField(
          controller: ctrl,
          keyboardType: keyboardType,
          validator: validator,
          autovalidateMode: AutovalidateMode.onUserInteraction,
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
            errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFD9534F))),
          ));

  // Mirrors the backend's validatePaymentDetails (payment_details.go) —
  // same rules, so a lawyer sees the exact same "why is this blocked"
  // message inline instead of only after the server rejects the request.
  // The backend remains the authority: this is a UX convenience, not the
  // enforcement point.
  static final _upiIdPattern =
      RegExp(r'^[a-zA-Z0-9.\-_]{2,256}@[a-zA-Z]{2,64}$');
  static final _ifscPattern = RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$');
  static final _accountNumberPattern = RegExp(r'^[0-9]{9,18}$');

  // These per-field validators are now format-only (empty is allowed here):
  // only one payment method is mandatory overall -- UPI, or complete bank
  // details -- matching the backend's validatePaymentDetails. Whether a
  // method is actually required at all, and whether a half-filled bank
  // section counts as "touched", is decided centrally in _submit, which has
  // visibility across every field; a single field's own validator can't see
  // its siblings to make that call correctly.
  String? _validateUpi(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null;
    if (!_upiIdPattern.hasMatch(s)) return 'Enter a valid UPI ID (e.g. yourname@upi)';
    return null;
  }

  String? _validateName(String? v, String label) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null;
    if (s.length < 2) return '$label is required';
    return null;
  }

  String? _validateAccountNumber(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null;
    if (!_accountNumberPattern.hasMatch(s)) {
      return 'Enter a valid account number (9–18 digits)';
    }
    return null;
  }

  String? _validateIfsc(String? v) {
    final s = (v ?? '').trim().toUpperCase();
    if (s.isEmpty) return null;
    if (!_ifscPattern.hasMatch(s)) return 'Enter a valid IFSC (e.g. SBIN0001234)';
    return null;
  }
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

class _NewDetailsChip extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  const _NewDetailsChip({required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 130,
          margin: const EdgeInsets.only(right: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFF2E8B57).withValues(alpha: 0.1)
                  : _bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: selected
                      ? const Color(0xFF2E8B57)
                      : _border,
                  width: selected ? 1.5 : 1)),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_circle_outline_rounded,
                  color: Color(0xFF2E8B57), size: 22),
              SizedBox(height: 8),
              Text('New Payment\nDetails',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Color(0xFF2E8B57),
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      );
}

class _ProfileChip extends StatelessWidget {
  final Map<String, dynamic> profile;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onSetDefault;
  final VoidCallback onDelete;
  const _ProfileChip({
    required this.profile,
    required this.selected,
    required this.onTap,
    required this.onSetDefault,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final name = (profile['name'] ?? 'Profile').toString();
    final upi = (profile['upi_id'] ?? '').toString();
    final bank = (profile['bank_name'] ?? '').toString();
    final maskedAcc = (profile['bank_account_number'] ?? '').toString();
    final isDefault = profile['is_default'] == true;
    final subtitle = upi.isNotEmpty
        ? upi
        : (bank.isNotEmpty ? '$bank${maskedAcc.isNotEmpty ? ' · $maskedAcc' : ''}' : 'No details');

    return GestureDetector(
      onTap: onTap,
      onLongPress: () => _showProfileActions(context),
      child: Container(
        width: 170,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF2E8B57).withValues(alpha: 0.1)
                : _bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: selected ? const Color(0xFF2E8B57) : _border,
                width: selected ? 1.5 : 1)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: _textPri,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700))),
              GestureDetector(
                  onTap: () => _showProfileActions(context),
                  child: const Icon(Icons.more_vert_rounded,
                      size: 16, color: _textMuted)),
            ]),
            if (isDefault) ...[
              const SizedBox(height: 2),
              const Text('DEFAULT',
                  style: TextStyle(
                      color: Color(0xFF2E8B57),
                      fontSize: 9,
                      fontWeight: FontWeight.w800)),
            ],
            const Spacer(),
            Text(subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _textMuted, fontSize: 10.5)),
          ],
        ),
      ),
    );
  }

  void _showProfileActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.star_rounded, color: Color(0xFF2E8B57)),
            title: const Text('Set as Default'),
            onTap: () {
              Navigator.pop(context);
              onSetDefault();
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded,
                color: Color(0xFFD9534F)),
            title: const Text('Delete Profile'),
            onTap: () {
              Navigator.pop(context);
              onDelete();
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
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
