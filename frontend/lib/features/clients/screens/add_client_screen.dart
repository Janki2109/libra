import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../../core/services/dio_client.dart';
import '../../../core/utils/validators.dart';
import '../providers/client_provider.dart';

// ── Theme Colors ───────────────────────────────────
const _bg = Color(0xFFF6F5FB);
const _bgCard = Color(0xFFFFFFFF);
const _brown = Color(0xFF150E3D);
const _gold = Color(0xFFB8860B);
const _border = Color(0xFFE6E3F4);
const _textPri = Color(0xFF2C1A0E);
const _textMuted = Color(0xFF3D2C8D);

class AddClientScreen extends StatefulWidget {
  const AddClientScreen({super.key});
  @override
  State<AddClientScreen> createState() => _AddClientScreenState();
}

class _AddClientScreenState extends State<AddClientScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _altPhoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController();
  final _pincodeCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _idProofType = 'Aadhaar';
  bool _loading = false;
  Uint8List? _idProofBytes;
  String _idProofMimeType = 'image/jpeg';

  final List<String> _idProofTypes = [
    'Aadhaar',
    'PAN',
    'Passport',
    'Voter ID',
    'Driving License',
    'Other'
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _altPhoneCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    _pincodeCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickIdProof() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take Photo'),
            onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from Gallery'),
            onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (source == null) return;

    final picker = ImagePicker();
    final picked =
        await picker.pickImage(source: source, imageQuality: 80, maxWidth: 1600);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final ext = picked.name.split('.').last.toLowerCase();
    setState(() {
      _idProofBytes = bytes;
      _idProofMimeType = ext == 'png' ? 'image/png' : 'image/jpeg';
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.lightImpact();
    setState(() => _loading = true);

    final result = await context.read<ClientProvider>().addClient({
      'name': _nameCtrl.text.trim(),
      'email': _emailCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'alternate_phone': _altPhoneCtrl.text.trim(),
      'address': _addressCtrl.text.trim(),
      'city': _cityCtrl.text.trim(),
      'state': _stateCtrl.text.trim(),
      'pincode': _pincodeCtrl.text.trim(),
      'id_proof_type': _idProofType,
      'notes': _notesCtrl.text.trim(),
    });

    // Uploaded as a regular client document, tagged by ID proof type, so it
    // shows up in the client's Documents list like anything else — there is
    // no separate "ID proof" storage slot on the client record itself.
    if (result != null && _idProofBytes != null) {
      try {
        await DioClient.instance.post('/documents/upload', data: {
          'file_name': '$_idProofType - ${_nameCtrl.text.trim()}',
          'file_content': base64Encode(_idProofBytes!),
          'file_type': _idProofMimeType == 'image/png' ? 'png' : 'jpg',
          'mime_type': _idProofMimeType,
          'category': 'ID Proof',
          'client_id': result['id'],
          'description': _idProofType,
        });
      } catch (_) {
        // Client is already created; a failed document upload shouldn't
        // block that — it can be uploaded again from the client's page.
      }
    }

    setState(() => _loading = false);

    if (result != null && mounted) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Client added successfully!'),
        backgroundColor: const Color(0xFF2E8B57),
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      context.pop();
    } else if (mounted) {
      HapticFeedback.vibrate();
      final message =
          context.read<ClientProvider>().error ?? 'Failed to add client';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFD9534F),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _bg,
        body: Stack(children: [
          Column(children: [
            // ── Brown AppBar ──
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF150E3D), Color(0xFF0B0726)],
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
                      onPressed: () => context.pop(),
                    ),
                    const Expanded(
                      child: Text('Add Client',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700)),
                    ),
                    TextButton(
                      onPressed: _loading ? null : _submit,
                      child: const Text('Save',
                          style: TextStyle(
                              color: Color(0xFFFFD700),
                              fontWeight: FontWeight.w700,
                              fontSize: 15)),
                    ),
                  ]),
                ),
              ),
            ),

            // ── Form ──
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _SectionHeader(
                        title: 'Personal Information',
                        icon: Icons.person_outline_rounded),
                    const SizedBox(height: 12),
                    _buildField(
                        controller: _nameCtrl,
                        label: 'Full Name *',
                        icon: Icons.person_rounded,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z ]')),
                        ],
                        validator: Validators.name),
                    const SizedBox(height: 10),
                    _buildField(
                        controller: _emailCtrl,
                        label: 'Email Address *',
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) => v!.trim().isEmpty
                            ? 'Email is required'
                            : null),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                          child: _buildField(
                              controller: _phoneCtrl,
                              label: 'Phone Number *',
                              icon: Icons.phone_outlined,
                              keyboardType: TextInputType.phone,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(10),
                              ],
                              validator: (v) => Validators.phone(v))),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _buildField(
                              controller: _altPhoneCtrl,
                              label: 'Alternate Phone',
                              icon: Icons.phone_outlined,
                              keyboardType: TextInputType.phone,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(10),
                              ],
                              validator: (v) =>
                                  Validators.phone(v, required: false))),
                    ]),
                    const SizedBox(height: 20),

                    _SectionHeader(
                        title: 'Address Details',
                        icon: Icons.location_on_outlined),
                    const SizedBox(height: 12),
                    _buildField(
                        controller: _addressCtrl,
                        label: 'Full Address *',
                        icon: Icons.home_outlined,
                        maxLines: 2,
                        validator: (v) =>
                            v!.trim().isEmpty ? 'Address required' : null),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                          child: _buildField(
                              controller: _cityCtrl,
                              label: 'City *',
                              icon: Icons.location_city_outlined,
                              validator: (v) =>
                                  v!.trim().isEmpty ? 'City required' : null)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _buildField(
                              controller: _stateCtrl,
                              label: 'State *',
                              icon: Icons.map_outlined,
                              validator: (v) => v!.trim().isEmpty
                                  ? 'State required'
                                  : null)),
                    ]),
                    const SizedBox(height: 10),
                    _buildField(
                        controller: _pincodeCtrl,
                        label: 'Pincode *',
                        icon: Icons.pin_outlined,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        validator: Validators.pincode),
                    const SizedBox(height: 20),

                    _SectionHeader(
                        title: 'ID Proof', icon: Icons.badge_outlined),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 2),
                      decoration: BoxDecoration(
                        color: _bgCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _border),
                        boxShadow: [
                          BoxShadow(
                              color: _brown.withValues(alpha: 0.04),
                              blurRadius: 6,
                              offset: const Offset(0, 2))
                        ],
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _idProofType,
                          dropdownColor: _bgCard,
                          style: const TextStyle(color: _textPri, fontSize: 14),
                          icon: const Icon(Icons.keyboard_arrow_down_rounded,
                              color: _brown),
                          items: _idProofTypes
                              .map((t) =>
                                  DropdownMenuItem(value: t, child: Text(t)))
                              .toList(),
                          onChanged: (v) => setState(() => _idProofType = v!),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _idProofBytes == null
                        ? OutlinedButton.icon(
                            onPressed: _pickIdProof,
                            icon: const Icon(Icons.upload_file_rounded,
                                color: _brown, size: 18),
                            label: const Text('Upload ID Proof Document',
                                style: TextStyle(color: _textPri)),
                            style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: _border),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12))))
                        : Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                                color: _bgCard,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: _brown, width: 1.2)),
                            child: Row(children: [
                              ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.memory(_idProofBytes!,
                                      width: 48, height: 48, fit: BoxFit.cover)),
                              const SizedBox(width: 12),
                              const Expanded(
                                  child: Text('ID proof document selected',
                                      style: TextStyle(
                                          color: _textPri,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13))),
                              TextButton(
                                  onPressed: _pickIdProof,
                                  child: const Text('Replace',
                                      style: TextStyle(
                                          color: _gold,
                                          fontWeight: FontWeight.w700))),
                            ])),
                    const SizedBox(height: 20),

                    _SectionHeader(
                        title: 'Additional Notes', icon: Icons.notes_rounded),
                    const SizedBox(height: 12),
                    _buildField(
                        controller: _notesCtrl,
                        label: 'Notes (optional)',
                        icon: Icons.note_outlined,
                        maxLines: 3),
                    const SizedBox(height: 28),

                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _brown,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: _loading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Text('Add Client',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white)),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      inputFormatters: inputFormatters,
      style: const TextStyle(color: _textPri, fontSize: 14),
      validator: validator,
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
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFD9534F))),
      ),
    );
  }
}

// ── Section Header ─────────────────────────────────
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
            color: _brown,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Colors.white, size: 15),
        ),
        const SizedBox(width: 10),
        Text(title,
            style: const TextStyle(
                color: _textPri, fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        Expanded(child: Container(height: 0.6, color: _border)),
      ]);
}
