import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
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
  final _idProofNumCtrl = TextEditingController();
  String _idProofType = 'Aadhaar';
  bool _loading = false;

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
    _idProofNumCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.lightImpact();
    setState(() => _loading = true);

    final result = await context.read<ClientProvider>().addClientWithPortal({
      'name': _nameCtrl.text.trim(),
      'email': _emailCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'alternate_phone': _altPhoneCtrl.text.trim(),
      'address': _addressCtrl.text.trim(),
      'city': _cityCtrl.text.trim(),
      'state': _stateCtrl.text.trim(),
      'pincode': _pincodeCtrl.text.trim(),
      'id_proof_type': _idProofType,
      'id_proof_number': _idProofNumCtrl.text.trim(),
      'notes': _notesCtrl.text.trim(),
    });

    setState(() => _loading = false);

    if (result != null && mounted) {
      HapticFeedback.heavyImpact();
      if (result['portal_created'] == true) {
        // The API no longer returns the generated password — it emails it to
        // the client directly. It used to come back here and also get written
        // verbatim into a notifications row, leaving a plaintext credential
        // in the database permanently.
        _showPortalCreated(email: result['portal_email'] ?? '');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Client added successfully!'),
          backgroundColor: const Color(0xFF2E8B57),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
        context.pop();
      }
    } else if (mounted) {
      HapticFeedback.vibrate();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Failed to add client'),
        backgroundColor: const Color(0xFFD9534F),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  /// Confirms the portal account was created.
  ///
  /// This used to display the generated password on screen with a "Copy
  /// Credentials" button. The API now emails it to the client instead, so the
  /// credential never travels back through the lawyer's device, never lands in
  /// their clipboard, and is not recoverable from a screenshot.
  void _showPortalCreated({required String email}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: _bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.check_circle_rounded, color: Color(0xFF2E8B57), size: 24),
          SizedBox(width: 10),
          Expanded(
            child: Text('Client Account Created',
                style: TextStyle(
                    color: _textPri,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
          ),
        ]),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Sign-in details have been emailed to your client. They will '
                  'be asked to choose their own password on first sign-in.',
                  style:
                      TextStyle(color: _textMuted, fontSize: 13, height: 1.5)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border),
                ),
                child: Row(children: [
                  const Icon(Icons.email_outlined, color: _gold, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(email,
                          style: const TextStyle(
                              color: _textPri,
                              fontWeight: FontWeight.w600,
                              fontSize: 13))),
                ]),
              ),
            ]),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              context.pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _brown,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Done',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
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
          Positioned.fill(
              child: Opacity(
                  opacity: 0.50,
                  child: Image.asset('assets/imagies1/add cilent images.png',
                      fit: BoxFit.cover))),
          Positioned.fill(
              child: Opacity(
                  opacity: 0.50,
                  child: Image.asset('assets/imagies1/add cilent images.png',
                      fit: BoxFit.cover))),
          // ent background ──
          Positioned.fill(child: CustomPaint(painter: _ParchmentPainter())),

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
                    // Info banner
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4A90D9).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: const Color(0xFF4A90D9)
                                .withValues(alpha: 0.25)),
                      ),
                      child: const Row(children: [
                        Icon(Icons.info_outline_rounded,
                            color: Color(0xFF4A90D9), size: 18),
                        SizedBox(width: 10),
                        Expanded(
                            child: Text(
                          'Client portal account will be automatically created when you add email address!',
                          style: TextStyle(
                              color: Color(0xFF2E6DB4),
                              fontSize: 12,
                              height: 1.4),
                        )),
                      ]),
                    ),
                    const SizedBox(height: 20),

                    _SectionHeader(
                        title: 'Personal Information',
                        icon: Icons.person_outline_rounded),
                    const SizedBox(height: 12),
                    _buildField(
                        controller: _nameCtrl,
                        label: 'Full Name *',
                        icon: Icons.person_rounded,
                        validator: (v) =>
                            v!.isEmpty ? 'Name is required' : null),
                    const SizedBox(height: 10),
                    _buildField(
                        controller: _emailCtrl,
                        label: 'Email Address (for portal access)',
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                          child: _buildField(
                              controller: _phoneCtrl,
                              label: 'Phone Number',
                              icon: Icons.phone_outlined,
                              keyboardType: TextInputType.phone)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _buildField(
                              controller: _altPhoneCtrl,
                              label: 'Alternate Phone',
                              icon: Icons.phone_outlined,
                              keyboardType: TextInputType.phone)),
                    ]),
                    const SizedBox(height: 20),

                    _SectionHeader(
                        title: 'Address Details',
                        icon: Icons.location_on_outlined),
                    const SizedBox(height: 12),
                    _buildField(
                        controller: _addressCtrl,
                        label: 'Full Address',
                        icon: Icons.home_outlined,
                        maxLines: 2),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                          child: _buildField(
                              controller: _cityCtrl,
                              label: 'City',
                              icon: Icons.location_city_outlined)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _buildField(
                              controller: _stateCtrl,
                              label: 'State',
                              icon: Icons.map_outlined)),
                    ]),
                    const SizedBox(height: 10),
                    _buildField(
                        controller: _pincodeCtrl,
                        label: 'Pincode',
                        icon: Icons.pin_outlined,
                        keyboardType: TextInputType.number),
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
                    _buildField(
                        controller: _idProofNumCtrl,
                        label: 'ID Proof Number',
                        icon: Icons.numbers_outlined),
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
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
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

// ── Parchment / Writing Background Painter ─────────
class _ParchmentPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = const Color(0xFF3D2C8D).withValues(alpha: 0.06)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    // Horizontal ruled lines like parchment paper
    for (double y = 60; y < size.height; y += 28) {
      canvas.drawLine(Offset(20, y), Offset(size.width - 20, y), linePaint);
    }

    // Left red margin line like legal paper
    final marginPaint = Paint()
      ..color = const Color(0xFF3D2C8D).withValues(alpha: 0.1)
      ..strokeWidth = 1.2;
    canvas.drawLine(const Offset(44, 0), Offset(44, size.height), marginPaint);

    // Faded scales of justice watermark center
    _drawScalesWatermark(canvas, size);

    // Faded "LEGAL DOCUMENT" text-like strokes top right
    _drawLegalStrokes(canvas, size);
  }

  void _drawScalesWatermark(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF150E3D).withValues(alpha: 0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final cx = size.width * 0.75;
    final cy = size.height * 0.38;
    final s = size.width * 0.18;

    // Center rod
    canvas.drawLine(Offset(cx, cy - s * 0.9), Offset(cx, cy + s * 0.15), paint);
    // Horizontal bar
    canvas.drawLine(Offset(cx - s, cy), Offset(cx + s, cy), paint);

    // Left pan strings + pan
    canvas.drawLine(
        Offset(cx - s, cy), Offset(cx - s * 1.35, cy + s * 0.85), paint);
    canvas.drawLine(
        Offset(cx - s, cy), Offset(cx - s * 0.65, cy + s * 0.85), paint);
    canvas.drawArc(
        Rect.fromCenter(
            center: Offset(cx - s, cy + s * 0.85),
            width: s * 0.7,
            height: s * 0.22),
        math.pi,
        math.pi,
        false,
        paint);

    // Right pan strings + pan
    canvas.drawLine(
        Offset(cx + s, cy), Offset(cx + s * 1.35, cy + s * 0.75), paint);
    canvas.drawLine(
        Offset(cx + s, cy), Offset(cx + s * 0.65, cy + s * 0.75), paint);
    canvas.drawArc(
        Rect.fromCenter(
            center: Offset(cx + s, cy + s * 0.75),
            width: s * 0.7,
            height: s * 0.22),
        math.pi,
        math.pi,
        false,
        paint);

    // Base/stand
    canvas.drawLine(Offset(cx - s * 0.3, cy + s * 0.15),
        Offset(cx + s * 0.3, cy + s * 0.15), paint);
    canvas.drawLine(
        Offset(cx, cy + s * 0.15), Offset(cx, cy + s * 0.55), paint);
    canvas.drawLine(Offset(cx - s * 0.25, cy + s * 0.55),
        Offset(cx + s * 0.25, cy + s * 0.55), paint);

    // Crown on top
    final crownPath = Path();
    crownPath.moveTo(cx - s * 0.18, cy - s * 0.9);
    crownPath.lineTo(cx - s * 0.12, cy - s * 1.05);
    crownPath.lineTo(cx - s * 0.04, cy - s * 0.95);
    crownPath.lineTo(cx, cy - s * 1.1);
    crownPath.lineTo(cx + s * 0.04, cy - s * 0.95);
    crownPath.lineTo(cx + s * 0.12, cy - s * 1.05);
    crownPath.lineTo(cx + s * 0.18, cy - s * 0.9);
    canvas.drawPath(crownPath, paint);
  }

  void _drawLegalStrokes(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF150E3D).withValues(alpha: 0.035)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Simulate faded handwriting lines top area
    final rand = math.Random(42);
    for (int i = 0; i < 6; i++) {
      final y = 80.0 + i * 22;
      final startX = 60.0 + rand.nextDouble() * 20;
      final endX = size.width * 0.55 + rand.nextDouble() * 40;
      final path = Path();
      path.moveTo(startX, y);
      for (double x = startX + 10; x < endX; x += 8) {
        path.cubicTo(
          x,
          y - rand.nextDouble() * 3,
          x + 4,
          y + rand.nextDouble() * 3,
          x + 8,
          y,
        );
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
