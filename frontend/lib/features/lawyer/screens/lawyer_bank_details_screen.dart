import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/dio_client.dart';

/// Lawyer's own payout/settlement bank account — separate from the firm's
/// client-facing bank/UPI details on an invoice (create_invoice_screen.dart).
/// Never shown to a client: no client-facing screen or endpoint reads this.
class LawyerBankDetailsScreen extends StatefulWidget {
  const LawyerBankDetailsScreen({super.key});
  @override
  State<LawyerBankDetailsScreen> createState() =>
      _LawyerBankDetailsScreenState();
}

class _LawyerBankDetailsScreenState extends State<LawyerBankDetailsScreen> {
  final _holderCtrl = TextEditingController();
  final _bankNameCtrl = TextEditingController();
  final _accountCtrl = TextEditingController();
  final _ifscCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _existingPassbookDocId;
  Uint8List? _newPassbookBytes;
  String? _newPassbookFileName;
  String _newPassbookMime = 'image/jpeg';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _holderCtrl.dispose();
    _bankNameCtrl.dispose();
    _accountCtrl.dispose();
    _ifscCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await DioClient.instance.get('/lawyer/bank-details');
      final d = res.data['data'] ?? {};
      _holderCtrl.text = (d['bank_account_holder_name'] ?? '').toString();
      _bankNameCtrl.text = (d['bank_name'] ?? '').toString();
      _accountCtrl.text = (d['bank_account_number'] ?? '').toString();
      _ifscCtrl.text = (d['bank_ifsc'] ?? '').toString();
      _existingPassbookDocId =
          (d['bank_passbook_document_id'] ?? '').toString().isEmpty
              ? null
              : d['bank_passbook_document_id'].toString();
    } catch (_) {
      // First-time setup — nothing saved yet is not an error.
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickPassbook(ImageSource source) async {
    try {
      final picked = await ImagePicker()
          .pickImage(source: source, imageQuality: 80, maxWidth: 1600);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final ext = picked.name.split('.').last.toLowerCase();
      setState(() {
        _newPassbookBytes = bytes;
        _newPassbookFileName = picked.name;
        _newPassbookMime = ext == 'png' ? 'image/png' : 'image/jpeg';
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Could not access camera/gallery. Check app permissions.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating));
    }
  }

  Future<void> _save() async {
    if (_holderCtrl.text.trim().isEmpty ||
        _bankNameCtrl.text.trim().isEmpty ||
        _accountCtrl.text.trim().isEmpty ||
        _ifscCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please fill in all bank detail fields'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating));
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => _saving = true);
    try {
      // Passbook reuses the existing document-upload endpoint/storage — same
      // mechanism as every other document in the app, just a new category —
      // rather than a second upload path.
      var passbookDocId = _existingPassbookDocId;
      if (_newPassbookBytes != null) {
        final upRes = await DioClient.instance.post('/documents/upload', data: {
          'file_name': _newPassbookFileName ?? 'passbook.jpg',
          'file_type': _newPassbookMime,
          'file_content': base64Encode(_newPassbookBytes!),
          'mime_type': _newPassbookMime,
          'category': 'lawyer_bank_passbook',
          'description': 'Bank passbook for payout settlement',
        });
        passbookDocId = upRes.data['data']?['id']?.toString();
      }

      await DioClient.instance.put('/lawyer/bank-details', data: {
        'bank_account_holder_name': _holderCtrl.text.trim(),
        'bank_name': _bankNameCtrl.text.trim(),
        'bank_account_number': _accountCtrl.text.trim(),
        'bank_ifsc': _ifscCtrl.text.trim(),
        'bank_passbook_document_id': passbookDocId ?? '',
      });

      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() {
        _existingPassbookDocId = passbookDocId;
        _newPassbookBytes = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Bank details saved!'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not save: ${DioClient.describeError(e)}'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _deco(String label, IconData icon) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textMuted),
        prefixIcon: Icon(icon, color: AppColors.gold, size: 20),
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.gold)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.primaryDark,
        title: const Text('Payout Bank Details',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => context.pop()),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: AppColors.info.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: AppColors.info.withValues(alpha: 0.3))),
                      child: Row(children: [
                        const Icon(Icons.info_outline_rounded,
                            color: AppColors.info, size: 18),
                        const SizedBox(width: 10),
                        const Expanded(
                            child: Text(
                                'Used only to pay out your consultation/invoice earnings. Never shown to clients.',
                                style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12))),
                      ]),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                        controller: _holderCtrl,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: _deco('Account Holder Name',
                            Icons.person_outline_rounded)),
                    const SizedBox(height: 14),
                    TextField(
                        controller: _bankNameCtrl,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration:
                            _deco('Bank Name', Icons.account_balance_outlined)),
                    const SizedBox(height: 14),
                    TextField(
                        controller: _accountCtrl,
                        keyboardType: TextInputType.number,
                        obscureText: true,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: _deco(
                            'Account Number', Icons.credit_card_outlined)),
                    const SizedBox(height: 14),
                    TextField(
                        controller: _ifscCtrl,
                        textCapitalization: TextCapitalization.characters,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: _deco('IFSC Code', Icons.pin_outlined)),
                    const SizedBox(height: 20),
                    const Text('Bank Passbook',
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 14)),
                    const SizedBox(height: 4),
                    const Text('Upload a photo of your passbook first page',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 12)),
                    const SizedBox(height: 10),
                    if (_newPassbookBytes != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.border)),
                        child: Row(children: [
                          ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(_newPassbookBytes!,
                                  width: 48, height: 48, fit: BoxFit.cover)),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Text(
                                  _newPassbookFileName ?? 'Passbook selected',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13))),
                          TextButton(
                              onPressed: () =>
                                  _pickPassbook(ImageSource.gallery),
                              child: const Text('Replace',
                                  style: TextStyle(
                                      color: AppColors.gold,
                                      fontWeight: FontWeight.w700))),
                        ]),
                      )
                    else if (_existingPassbookDocId != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color:
                                    AppColors.success.withValues(alpha: 0.3))),
                        child: Row(children: [
                          const Icon(Icons.check_circle_rounded,
                              color: AppColors.success, size: 20),
                          const SizedBox(width: 10),
                          const Expanded(
                              child: Text('Passbook already uploaded',
                                  style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 13))),
                          TextButton(
                              onPressed: () =>
                                  _pickPassbook(ImageSource.gallery),
                              child: const Text('Replace',
                                  style: TextStyle(
                                      color: AppColors.gold,
                                      fontWeight: FontWeight.w700))),
                        ]),
                      ),
                    if (_newPassbookBytes == null &&
                        _existingPassbookDocId == null)
                      Row(children: [
                        Expanded(
                            child: OutlinedButton.icon(
                                onPressed: () =>
                                    _pickPassbook(ImageSource.gallery),
                                icon: const Icon(Icons.photo_library_outlined,
                                    color: AppColors.gold, size: 18),
                                label: const Text('Gallery',
                                    style: TextStyle(
                                        color: AppColors.textPrimary)),
                                style: OutlinedButton.styleFrom(
                                    side: const BorderSide(
                                        color: AppColors.border),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12))))),
                        const SizedBox(width: 12),
                        Expanded(
                            child: OutlinedButton.icon(
                                onPressed: () =>
                                    _pickPassbook(ImageSource.camera),
                                icon: const Icon(Icons.camera_alt_outlined,
                                    color: AppColors.gold, size: 18),
                                label: const Text('Camera',
                                    style: TextStyle(
                                        color: AppColors.textPrimary)),
                                style: OutlinedButton.styleFrom(
                                    side: const BorderSide(
                                        color: AppColors.border),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12))))),
                      ]),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.gold,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12))),
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: AppColors.primary, strokeWidth: 2))
                            : const Text('Save Bank Details',
                                style: TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15)),
                      ),
                    ),
                  ]),
            ),
    );
  }
}
