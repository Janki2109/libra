import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/dio_client.dart';

/// Forgot Password — Email -> OTP -> New Password, all three steps verified
/// server-side against the existing otps table (backend/controllers/
/// auth_controller.go: ForgotPassword, VerifyPasswordResetOTP,
/// ResetPassword), reusing the same SMTP mailer and password hashing the
/// rest of auth already uses. Works identically for lawyer, client and
/// student accounts since the backend isn't role-specific here. Nothing here
/// is a local/fake reset — every step is a real API call, and the OTP itself
/// is never shown in this app, only emailed.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

enum _Step { email, otp, newPassword, done }

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  _Step _step = _Step.email;
  bool _loading = false;
  String? _error;
  String _email = '';

  final _emailCtrl = TextEditingController();
  final _otpCtrls = List.generate(6, (_) => TextEditingController());
  final _otpNodes = List.generate(6, (_) => FocusNode());
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  // Resend cooldown — the backend's otpLimiter (5 requests / 15 min) is the
  // real rate limit; this is just so the button itself doesn't invite
  // spamming taps in the meantime.
  int _resendSeconds = 0;
  Timer? _resendTimer;

  String get _otp => _otpCtrls.map((c) => c.text).join();

  @override
  void dispose() {
    _emailCtrl.dispose();
    for (final c in _otpCtrls) c.dispose();
    for (final n in _otpNodes) n.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        _resendSeconds--;
        if (_resendSeconds <= 0) t.cancel();
      });
    });
  }

  Future<void> _sendCode() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter a valid email address');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await DioClient.instance.post('/auth/forgot-password', data: {'email': email});
      if (!mounted) return;
      setState(() {
        _email = email;
        _step = _Step.otp;
        _loading = false;
      });
      _startResendCooldown();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = DioClient.describeError(e);
      });
    }
  }

  Future<void> _verifyOtp() async {
    if (_otp.length < 6) {
      setState(() => _error = 'Enter all 6 digits');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await DioClient.instance.post('/auth/forgot-password/verify-otp',
          data: {'email': _email, 'otp': _otp});
      if (!mounted) return;
      setState(() {
        _step = _Step.newPassword;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = DioClient.describeError(e);
      });
    }
  }

  Future<void> _resetPassword() async {
    if (_newPassCtrl.text.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters');
      return;
    }
    if (_newPassCtrl.text != _confirmPassCtrl.text) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // The OTP is re-verified server-side here too (see ResetPassword on
      // the backend) — the earlier "Code verified" step never issues a
      // token that alone would let this call skip re-checking it.
      await DioClient.instance.post('/auth/reset-password', data: {
        'email': _email,
        'otp': _otp,
        'new_password': _newPassCtrl.text,
      });
      if (!mounted) return;
      setState(() {
        _step = _Step.done;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = DioClient.describeError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.primaryDark,
        title: const Text('Reset Password',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: switch (_step) {
            _Step.email => _buildEmailStep(),
            _Step.otp => _buildOtpStep(),
            _Step.newPassword => _buildNewPasswordStep(),
            _Step.done => _buildDoneStep(),
          },
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    if (_error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.error.withValues(alpha: 0.3))),
        child: Row(children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Text(_error!,
                  style: const TextStyle(color: AppColors.error, fontSize: 13))),
        ]),
      ),
    );
  }

  Widget _buildEmailStep() {
    return Column(children: [
      const SizedBox(height: 12),
      Container(
        width: 72,
        height: 72,
        decoration: const BoxDecoration(
            gradient: AppColors.goldGradient, shape: BoxShape.circle),
        child: const Icon(Icons.lock_reset_rounded, color: AppColors.primary, size: 32),
      ),
      const SizedBox(height: 20),
      const Text('Forgot Password?',
          style: TextStyle(
              color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      const Text(
          'Enter your registered email address. We\'ll send a verification code to reset your password.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
      const SizedBox(height: 28),
      _buildErrorBanner(),
      TextField(
        controller: _emailCtrl,
        keyboardType: TextInputType.emailAddress,
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: InputDecoration(
          labelText: 'Email Address',
          labelStyle: const TextStyle(color: AppColors.textMuted),
          prefixIcon: const Icon(Icons.email_outlined, color: AppColors.gold, size: 20),
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
        ),
        onSubmitted: (_) => _sendCode(),
      ),
      const SizedBox(height: 24),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _loading ? null : _sendCode,
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2))
              : const Text('Send Code',
                  style: TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 16)),
        ),
      ),
    ]);
  }

  Widget _buildOtpStep() {
    return Column(children: [
      const SizedBox(height: 12),
      Container(
        width: 72,
        height: 72,
        decoration: const BoxDecoration(
            gradient: AppColors.goldGradient, shape: BoxShape.circle),
        child: const Icon(Icons.mark_email_read_rounded, color: AppColors.primary, size: 32),
      ),
      const SizedBox(height: 20),
      const Text('Enter Code',
          style: TextStyle(
              color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Text('Enter the 6-digit code sent to $_email',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
      const SizedBox(height: 28),
      _buildErrorBanner(),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(
            6,
            (i) => _OtpBox(
                  controller: _otpCtrls[i],
                  focusNode: _otpNodes[i],
                  onChanged: (v) {
                    if (v.length == 1 && i < 5) {
                      _otpNodes[i + 1].requestFocus();
                    } else if (v.isEmpty && i > 0) {
                      _otpNodes[i - 1].requestFocus();
                    }
                    setState(() {});
                  },
                )),
      ),
      const SizedBox(height: 20),
      TextButton(
        onPressed: _resendSeconds > 0 || _loading ? null : _sendCode,
        child: Text(
            _resendSeconds > 0 ? 'Resend code in ${_resendSeconds}s' : 'Resend Code',
            style: TextStyle(
                color: _resendSeconds > 0 ? AppColors.textMuted : AppColors.gold,
                fontWeight: FontWeight.w600)),
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _loading ? null : _verifyOtp,
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2))
              : const Text('Verify Code',
                  style: TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 16)),
        ),
      ),
    ]);
  }

  Widget _buildNewPasswordStep() {
    return Column(children: [
      const SizedBox(height: 12),
      Container(
        width: 72,
        height: 72,
        decoration: const BoxDecoration(
            gradient: AppColors.goldGradient, shape: BoxShape.circle),
        child: const Icon(Icons.password_rounded, color: AppColors.primary, size: 32),
      ),
      const SizedBox(height: 20),
      const Text('Set New Password',
          style: TextStyle(
              color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      const Text('Choose a new password for your account.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
      const SizedBox(height: 28),
      _buildErrorBanner(),
      TextField(
        controller: _newPassCtrl,
        obscureText: _obscureNew,
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: InputDecoration(
          labelText: 'New Password',
          labelStyle: const TextStyle(color: AppColors.textMuted),
          prefixIcon: const Icon(Icons.lock_outline, color: AppColors.gold, size: 20),
          suffixIcon: IconButton(
              icon: Icon(_obscureNew ? Icons.visibility_off : Icons.visibility,
                  color: AppColors.textMuted, size: 20),
              onPressed: () => setState(() => _obscureNew = !_obscureNew)),
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
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _confirmPassCtrl,
        obscureText: _obscureConfirm,
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: InputDecoration(
          labelText: 'Confirm New Password',
          labelStyle: const TextStyle(color: AppColors.textMuted),
          prefixIcon: const Icon(Icons.lock_outline, color: AppColors.gold, size: 20),
          suffixIcon: IconButton(
              icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility,
                  color: AppColors.textMuted, size: 20),
              onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm)),
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
        ),
        onSubmitted: (_) => _resetPassword(),
      ),
      const SizedBox(height: 24),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _loading ? null : _resetPassword,
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2))
              : const Text('Reset Password',
                  style: TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 16)),
        ),
      ),
    ]);
  }

  Widget _buildDoneStep() {
    return Column(children: [
      const SizedBox(height: 40),
      Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.15), shape: BoxShape.circle),
        child: const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 44),
      ),
      const SizedBox(height: 20),
      const Text('Password Reset!',
          style: TextStyle(
              color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      const Text('Your password has been updated. You can now sign in with your new password.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
      const SizedBox(height: 28),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => context.go('/login'),
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: const Text('Back to Login',
              style: TextStyle(
                  color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 16)),
        ),
      ),
    ]);
  }
}

class _OtpBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  const _OtpBox(
      {required this.controller, required this.focusNode, required this.onChanged});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 44,
        child: TextFormField(
          controller: controller,
          focusNode: focusNode,
          maxLength: 1,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          onChanged: onChanged,
          style: const TextStyle(
              color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.gold, width: 2)),
          ),
        ),
      );
}
