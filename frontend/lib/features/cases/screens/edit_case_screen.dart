import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/dio_client.dart';

class EditCaseScreen extends StatefulWidget {
  final String caseId;
  const EditCaseScreen({super.key, required this.caseId});
  @override
  State<EditCaseScreen> createState() => _EditCaseScreenState();
}

class _EditCaseScreenState extends State<EditCaseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _courtNameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _caseType = 'Civil';
  String _priority = 'Normal';
  bool _loading = true;
  bool _saving = false;

  // The backend's UpdateCase only persists these fields when called without
  // a status change — case_number, court_location, judge_name, opposite
  // party/lawyer and the linked client/lawyer are fixed at creation.
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
    _load();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _courtNameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await DioClient.instance.get('/cases/${widget.caseId}');
      final data = res.data['data'] ?? {};
      _titleCtrl.text = data['case_title'] ?? '';
      _courtNameCtrl.text = data['court_name'] ?? '';
      _descCtrl.text = data['description'] ?? '';
      final type = (data['case_type'] ?? '') as String;
      if (_caseTypes.any((t) => t.toLowerCase() == type.toLowerCase())) {
        _caseType = _caseTypes.firstWhere(
            (t) => t.toLowerCase() == type.toLowerCase());
      }
      final priority = (data['priority'] ?? '') as String;
      if (_priorities.any((p) => p.toLowerCase() == priority.toLowerCase())) {
        _priority = _priorities.firstWhere(
            (p) => p.toLowerCase() == priority.toLowerCase());
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await DioClient.instance.put('/cases/${widget.caseId}', data: {
        'case_title': _titleCtrl.text.trim(),
        'case_type': _caseType,
        'court_name': _courtNameCtrl.text.trim(),
        'priority': _priority.toLowerCase(),
        'description': _descCtrl.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Case updated successfully'),
            backgroundColor: AppColors.success));
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(DioClient.describeError(e)),
            backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.primaryDark,
        title: const Text('Edit Case',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => context.pop()),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(children: [
                  _Field(
                      ctrl: _titleCtrl,
                      label: 'Case Title',
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? 'Required' : null),
                  const SizedBox(height: 14),
                  _Dropdown(
                      label: 'Case Type',
                      value: _caseType,
                      items: _caseTypes,
                      onChanged: (v) => setState(() => _caseType = v!)),
                  const SizedBox(height: 14),
                  _Field(ctrl: _courtNameCtrl, label: 'Court Name'),
                  const SizedBox(height: 14),
                  _Dropdown(
                      label: 'Priority',
                      value: _priority,
                      items: _priorities,
                      onChanged: (v) => setState(() => _priority = v!)),
                  const SizedBox(height: 14),
                  _Field(ctrl: _descCtrl, label: 'Description', maxLines: 4),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.gold,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  color: AppColors.primary, strokeWidth: 2))
                          : const Text('Save Changes',
                              style: TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15)),
                    ),
                  ),
                ]),
              ),
            ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final int maxLines;
  final String? Function(String?)? validator;
  const _Field(
      {required this.ctrl,
      required this.label,
      this.maxLines = 1,
      this.validator});
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextFormField(
            controller: ctrl,
            maxLines: maxLines,
            validator: validator,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
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
        ],
      );
}

class _Dropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> items;
  final void Function(String?) onChanged;
  const _Dropdown(
      {required this.label,
      required this.value,
      required this.items,
      required this.onChanged});
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                isExpanded: true,
                dropdownColor: AppColors.surface,
                style: const TextStyle(color: AppColors.textPrimary),
                items: items
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      );
}
