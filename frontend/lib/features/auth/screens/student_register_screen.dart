import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/validators.dart';
import '../providers/auth_provider.dart';

class StudentRegisterScreen extends StatefulWidget {
  const StudentRegisterScreen({super.key});
  @override
  State<StudentRegisterScreen> createState() => _StudentRegisterScreenState();
}

class _StudentRegisterScreenState extends State<StudentRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _collegeCtrl = TextEditingController();
  String _year = '1st Year';
  bool _obscurePass = true;
  bool _obscureConfirm = true;

  final List<String> _years = [
    '1st Year',
    '2nd Year',
    '3rd Year',
    '4th Year',
    '5th Year',
    'LLM',
    'PhD'
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _collegeCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
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
    final success = await auth.studentRegister(
        name: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        password: _passwordCtrl.text,
        collegeName: _collegeCtrl.text.trim(),
        year: _year);
    if (success && mounted) {
      HapticFeedback.heavyImpact();
      context.go('/student/dashboard');
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
          title: const Text('Student Registration',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
      body: Form(
        key: _formKey,
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: AppColors.purple.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.purple.withValues(alpha: 0.3))),
              child: const Row(children: [
                Icon(Icons.school_rounded, color: AppColors.purple, size: 32),
                SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('Law Student Account',
                          style: TextStyle(
                              color: AppColors.purple,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                      Text('Get access to case studies, quizzes & legal news',
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 11)),
                    ])),
              ])),
          const SizedBox(height: 24),

          _buildField(_nameCtrl, 'Full Name *', Icons.person_rounded,
              validator: (v) => v!.isEmpty ? 'Required' : null),
          const SizedBox(height: 14),

          _buildField(_emailCtrl, 'Email Address *', Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              validator: (v) => v!.isEmpty ? 'Required' : null),
          const SizedBox(height: 14),

          // ✅ Phone - 10 digits only
          _buildField(_phoneCtrl, 'Phone Number *', Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              isPhone: true,
              validator: (v) => Validators.phone(v)),
          const SizedBox(height: 14),

          _buildField(_collegeCtrl, 'College / University Name *',
              Icons.account_balance_rounded,
              validator: (v) => v!.isEmpty ? 'Required' : null),
          const SizedBox(height: 14),

          Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border)),
              child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                      value: _year,
                      dropdownColor: AppColors.surface,
                      style: const TextStyle(color: AppColors.textPrimary),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded,
                          color: AppColors.purple),
                      isExpanded: true,
                      items: _years
                          .map(
                              (y) => DropdownMenuItem(value: y, child: Text(y)))
                          .toList(),
                      onChanged: (v) => setState(() => _year = v!)))),
          const SizedBox(height: 14),

          _buildField(_passwordCtrl, 'Password *', Icons.lock_outline,
              obscure: _obscurePass,
              onToggle: () => setState(() => _obscurePass = !_obscurePass),
              validator: (v) => v!.length < 6 ? 'Min 6 characters' : null),
          const SizedBox(height: 14),

          _buildField(_confirmCtrl, 'Confirm Password *', Icons.lock_outline,
              obscure: _obscureConfirm,
              onToggle: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
              validator: (v) => v!.isEmpty ? 'Required' : null),
          const SizedBox(height: 24),

          SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                  onPressed: auth.loading ? null : _register,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.purple,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14))),
                  child: auth.loading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Text('Create Student Account',
                          style: TextStyle(
                              fontSize: 15,
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
                        color: AppColors.purple,
                        fontSize: 13,
                        fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  Widget _buildField(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    TextInputType? keyboardType,
    bool obscure = false,
    bool isPhone = false,
    VoidCallback? onToggle,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
        controller: ctrl,
        keyboardType: keyboardType,
        obscureText: obscure,
        style: const TextStyle(color: AppColors.textPrimary),
        validator: validator,
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
            prefixIcon: Icon(icon, color: AppColors.purple, size: 20),
            suffixIcon: onToggle != null
                ? IconButton(
                    icon: Icon(
                        obscure ? Icons.visibility_off : Icons.visibility,
                        color: AppColors.textMuted,
                        size: 20),
                    onPressed: onToggle)
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
                borderSide: const BorderSide(color: AppColors.purple)),
            errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.error))));
  }
}
