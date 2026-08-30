import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/services/dio_client.dart';
import '../../cases/providers/case_provider.dart';

const _bg = Color(0xFFF6F5FB);
const _bgCard = Color(0xFFFFFFFF);
const _brown = Color(0xFF150E3D);
const _brownLight = Color(0xFF3D2C8D);
const _border = Color(0xFFE6E3F4);
const _textPri = Color(0xFF2C1A0E);
const _textMuted = Color(0xFF3D2C8D);

class AddHearingScreen extends StatefulWidget {
  const AddHearingScreen({super.key});
  @override
  State<AddHearingScreen> createState() => _AddHearingScreenState();
}

class _AddHearingScreenState extends State<AddHearingScreen> {
  final _courtNameCtrl = TextEditingController();
  final _courtRoomCtrl = TextEditingController();
  final _judgeNameCtrl = TextEditingController();
  final _purposeCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String? _selectedCaseId;
  DateTime _hearingDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay? _hearingTime;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => context.read<CaseProvider>().loadCases());
  }

  @override
  void dispose() {
    _courtNameCtrl.dispose();
    _courtRoomCtrl.dispose();
    _judgeNameCtrl.dispose();
    _purposeCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _formatDateDisplay(DateTime d) => '${d.day}/${d.month}/${d.year}';

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _hearingDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      builder: (ctx, child) => Theme(
        data: ThemeData.light().copyWith(
          colorScheme: const ColorScheme.light(
              primary: Color(0xFF150E3D), surface: Color(0xFFF6F5FB)),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _hearingDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _hearingTime ?? TimeOfDay.now(),
      builder: (ctx, child) => Theme(
        data: ThemeData.light().copyWith(
          colorScheme: const ColorScheme.light(
              primary: Color(0xFF150E3D), surface: Color(0xFFF6F5FB)),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _hearingTime = picked);
  }

  Future<void> _submit() async {
    if (_courtNameCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Please fill court name'),
        backgroundColor: const Color(0xFFD9534F),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => _loading = true);
    try {
      String? timeStr;
      if (_hearingTime != null) {
        timeStr =
            '${_hearingTime!.hour.toString().padLeft(2, '0')}:${_hearingTime!.minute.toString().padLeft(2, '0')}:00';
      }
      await DioClient.instance.post('/hearings', data: {
        'case_id': _selectedCaseId ?? '',
        'hearing_date': _formatDate(_hearingDate),
        'hearing_time': timeStr ?? '',
        'court_name': _courtNameCtrl.text.trim(),
        'court_room': _courtRoomCtrl.text.trim(),
        'judge_name': _judgeNameCtrl.text.trim(),
        'purpose': _purposeCtrl.text.trim(),
        'notes': _notesCtrl.text.trim(),
      });
      if (mounted) {
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_selectedCaseId != null
              ? 'Hearing scheduled! Client notified automatically!'
              : 'Hearing scheduled successfully!'),
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
          content: const Text('Failed to schedule hearing'),
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
    final cases = context.watch<CaseProvider>().cases;
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
                        child: Text('Schedule Hearing',
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
              child: ListView(padding: const EdgeInsets.all(16), children: [
            // Info banner
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: const Color(0xFF4A90D9).withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0xFF4A90D9).withValues(alpha: 0.2))),
              child: const Row(children: [
                Icon(Icons.info_outline_rounded,
                    color: Color(0xFF4A90D9), size: 16),
                SizedBox(width: 8),
                Expanded(
                    child: Text(
                        'Select a case to automatically notify the client about this hearing!',
                        style: TextStyle(
                            color: Color(0xFF2E6DB4),
                            fontSize: 11,
                            height: 1.4))),
              ]),
            ),
            const SizedBox(height: 16),

            _SectionHeader(title: 'Select Case', icon: Icons.gavel_rounded),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              decoration: BoxDecoration(
                  color: _bgCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: _selectedCaseId != null ? _brown : _border,
                      width: _selectedCaseId != null ? 1.5 : 0.8),
                  boxShadow: [
                    BoxShadow(
                        color: _brown.withValues(alpha: 0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2))
                  ]),
              child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                value: _selectedCaseId,
                hint: const Text('Select Case (optional)',
                    style: TextStyle(color: _textMuted, fontSize: 13)),
                dropdownColor: _bgCard,
                style: const TextStyle(color: _textPri, fontSize: 14),
                icon: const Icon(Icons.keyboard_arrow_down_rounded,
                    color: _brown),
                isExpanded: true,
                items: [
                  const DropdownMenuItem<String>(
                      value: null,
                      child: Text('No case selected',
                          style: TextStyle(color: _textMuted))),
                  ...cases
                      .map<DropdownMenuItem<String>>((cs) => DropdownMenuItem(
                            value: cs['id'],
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(cs['case_title'] ?? '',
                                      style: const TextStyle(
                                          color: _textPri,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13),
                                      overflow: TextOverflow.ellipsis),
                                  if ((cs['client_name'] ?? '').isNotEmpty)
                                    Text('Client: ${cs['client_name']}',
                                        style: const TextStyle(
                                            color: _brownLight, fontSize: 11)),
                                ]),
                          )),
                ],
                onChanged: (v) => setState(() {
                  _selectedCaseId = v;
                  if (v != null) {
                    final cs =
                        cases.firstWhere((c) => c['id'] == v, orElse: () => {});
                    if ((cs['court_name'] ?? '').isNotEmpty)
                      _courtNameCtrl.text = cs['court_name'];
                    if ((cs['judge_name'] ?? '').isNotEmpty)
                      _judgeNameCtrl.text = cs['judge_name'];
                  }
                }),
              )),
            ),
            if (_selectedCaseId != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: const Color(0xFF2E8B57).withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: const Color(0xFF2E8B57).withValues(alpha: 0.3))),
                child: const Row(children: [
                  Icon(Icons.check_circle_rounded,
                      color: Color(0xFF2E8B57), size: 15),
                  SizedBox(width: 8),
                  Text('Client will see this hearing in their portal!',
                      style: TextStyle(color: Color(0xFF2E8B57), fontSize: 11)),
                ]),
              ),
            ],
            const SizedBox(height: 20),

            _SectionHeader(
                title: 'Date & Time', icon: Icons.calendar_today_rounded),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: _bgCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _brown, width: 1.2),
                    boxShadow: [
                      BoxShadow(
                          color: _brown.withValues(alpha: 0.05),
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
                        const Text('Hearing Date',
                            style: TextStyle(color: _textMuted, fontSize: 11)),
                        Text(_formatDateDisplay(_hearingDate),
                            style: const TextStyle(
                                color: _textPri,
                                fontWeight: FontWeight.w700,
                                fontSize: 16)),
                      ]),
                  const Spacer(),
                  const Icon(Icons.edit_rounded, color: _textMuted, size: 16),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _pickTime,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: _bgCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _hearingTime != null ? _brown : _border,
                        width: 0.8),
                    boxShadow: [
                      BoxShadow(
                          color: _brown.withValues(alpha: 0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 2))
                    ]),
                child: Row(children: [
                  Icon(Icons.access_time_rounded,
                      color: _hearingTime != null ? _brown : _textMuted,
                      size: 20),
                  const SizedBox(width: 12),
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Hearing Time (optional)',
                            style: TextStyle(color: _textMuted, fontSize: 11)),
                        Text(
                            _hearingTime != null
                                ? _hearingTime!.format(context)
                                : 'Select time',
                            style: TextStyle(
                                color: _hearingTime != null
                                    ? _textPri
                                    : _textMuted,
                                fontWeight: FontWeight.w600,
                                fontSize: 15)),
                      ]),
                  const Spacer(),
                  const Icon(Icons.edit_rounded, color: _textMuted, size: 16),
                ]),
              ),
            ),
            const SizedBox(height: 20),

            _SectionHeader(
                title: 'Court Details', icon: Icons.account_balance_rounded),
            const SizedBox(height: 10),
            _buildField(
                _courtNameCtrl, 'Court Name *', Icons.account_balance_rounded),
            const SizedBox(height: 10),
            _buildField(_courtRoomCtrl, 'Court Room Number',
                Icons.door_front_door_outlined),
            const SizedBox(height: 10),
            _buildField(_judgeNameCtrl, 'Judge Name', Icons.person_outlined),
            const SizedBox(height: 20),

            _SectionHeader(
                title: 'Hearing Details', icon: Icons.info_outline_rounded),
            const SizedBox(height: 10),
            _buildField(_purposeCtrl, 'Purpose / Agenda', Icons.topic_rounded),
            const SizedBox(height: 10),
            TextFormField(
              controller: _notesCtrl,
              maxLines: 3,
              style: const TextStyle(color: _textPri, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Additional notes...',
                hintStyle: const TextStyle(color: _textMuted, fontSize: 13),
                prefixIcon:
                    const Icon(Icons.note_outlined, color: _brown, size: 18),
                filled: true,
                fillColor: _bgCard,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _border)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _border, width: 0.8)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _brown, width: 1.5)),
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
                    : const Text('Schedule Hearing',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
              ),
            ),
            const SizedBox(height: 40),
          ])),
        ]),
      ),
    );
  }

  Widget _buildField(TextEditingController ctrl, String label, IconData icon) {
    return TextFormField(
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
