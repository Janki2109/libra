import 'package:dio/dio.dart';

import '../../../core/services/dio_client.dart';

class AdminException implements Exception {
  final String message;
  const AdminException(this.message);
  @override
  String toString() => message;
}

/// Thin wrapper over every /admin/* endpoint. Deliberately untyped
/// (Map<String,dynamic>/List) rather than a model class per endpoint — the
/// admin panel has ~20 list/detail shapes and the existing admin screens
/// (admin_dashboard_screen.dart etc.) already use raw maps throughout, so
/// this matches that established convention instead of introducing a
/// second style.
class AdminRepository {
  Future<Map<String, dynamic>> _get(String path, [Map<String, dynamic>? query]) async {
    try {
      final res = await DioClient.instance.get(path, queryParameters: query);
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AdminException(DioClient.describeError(e));
    }
  }

  Future<Map<String, dynamic>> stats() => _get('/admin/stats');

  Future<Map<String, dynamic>> users({String? role, String? status, String? search, String? from, String? to, int page = 1}) =>
      _get('/admin/users', {
        if (role != null && role.isNotEmpty) 'role': role,
        if (status != null && status.isNotEmpty) 'status': status,
        if (search != null && search.isNotEmpty) 'search': search,
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
        'page': page,
      });

  Future<Map<String, dynamic>> userDetail(String id) => _get('/admin/users/$id');

  Future<void> setUserActive(String id, bool active) async {
    try {
      await DioClient.instance.put('/admin/users/$id', data: {'is_active': active});
    } on DioException catch (e) {
      throw AdminException(DioClient.describeError(e));
    }
  }

  Future<void> deleteUser(String id) async {
    try {
      await DioClient.instance.delete('/admin/users/$id');
    } on DioException catch (e) {
      throw AdminException(DioClient.describeError(e));
    }
  }

  Future<Map<String, dynamic>> lawyers({String? status}) =>
      _get('/admin/lawyers', {if (status != null && status.isNotEmpty) 'status': status});

  Future<Map<String, dynamic>> lawyerDocument(String lawyerId) => _get('/admin/lawyers/$lawyerId/document');

  Future<void> verifyLawyer(String id, String status, {String rejectionReason = ''}) async {
    try {
      await DioClient.instance.put('/admin/lawyers/$id/verify',
          data: {'verification_status': status, 'rejection_reason': rejectionReason});
    } on DioException catch (e) {
      throw AdminException(DioClient.describeError(e));
    }
  }

  Future<Map<String, dynamic>> students({String? status, String? search, int page = 1}) => _get('/admin/students', {
        if (status != null && status.isNotEmpty) 'status': status,
        if (search != null && search.isNotEmpty) 'search': search,
        'page': page,
      });

  Future<Map<String, dynamic>> clients({String? status, String? search, int page = 1}) => _get('/admin/clients', {
        if (status != null && status.isNotEmpty) 'status': status,
        if (search != null && search.isNotEmpty) 'search': search,
        'page': page,
      });

  Future<Map<String, dynamic>> consultations(
          {String? status, String? paymentStatus, String? search, String? from, String? to, int page = 1}) =>
      _get('/admin/consultations', {
        if (status != null && status.isNotEmpty) 'status': status,
        if (paymentStatus != null && paymentStatus.isNotEmpty) 'payment_status': paymentStatus,
        if (search != null && search.isNotEmpty) 'search': search,
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
        'page': page,
      });

  Future<Map<String, dynamic>> consultationDetail(String id) => _get('/admin/consultations/$id');

  Future<Map<String, dynamic>> payments(
          {String? status, String? kind, String? search, String? from, String? to, int page = 1}) =>
      _get('/admin/payments', {
        if (status != null && status.isNotEmpty) 'status': status,
        if (kind != null && kind.isNotEmpty) 'kind': kind,
        if (search != null && search.isNotEmpty) 'search': search,
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
        'page': page,
      });

  Future<Map<String, dynamic>> revenue({String? from, String? to}) => _get('/admin/revenue', {
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
      });

  Future<Map<String, dynamic>> invoices({String? status, String? search, int page = 1}) => _get('/admin/invoices', {
        if (status != null && status.isNotEmpty) 'status': status,
        if (search != null && search.isNotEmpty) 'search': search,
        'page': page,
      });

  Future<Map<String, dynamic>> documents({String? category, String? ownerRole, int page = 1}) => _get('/admin/documents', {
        if (category != null && category.isNotEmpty) 'category': category,
        if (ownerRole != null && ownerRole.isNotEmpty) 'owner_role': ownerRole,
        'page': page,
      });

  Future<Map<String, dynamic>> cases({String? search, String? status, int page = 1}) => _get('/admin/cases', {
        if (search != null && search.isNotEmpty) 'search': search,
        if (status != null && status.isNotEmpty) 'status': status,
        'page': page,
      });

  Future<Map<String, dynamic>> hearings({String? status, int page = 1}) => _get('/admin/hearings', {
        if (status != null && status.isNotEmpty) 'status': status,
        'page': page,
      });

  Future<Map<String, dynamic>> notifications({int page = 1}) => _get('/admin/notifications', {'page': page});

  Future<int> sendNotification({required String target, String? userId, required String title, required String message}) async {
    try {
      final res = await DioClient.instance.post('/admin/notifications/send', data: {
        'target': target,
        if (userId != null) 'user_id': userId,
        'title': title,
        'message': message,
      });
      return (res.data['data']?['recipients'] as num?)?.toInt() ?? 0;
    } on DioException catch (e) {
      throw AdminException(DioClient.describeError(e));
    }
  }

  Future<Map<String, dynamic>> search(String q) => _get('/admin/search', {'q': q});
}
