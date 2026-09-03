
class UserModel {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String roleId;
  final String roleName;
  final String firmId;
  final String avatarUrl;
  final String profilePhoto; // ✅ NEW
  final String designation;
  final bool isActive;
  final String createdAt;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    this.phone = '',
    this.roleId = '',
    this.roleName = '',
    this.firmId = '',
    this.avatarUrl = '',
    this.profilePhoto = '', // ✅ NEW
    this.designation = '',
    this.isActive = true,
    this.createdAt = '',
  });

  String get initials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : 'U';
  }

  bool get isAdmin => roleName == 'admin' || roleName == 'super_admin';
  bool get isClient => roleName == 'client';
  bool get isLawyer => roleName == 'lawyer' || roleName == 'admin';
  bool get isSuperAdmin => roleName == 'super_admin';
  bool get isLawStudent => roleName == 'law_student';
  bool get hasPhoto => profilePhoto.isNotEmpty;

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      roleId: json['role_id']?.toString() ?? '',
      roleName: json['role_name']?.toString() ?? json['role']?.toString() ?? '',
      firmId: json['firm_id']?.toString() ?? '',
      avatarUrl: json['avatar_url']?.toString() ?? '',
      // The server only ever populates avatar_url — profile_photo exists
      // solely in the locally-cached copy of this model, written by
      // AuthProvider.updateProfilePhoto. Prefer it when present (it may be
      // fresher than what the server has just after an update), otherwise
      // fall back to what the server actually sent.
      profilePhoto: (json['profile_photo']?.toString().isNotEmpty ?? false)
          ? json['profile_photo'].toString()
          : (json['avatar_url']?.toString() ?? ''),
      designation: json['designation']?.toString() ?? '',
      isActive: json['is_active'] ?? true,
      createdAt: json['created_at']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'phone': phone,
        'role_id': roleId,
        'role_name': roleName,
        'firm_id': firmId,
        'avatar_url': avatarUrl,
        'profile_photo': profilePhoto,
        'designation': designation,
        'is_active': isActive,
        'created_at': createdAt,
      };
}
