import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../providers/auth_provider.dart';

class ClientRegisterScreen extends StatefulWidget {
  const ClientRegisterScreen({super.key});
  @override
  State<ClientRegisterScreen> createState() => _ClientRegisterScreenState();
}

class _ClientRegisterScreenState extends State<ClientRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _agreeToTerms = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreeToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Please agree to Terms & Conditions'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
      return;
    }
    if (_passwordCtrl.text != _confirmCtrl.text) {
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
    final success = await auth.clientRegister(
        name: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        password: _passwordCtrl.text);
    if (success && mounted) {
      HapticFeedback.heavyImpact();
      context.go('/portal/dashboard');
    } else if (mounted) {
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
          title: const Text('Create Client Account',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
      body: Form(
        key: _formKey,
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.info.withValues(alpha: 0.3))),
              child: const Row(children: [
                Icon(Icons.person_rounded, color: AppColors.info, size: 32),
                SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('Client Registration',
                          style: TextStyle(
                              color: AppColors.info,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                      Text('Create your account to access your cases',
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 12)),
                    ])),
              ])),
          const SizedBox(height: 24),

          TextFormField(
              controller: _nameCtrl,
              style: const TextStyle(color: AppColors.textPrimary),
              validator: (v) => v!.isEmpty ? 'Name is required' : null,
              decoration:
                  _deco('Full Name *', Icons.person_rounded, AppColors.info)),
          const SizedBox(height: 14),

          TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: AppColors.textPrimary),
              validator: (v) {
                if (v!.isEmpty) return 'Email is required';
                if (!v.contains('@')) return 'Enter valid email';
                return null;
              },
              decoration: _deco(
                  'Email Address *', Icons.email_outlined, AppColors.info)),
          const SizedBox(height: 14),

          // ✅ Phone - 10 digits only
          TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: AppColors.textPrimary),
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10)
              ],
              validator: (v) {
                if (v!.isEmpty) return 'Phone is required';
                if (v.length != 10) return 'Enter valid 10-digit number';
                return null;
              },
              decoration: _deco(
                  'Phone Number *', Icons.phone_outlined, AppColors.info)),
          const SizedBox(height: 14),

          TextFormField(
              controller: _passwordCtrl,
              obscureText: _obscurePass,
              style: const TextStyle(color: AppColors.textPrimary),
              validator: (v) => v!.length < 6 ? 'Minimum 6 characters' : null,
              decoration: _deco(
                  'Password *', Icons.lock_outline, AppColors.info,
                  suffixIcon: IconButton(
                      icon: Icon(
                          _obscurePass
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: AppColors.textMuted,
                          size: 20),
                      onPressed: () =>
                          setState(() => _obscurePass = !_obscurePass)))),
          const SizedBox(height: 14),

          TextFormField(
              controller: _confirmCtrl,
              obscureText: _obscureConfirm,
              style: const TextStyle(color: AppColors.textPrimary),
              validator: (v) => v!.isEmpty ? 'Please confirm password' : null,
              decoration: _deco(
                  'Confirm Password *', Icons.lock_outline, AppColors.info,
                  suffixIcon: IconButton(
                      icon: Icon(
                          _obscureConfirm
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: AppColors.textMuted,
                          size: 20),
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm)))),
          const SizedBox(height: 20),

          GestureDetector(
              onTap: () => setState(() => _agreeToTerms = !_agreeToTerms),
              child: Row(children: [
                Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                        color:
                            _agreeToTerms ? AppColors.info : AppColors.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: _agreeToTerms
                                ? AppColors.info
                                : AppColors.border)),
                    child: _agreeToTerms
                        ? const Icon(Icons.check_rounded,
                            color: Colors.white, size: 16)
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
                              color: AppColors.info,
                              fontWeight: FontWeight.w600)),
                      TextSpan(text: ' and '),
                      TextSpan(
                          text: 'Privacy Policy',
                          style: TextStyle(
                              color: AppColors.info,
                              fontWeight: FontWeight.w600)),
                    ]))),
              ])),
          const SizedBox(height: 24),

          SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                  onPressed: auth.loading ? null : _register,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.info,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14))),
                  child: auth.loading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Text('Create Account',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)))),
          const SizedBox(height: 16),

          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('Already have an account? ',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            GestureDetector(
                onTap: () => context.go('/login'),
                child: const Text('Sign In',
                    style: TextStyle(
                        color: AppColors.info,
                        fontSize: 13,
                        fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  InputDecoration _deco(String label, IconData icon, Color accent,
          {Widget? suffixIcon}) =>
      InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: AppColors.textMuted),
          prefixIcon: Icon(icon, color: accent, size: 20),
          suffixIcon: suffixIcon,
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
              borderSide: BorderSide(color: accent)),
          errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.error)));
}
