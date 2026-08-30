import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/dio_client.dart';
import '../../../core/constants/app_colors.dart';

class StaffListScreen extends StatefulWidget {
  const StaffListScreen({super.key});
  @override
  State<StaffListScreen> createState() => _StaffListScreenState();
}

class _StaffListScreenState extends State<StaffListScreen> {
  List<dynamic> _staff = [];
  bool _loading = true;
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStaff() async {
    setState(() => _loading = true);
    try {
      final res = await DioClient.instance.get('/staff');
      setState(() {
        _staff = res.data['data'] ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'admin':
        return AppColors.gold;
      case 'lawyer':
        return AppColors.info;
      case 'staff':
        return AppColors.success;
      case 'clerk':
        return AppColors.warning;
      default:
        return AppColors.textMuted;
    }
  }

  IconData _roleIcon(String role) {
    switch (role) {
      case 'admin':
        return Icons.admin_panel_settings_rounded;
      case 'lawyer':
        return Icons.gavel_rounded;
      case 'staff':
        return Icons.badge_rounded;
      case 'clerk':
        return Icons.description_rounded;
      default:
        return Icons.person_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _staff.where((s) {
      final name = (s['name'] ?? '').toLowerCase();
      final email = (s['email'] ?? '').toLowerCase();
      final role = (s['role'] ?? '').toLowerCase();
      return name.contains(_search) ||
          email.contains(_search) ||
          role.contains(_search);
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.primaryDark,
        title: const Text('Staff Management',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_rounded, color: AppColors.gold),
            onPressed: () {
              HapticFeedback.lightImpact();
              _showAddStaffDialog();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Stats Row
          Container(
            padding: const EdgeInsets.all(16),
            color: AppColors.primaryDark,
            child: Row(
              children: [
                _StaffStat(
                  label: 'Total',
                  value: '${_staff.length}',
                  color: AppColors.info,
                ),
                const SizedBox(width: 8),
                _StaffStat(
                  label: 'Lawyers',
                  value: '${_staff.where((s) => s['role'] == 'lawyer').length}',
                  color: AppColors.gold,
                ),
                const SizedBox(width: 8),
                _StaffStat(
                  label: 'Staff',
                  value:
                      '${_staff.where((s) => s['role'] == 'staff' || s['role'] == 'clerk').length}',
                  color: AppColors.success,
                ),
                const SizedBox(width: 8),
                _StaffStat(
                  label: 'Active',
                  value:
                      '${_staff.where((s) => s['is_active'] == true).length}',
                  color: AppColors.success,
                ),
              ],
            ),
          ),

          // Search
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: AppColors.textPrimary),
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search staff...',
                hintStyle: const TextStyle(color: AppColors.textMuted),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: AppColors.textMuted),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.gold),
                ),
              ),
            ),
          ),

          // List
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.gold))
                : filtered.isEmpty
                    ? _EmptyState(onAdd: _showAddStaffDialog)
                    : RefreshIndicator(
                        color: AppColors.gold,
                        onRefresh: _loadStaff,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) => _StaffCard(
                            staff: filtered[i],
                            roleColor: _roleColor(filtered[i]['role'] ?? ''),
                            roleIcon: _roleIcon(filtered[i]['role'] ?? ''),
                            onToggleActive: () => _toggleActive(filtered[i]),
                          ),
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          HapticFeedback.lightImpact();
          _showAddStaffDialog();
        },
        backgroundColor: AppColors.gold,
        child: const Icon(Icons.person_add_rounded, color: AppColors.primary),
      ),
    );
  }

  Future<void> _toggleActive(Map<String, dynamic> staff) async {
    try {
      await DioClient.instance.put('/staff/${staff['id']}', data: {
        'name': staff['name'],
        'phone': staff['phone'] ?? '',
        'designation': staff['designation'] ?? '',
        'is_active': !(staff['is_active'] ?? true),
      });
      _loadStaff();
      HapticFeedback.heavyImpact();
    } catch (e) {
      debugPrint('Toggle error: $e');
    }
  }

  void _showAddStaffDialog() {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final designationCtrl = TextEditingController();
    String selectedRole = 'lawyer';
    bool loading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Add Staff Member',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 20),

              // Name
              _modalField(nameCtrl, 'Full Name', Icons.person_rounded),
              const SizedBox(height: 12),

              // Email
              _modalField(emailCtrl, 'Email Address', Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 12),

              // Phone
              _modalField(phoneCtrl, 'Phone Number', Icons.phone_outlined,
                  keyboardType: TextInputType.phone),
              const SizedBox(height: 12),

              // Password
              _modalField(passCtrl, 'Password', Icons.lock_outline,
                  obscure: true),
              const SizedBox(height: 12),

              // Designation
              _modalField(
                  designationCtrl, 'Designation', Icons.work_outline_rounded),
              const SizedBox(height: 12),

              // Role
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedRole,
                    dropdownColor: AppColors.surface,
                    style: const TextStyle(color: AppColors.textPrimary),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: AppColors.gold),
                    isExpanded: true,
                    items: ['lawyer', 'staff', 'clerk', 'admin']
                        .map((r) => DropdownMenuItem(
                              value: r,
                              child: Text(r.toUpperCase()),
                            ))
                        .toList(),
                    onChanged: (v) => setModalState(() => selectedRole = v!),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Submit
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: loading
                      ? null
                      : () async {
                          if (nameCtrl.text.isEmpty ||
                              emailCtrl.text.isEmpty ||
                              passCtrl.text.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please fill required fields'),
                                backgroundColor: AppColors.error,
                              ),
                            );
                            return;
                          }
                          setModalState(() => loading = true);
                          try {
                            await DioClient.instance.post('/staff', data: {
                              'name': nameCtrl.text.trim(),
                              'email': emailCtrl.text.trim(),
                              'phone': phoneCtrl.text.trim(),
                              'password': passCtrl.text,
                              'designation': designationCtrl.text.trim(),
                              'role': selectedRole,
                            });
                            if (ctx.mounted) Navigator.pop(ctx);
                            _loadStaff();
                            HapticFeedback.heavyImpact();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text('✅ Staff member added!'),
                                  backgroundColor: AppColors.success,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                              );
                            }
                          } catch (e) {
                            setModalState(() => loading = false);
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: AppColors.primary, strokeWidth: 2),
                        )
                      : const Text('Add Staff Member',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modalField(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    TextInputType? keyboardType,
    bool obscure = false,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboardType,
      obscureText: obscure,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textMuted),
        prefixIcon: Icon(icon, color: AppColors.gold, size: 20),
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.gold),
        ),
      ),
    );
  }
}

class _StaffCard extends StatelessWidget {
  final dynamic staff;
  final Color roleColor;
  final IconData roleIcon;
  final VoidCallback onToggleActive;

  const _StaffCard({
    required this.staff,
    required this.roleColor,
    required this.roleIcon,
    required this.onToggleActive,
  });

  @override
  Widget build(BuildContext context) {
    final name = staff['name'] ?? '';
    final email = staff['email'] ?? '';
    final phone = staff['phone'] ?? '';
    final role = staff['role'] ?? '';
    final designation = staff['designation'] ?? '';
    final isActive = staff['is_active'] ?? true;
    final initials = name.isNotEmpty
        ? name
            .trim()
            .split(' ')
            .map((p) => p.isNotEmpty ? p[0] : '')
            .take(2)
            .join()
            .toUpperCase()
        : 'S';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? roleColor.withValues(alpha: 0.2) : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          // Avatar
          Stack(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: roleColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: roleColor.withValues(alpha: 0.3)),
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: TextStyle(
                      color: roleColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: isActive ? AppColors.success : AppColors.error,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.bgCard, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
                if (designation.isNotEmpty)
                  Text(designation,
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 12)),
                if (email.isNotEmpty)
                  Text(email,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                if (phone.isNotEmpty)
                  Text(phone,
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 11)),
              ],
            ),
          ),

          // Role + Toggle
          Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: roleColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(roleIcon, color: roleColor, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      role.toUpperCase(),
                      style: TextStyle(
                          color: roleColor,
                          fontSize: 9,
                          fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: onToggleActive,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppColors.success.withValues(alpha: 0.1)
                        : AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isActive ? 'Active' : 'Inactive',
                    style: TextStyle(
                      color: isActive ? AppColors.success : AppColors.error,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StaffStat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _StaffStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    color: color, fontSize: 18, fontWeight: FontWeight.w800)),
            Text(label,
                style:
                    const TextStyle(color: AppColors.textMuted, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.people_outline_rounded,
                color: AppColors.textMuted, size: 40),
          ),
          const SizedBox(height: 16),
          const Text('No staff members yet',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('Add lawyers and staff to your firm',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.person_add_rounded),
            label: const Text('Add Staff'),
          ),
        ],
      ),
    );
  }
}
