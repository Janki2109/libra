import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/services/dio_client.dart';
import '../../clients/providers/client_provider.dart';

const _bg = Color(0xFFF6F5FB);
const _bgCard = Color(0xFFFFFFFF);
const _brown = Color(0xFF150E3D);
const _border = Color(0xFFE6E3F4);
const _textPri = Color(0xFF2C1A0E);
const _textMuted = Color(0xFF3D2C8D);

class AddCaseScreen extends StatefulWidget {
  const AddCaseScreen({super.key});
  @override
  State<AddCaseScreen> createState() => _AddCaseScreenState();
}

class _AddCaseScreenState extends State<AddCaseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _caseNumCtrl = TextEditingController();
  final _courtNameCtrl = TextEditingController();
  final _courtLocationCtrl = TextEditingController();
  final _judgeNameCtrl = TextEditingController();
  final _oppositePartyCtrl = TextEditingController();
  final _oppLawyerCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String? _selectedClientId;
  String? _selectedClientName;
  String _caseType = 'Civil';
  String _priority = 'Normal';
  bool _loading = false;

  final List<String> _caseTypes = [
    'Civil',
    'Criminal',
    'Family',
    'Property',
    'Corporate',
    'Labour',
    'Tax',
    'Constitutional',
    'Other'
  ];
  final List<String> _priorities = ['Low', 'Normal', 'High', 'Urgent'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.read<ClientProvider>().loadClients());
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _caseNumCtrl.dispose();
    _courtNameCtrl.dispose();
    _courtLocationCtrl.dispose();
    _judgeNameCtrl.dispose();
    _oppositePartyCtrl.dispose();
    _oppLawyerCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.lightImpact();
    setState(() => _loading = true);
    try {
      await DioClient.instance.post('/cases', data: {
        'client_id': _selectedClientId ?? '',
        'case_title': _titleCtrl.text.trim(),
        'case_number': _caseNumCtrl.text.trim(),
        'case_type': _caseType,
        'court_name': _courtNameCtrl.text.trim(),
        'court_location': _courtLocationCtrl.text.trim(),
        'judge_name': _judgeNameCtrl.text.trim(),
        'opposite_party': _oppositePartyCtrl.text.trim(),
        'opposite_lawyer': _oppLawyerCtrl.text.trim(),
        'priority': _priority.toLowerCase(),
        'description': _descCtrl.text.trim(),
      });
      if (mounted) {
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_selectedClientId != null
              ? 'Case created! ${_selectedClientName ?? 'Client'} can see it in their portal!'
              : 'Case created successfully!'),
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
          content: const Text('Failed to create case'),
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
        body: Stack(children: [
          // ── Faded background image ──────────────
          Positioned.fill(
            child: Opacity(
              opacity: 0.50,
              child: Image.asset(
                'assets/imagies1/wrting case image.webp',
                fit: BoxFit.cover,
              ),
            ),
          ),
          // ── Parchment overlay lines ──────────────
          Positioned.fill(child: CustomPaint(painter: _ParchmentPainter())),
          Column(children: [
            // Brown AppBar
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
                          child: Text('Add New Case',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700))),
                      TextButton(
                          onPressed: _loading ? null : _submit,
                          child: const Text('Save',
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
                // Client Selection
                _SectionHeader(
                    title: 'Select Client', icon: Icons.person_rounded),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4A90D9).withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFF4A90D9).withValues(alpha: 0.2)),
                  ),
                  child: const Row(children: [
                    Icon(Icons.info_outline_rounded,
                        color: Color(0xFF4A90D9), size: 16),
                    SizedBox(width: 8),
                    Expanded(
                        child: Text(
                            'Select a client to automatically share this case in their portal!',
                            style: TextStyle(
                                color: Color(0xFF2E6DB4),
                                fontSize: 11,
                                height: 1.4))),
                  ]),
                ),
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                  decoration: BoxDecoration(
                    color: _bgCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _selectedClientId != null ? _brown : _border,
                        width: _selectedClientId != null ? 1.5 : 0.8),
                    boxShadow: [
                      BoxShadow(
                          color: _brown.withValues(alpha: 0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 2))
                    ],
                  ),
                  child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                    value: _selectedClientId,
                    hint: const Text('No client selected',
                        style: TextStyle(color: _textMuted, fontSize: 13)),
                    dropdownColor: _bgCard,
                    style: const TextStyle(color: _textPri, fontSize: 14),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: _brown),
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem<String>(
                          value: null,
                          child: Text('No client selected',
                              style: TextStyle(color: _textMuted))),
                      ...clients.map<DropdownMenuItem<String>>(
                          (cl) => DropdownMenuItem(
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
                                                  ? cl['name'][0].toUpperCase()
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
                                        if ((cl['email'] ?? '').isNotEmpty)
                                          Text(cl['email'],
                                              style: const TextStyle(
                                                  color: _textMuted,
                                                  fontSize: 11)),
                                      ])),
                                  if ((cl['email'] ?? '').isNotEmpty)
                                    const Icon(Icons.verified_rounded,
                                        color: Color(0xFF2E8B57), size: 14),
                                ]),
                              )),
                    ],
                    onChanged: (v) => setState(() {
                      _selectedClientId = v;
                      if (v != null) {
                        final cl = clients.firstWhere((c) => c['id'] == v,
                            orElse: () => {});
                        _selectedClientName = cl['name'];
                      } else {
                        _selectedClientName = null;
                      }
                    }),
                  )),
                ),
                if (_selectedClientId != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E8B57).withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: const Color(0xFF2E8B57).withValues(alpha: 0.3)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.check_circle_rounded,
                          color: Color(0xFF2E8B57), size: 15),
                      const SizedBox(width: 8),
                      Text(
                          '$_selectedClientName will see this case in their portal!',
                          style: const TextStyle(
                              color: Color(0xFF2E8B57), fontSize: 11)),
                    ]),
                  ),
                ],
                const SizedBox(height: 20),

                _SectionHeader(
                    title: 'Case Details', icon: Icons.gavel_rounded),
                const SizedBox(height: 12),
                _buildField(_titleCtrl, 'Case Title *', Icons.title_rounded,
                    validator: (v) => v!.isEmpty ? 'Title required' : null),
                const SizedBox(height: 10),
                _buildField(_caseNumCtrl, 'Case Number', Icons.numbers_rounded),
                const SizedBox(height: 10),
                _buildDropdown(
                    label: 'Case Type',
                    value: _caseType,
                    items: _caseTypes,
                    onChanged: (v) => setState(() => _caseType = v!)),
                const SizedBox(height: 10),
                _buildDropdown(
                    label: 'Priority',
                    value: _priority,
                    items: _priorities,
                    onChanged: (v) => setState(() => _priority = v!),
                    accentColor: _priority == 'Urgent'
                        ? const Color(0xFFD9534F)
                        : _priority == 'High'
                            ? const Color(0xFFD4A017)
                            : _brown),
                const SizedBox(height: 20),

                _SectionHeader(
                    title: 'Court Details',
                    icon: Icons.account_balance_rounded),
                const SizedBox(height: 12),
                _buildField(_courtNameCtrl, 'Court Name',
                    Icons.account_balance_rounded),
                const SizedBox(height: 10),
                _buildField(_courtLocationCtrl, 'Court Location',
                    Icons.location_on_outlined),
                const SizedBox(height: 10),
                _buildField(
                    _judgeNameCtrl, 'Judge Name', Icons.person_outlined),
                const SizedBox(height: 20),

                _SectionHeader(
                    title: 'Opposite Party', icon: Icons.people_rounded),
                const SizedBox(height: 12),
                _buildField(_oppositePartyCtrl, 'Opposite Party Name',
                    Icons.person_outline_rounded),
                const SizedBox(height: 10),
                _buildField(
                    _oppLawyerCtrl, 'Opposite Lawyer', Icons.gavel_rounded),
                const SizedBox(height: 20),

                _SectionHeader(
                    title: 'Description', icon: Icons.description_rounded),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descCtrl,
                  maxLines: 4,
                  style: const TextStyle(color: _textPri, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Case description...',
                    hintStyle: const TextStyle(color: _textMuted, fontSize: 13),
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
                        elevation: 0),
                    child: _loading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text('Create Case',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white)),
                  ),
                ),
                const SizedBox(height: 40),
              ]),
            )),
          ]),
        ]),
      ),
    );
  }

  Widget _buildField(TextEditingController ctrl, String label, IconData icon,
      {String? Function(String?)? validator}) {
    return TextFormField(
      controller: ctrl,
      validator: validator,
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
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFD9534F))),
      ),
    );
  }

  Widget _buildDropdown(
      {required String label,
      required String value,
      required List<String> items,
      required void Function(String?) onChanged,
      Color accentColor = _brown}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
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
      child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
        value: value,
        dropdownColor: _bgCard,
        style: TextStyle(color: accentColor, fontSize: 14),
        icon: Icon(Icons.keyboard_arrow_down_rounded, color: accentColor),
        isExpanded: true,
        items: items
            .map((i) => DropdownMenuItem(
                value: i,
                child: Text(i, style: const TextStyle(color: _textPri))))
            .toList(),
        onChanged: onChanged,
      )),
    );
  }
}

class _ParchmentPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final lp = Paint()
      ..color = const Color(0xFF3D2C8D).withValues(alpha: 0.05)
      ..strokeWidth = 0.7
      ..style = PaintingStyle.stroke;
    for (double y = 60; y < size.height; y += 28)
      canvas.drawLine(Offset(20, y), Offset(size.width - 20, y), lp);
    final mp = Paint()
      ..color = const Color(0xFF3D2C8D).withValues(alpha: 0.09)
      ..strokeWidth = 1.0;
    canvas.drawLine(const Offset(44, 0), Offset(44, size.height), mp);
    final wp = Paint()
      ..color = const Color(0xFF150E3D).withValues(alpha: 0.04)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;
    final cx = size.width * 0.82;
    final cy = size.height * 0.42;
    final s = size.width * 0.14;
    canvas.drawLine(Offset(cx, cy - s * 0.9), Offset(cx, cy + s * 0.2), wp);
    canvas.drawLine(Offset(cx - s, cy), Offset(cx + s, cy), wp);
    canvas.drawLine(
        Offset(cx - s, cy), Offset(cx - s * 1.35, cy + s * 0.85), wp);
    canvas.drawLine(
        Offset(cx - s, cy), Offset(cx - s * 0.65, cy + s * 0.85), wp);
    canvas.drawArc(
        Rect.fromCenter(
            center: Offset(cx - s, cy + s * 0.85),
            width: s * 0.7,
            height: s * 0.22),
        math.pi,
        math.pi,
        false,
        wp);
    canvas.drawLine(
        Offset(cx + s, cy), Offset(cx + s * 1.35, cy + s * 0.75), wp);
    canvas.drawLine(
        Offset(cx + s, cy), Offset(cx + s * 0.65, cy + s * 0.75), wp);
    canvas.drawArc(
        Rect.fromCenter(
            center: Offset(cx + s, cy + s * 0.75),
            width: s * 0.7,
            height: s * 0.22),
        math.pi,
        math.pi,
        false,
        wp);
  }

  @override
  bool shouldRepaint(covariant CustomPainter o) => false;
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
