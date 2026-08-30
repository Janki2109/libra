import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/storage_service.dart';
import '../providers/auth_provider.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firmNameCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  final _barCouncilCtrl = TextEditingController();
  String _selectedCity = '';
  String _selectedState = '';
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _agreeToTerms = false;

  // ─── Lawyer verification document ─────────
  Uint8List? _docBytes;
  String? _docFileName;
  String _docMimeType = 'image/jpeg';
  bool _uploadingDoc = false;

  @override
  void dispose() {
    _firmNameCtrl.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPassCtrl.dispose();
    _barCouncilCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDocument(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
          source: source, imageQuality: 80, maxWidth: 1600);
      if (picked == null) return; // user cancelled — nothing to do
      final bytes = await picked.readAsBytes();
      final ext = picked.name.split('.').last.toLowerCase();
      final mime = (ext == 'png') ? 'image/png' : 'image/jpeg';
      setState(() {
        _docBytes = bytes;
        _docFileName = picked.name;
        _docMimeType = mime;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text(
              'Could not access camera/gallery. Check app permissions.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
    }
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (_docBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text(
              'Please upload or capture your verification document'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
      return;
    }
    if (!_agreeToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Please agree to Terms & Conditions'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
      return;
    }
    if (_passwordCtrl.text != _confirmPassCtrl.text) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Passwords do not match'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
      return;
    }

    HapticFeedback.lightImpact();
    final auth = context.read<AuthProvider>();
    final pendingPlan = await StorageService.takePendingPlan();
    if (!mounted) return;
    final success = await auth.register(
      firmName: _firmNameCtrl.text.trim(),
      name: _nameCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      password: _passwordCtrl.text,
      barCouncilNumber: _barCouncilCtrl.text.trim(),
      city: _selectedCity,
      state: _selectedState,
      plan: pendingPlan ?? '',
    );

    if (success && mounted) {
      setState(() => _uploadingDoc = true);
      final docOk = await auth.uploadVerificationDocument(
        fileName: _docFileName!,
        mimeType: _docMimeType,
        base64Content: 'data:$_docMimeType;base64,${base64Encode(_docBytes!)}',
      );
      if (mounted) setState(() => _uploadingDoc = false);
      if (!docOk && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text(
                'Account created, but the document upload failed. You can add it later from your profile.'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12))));
      }
      HapticFeedback.heavyImpact();
      if (mounted) context.go('/subscription');
    } else if (mounted) {
      HapticFeedback.vibrate();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(auth.error ?? 'Registration failed'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.primaryDark,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => context.go('/login')),
        title: const Text('Create Account',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
      body: Form(
        key: _formKey,
        child: ListView(padding: const EdgeInsets.all(20), children: [
          const SizedBox(height: 10),
          ShaderMask(
              shaderCallback: (b) => AppColors.goldGradient.createShader(b),
              child: const Text('Create Your Account',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Colors.white))),
          const SizedBox(height: 20),

          _buildField(
              controller: _firmNameCtrl,
              label: 'Law Firm / Practice Name *',
              icon: Icons.business_rounded,
              validator: (v) => v!.isEmpty ? 'Firm name required' : null),
          const SizedBox(height: 14),

          _buildField(
              controller: _nameCtrl,
              label: 'Your Full Name *',
              icon: Icons.person_rounded,
              validator: (v) => v!.isEmpty ? 'Name required' : null),
          const SizedBox(height: 14),

          _buildField(
              controller: _emailCtrl,
              label: 'Email Address *',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              validator: (v) => v!.isEmpty ? 'Email required' : null),
          const SizedBox(height: 14),

          // ✅ Phone - 10 digits only
          _buildField(
              controller: _phoneCtrl,
              label: 'Phone Number *',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              isPhone: true,
              validator: (v) {
                if (v!.isEmpty) return 'Phone required';
                if (v.length != 10) return 'Enter valid 10-digit number';
                return null;
              }),
          const SizedBox(height: 14),

          _buildField(
              controller: _barCouncilCtrl,
              label: 'Bar Council Number',
              icon: Icons.badge_outlined),
          const SizedBox(height: 14),

          Row(children: [
            Expanded(
                child: _buildField(
                    controller: TextEditingController(),
                    label: 'City',
                    icon: Icons.location_city_outlined,
                    onChanged: (v) => _selectedCity = v)),
            const SizedBox(width: 12),
            Expanded(
                child: _buildField(
                    controller: TextEditingController(),
                    label: 'State',
                    icon: Icons.map_outlined,
                    onChanged: (v) => _selectedState = v)),
          ]),
          const SizedBox(height: 14),

          _buildField(
              controller: _passwordCtrl,
              label: 'Password *',
              icon: Icons.lock_outline,
              obscure: _obscurePass,
              onToggleObscure: () =>
                  setState(() => _obscurePass = !_obscurePass),
              validator: (v) => v!.length < 6 ? 'Minimum 6 characters' : null),
          const SizedBox(height: 14),

          _buildField(
              controller: _confirmPassCtrl,
              label: 'Confirm Password *',
              icon: Icons.lock_outline,
              obscure: _obscureConfirm,
              onToggleObscure: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
              validator: (v) => v!.isEmpty ? 'Please confirm password' : null),
          const SizedBox(height: 20),

          // Lawyer verification document
          const Text('Verification Document *',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text(
              'Upload your Bar Council ID / professional license for verification',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          const SizedBox(height: 10),
          if (_docBytes != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border)),
              child: Row(children: [
                ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(_docBytes!,
                        width: 48, height: 48, fit: BoxFit.cover)),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(_docFileName ?? 'Document selected',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13))),
                TextButton(
                    onPressed: () => _pickDocument(ImageSource.gallery),
                    child: const Text('Replace',
                        style: TextStyle(
                            color: AppColors.gold,
                            fontWeight: FontWeight.w700))),
              ]),
            )
          else
            Row(children: [
              Expanded(
                  child: OutlinedButton.icon(
                      onPressed: () => _pickDocument(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined,
                          color: AppColors.gold, size: 18),
                      label: const Text('Gallery',
                          style: TextStyle(color: AppColors.textPrimary)),
                      style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.border),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12))))),
              const SizedBox(width: 12),
              Expanded(
                  child: OutlinedButton.icon(
                      onPressed: () => _pickDocument(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt_outlined,
                          color: AppColors.gold, size: 18),
                      label: const Text('Camera',
                          style: TextStyle(color: AppColors.textPrimary)),
                      style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.border),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12))))),
            ]),
          const SizedBox(height: 20),

          // Terms
          GestureDetector(
              onTap: () => setState(() => _agreeToTerms = !_agreeToTerms),
              child: Row(children: [
                Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                        color:
                            _agreeToTerms ? AppColors.gold : AppColors.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: _agreeToTerms
                                ? AppColors.gold
                                : AppColors.border)),
                    child: _agreeToTerms
                        ? const Icon(Icons.check_rounded,
                            color: AppColors.primary, size: 16)
                        : null),
                const SizedBox(width: 10),
                const Expanded(
                    child: Text.rich(TextSpan(
                        text: 'I agree to the ',
                        style:
                            TextStyle(color: AppColors.textMuted, fontSize: 13),
                        children: [
                      TextSpan(
                          text: 'Terms of Service',
                          style: TextStyle(
                              color: AppColors.gold,
                              fontWeight: FontWeight.w600)),
                      TextSpan(text: ' and '),
                      TextSpan(
                          text: 'Privacy Policy',
                          style: TextStyle(
                              color: AppColors.gold,
                              fontWeight: FontWeight.w600)),
                    ]))),
              ])),
          const SizedBox(height: 24),

          SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                  onPressed:
                      (auth.loading || _uploadingDoc) ? null : _register,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14))),
                  child: (auth.loading || _uploadingDoc)
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              color: AppColors.primary, strokeWidth: 2))
                      : const Text('Create Account',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary)))),
          const SizedBox(height: 16),

          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('Already have an account? ',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            GestureDetector(
                onTap: () => context.go('/login'),
                child: const Text('Sign In',
                    style: TextStyle(
                        color: AppColors.gold,
                        fontSize: 13,
                        fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscure = false,
    bool isPhone = false,
    VoidCallback? onToggleObscure,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscure,
      style: const TextStyle(color: AppColors.textPrimary),
      validator: validator,
      onChanged: onChanged,
      // ✅ Block more than 10 digits for phone
      inputFormatters: isPhone
          ? [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10)
            ]
          : null,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textMuted),
        prefixIcon: Icon(icon, color: AppColors.gold, size: 20),
        suffixIcon: onToggleObscure != null
            ? IconButton(
                icon: Icon(obscure ? Icons.visibility_off : Icons.visibility,
                    color: AppColors.textMuted, size: 20),
                onPressed: onToggleObscure)
            : null,
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
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.error)),
      ),
    );
  }
}
