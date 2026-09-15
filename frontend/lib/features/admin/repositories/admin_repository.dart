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
  Future<Map<String, dynamic>> _get(String path,
      [Map<String, dynamic>? query]) async {
    try {
      final res = await DioClient.instance.get(path, queryParameters: query);
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AdminException(DioClient.describeError(e));
    }
  }

  Future<Map<String, dynamic>> stats() => _get('/admin/stats');

  Future<Map<String, dynamic>> users(
          {String? role,
          String? status,
          String? search,
          String? from,
          String? to,
          int page = 1}) =>
      _get('/admin/users', {
        if (role != null && role.isNotEmpty) 'role': role,
        if (status != null && status.isNotEmpty) 'status': status,
        if (search != null && search.isNotEmpty) 'search': search,
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
        'page': page,
      });

  Future<Map<String, dynamic>> userDetail(String id) =>
      _get('/admin/users/$id');

  Future<void> setUserActive(String id, bool active) async {
    try {
      await DioClient.instance
          .put('/admin/users/$id', data: {'is_active': active});
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

  Future<Map<String, dynamic>> lawyers({
    String? status,
    String? search,
    String? activity,
    String? specialization,
    String? from,
    String? to,
    int page = 1,
    int limit = 20,
  }) =>
      _get('/admin/lawyers', {
        if (status != null && status.isNotEmpty) 'status': status,
        if (search != null && search.isNotEmpty) 'search': search,
        if (activity != null && activity.isNotEmpty) 'activity': activity,
        if (specialization != null && specialization.isNotEmpty)
          'specialization': specialization,
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
        'page': page,
        'limit': limit,
      });

  Future<Map<String, dynamic>> lawyerDocument(String lawyerId) =>
      _get('/admin/lawyers/$lawyerId/document');

  Future<void> verifyLawyer(String id, String status,
      {String rejectionReason = ''}) async {
    try {
      await DioClient.instance.put('/admin/lawyers/$id/verify', data: {
        'verification_status': status,
        'rejection_reason': rejectionReason
      });
    } on DioException catch (e) {
      throw AdminException(DioClient.describeError(e));
    }
  }

  Future<Map<String, dynamic>> students(
          {String? status, String? search, int page = 1}) =>
      _get('/admin/students', {
        if (status != null && status.isNotEmpty) 'status': status,
        if (search != null && search.isNotEmpty) 'search': search,
        'page': page,
      });

  Future<Map<String, dynamic>> clients(
          {String? status, String? search, int page = 1}) =>
      _get('/admin/clients', {
        if (status != null && status.isNotEmpty) 'status': status,
        if (search != null && search.isNotEmpty) 'search': search,
        'page': page,
      });

  Future<Map<String, dynamic>> consultations(
          {String? status,
          String? paymentStatus,
          String? search,
          String? from,
          String? to,
          int page = 1}) =>
      _get('/admin/consultations', {
        if (status != null && status.isNotEmpty) 'status': status,
        if (paymentStatus != null && paymentStatus.isNotEmpty)
          'payment_status': paymentStatus,
        if (search != null && search.isNotEmpty) 'search': search,
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
        'page': page,
      });

  Future<Map<String, dynamic>> consultationDetail(String id) =>
      _get('/admin/consultations/$id');

  Future<Map<String, dynamic>> payments(
          {String? status,
          String? kind,
          String? search,
          String? from,
          String? to,
          int page = 1}) =>
      _get('/admin/payments', {
        if (status != null && status.isNotEmpty) 'status': status,
        if (kind != null && kind.isNotEmpty) 'kind': kind,
        if (search != null && search.isNotEmpty) 'search': search,
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
        'page': page,
      });

  Future<Map<String, dynamic>> revenue({String? from, String? to}) =>
      _get('/admin/revenue', {
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
      });

  Future<Map<String, dynamic>> invoices(
          {String? status, String? search, int page = 1}) =>
      _get('/admin/invoices', {
        if (status != null && status.isNotEmpty) 'status': status,
        if (search != null && search.isNotEmpty) 'search': search,
        'page': page,
      });

  Future<Map<String, dynamic>> documents(
          {String? category, String? ownerRole, int page = 1}) =>
      _get('/admin/documents', {
        if (category != null && category.isNotEmpty) 'category': category,
        if (ownerRole != null && ownerRole.isNotEmpty) 'owner_role': ownerRole,
        'page': page,
      });

  Future<Map<String, dynamic>> cases(
          {String? search, String? status, int page = 1}) =>
      _get('/admin/cases', {
        if (search != null && search.isNotEmpty) 'search': search,
        if (status != null && status.isNotEmpty) 'status': status,
        'page': page,
      });

  Future<Map<String, dynamic>> hearings({String? status, int page = 1}) =>
      _get('/admin/hearings', {
        if (status != null && status.isNotEmpty) 'status': status,
        'page': page,
      });

  Future<Map<String, dynamic>> notifications({int page = 1}) =>
      _get('/admin/notifications', {'page': page});

  Future<int> sendNotification(
      {required String target,
      String? userId,
      required String title,
      required String message}) async {
    try {
      final res =
          await DioClient.instance.post('/admin/notifications/send', data: {
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

  Future<Map<String, dynamic>> search(String q) =>
      _get('/admin/search', {'q': q});

  // ─── Subscriptions module (Super Admin only) ──────
  Future<Map<String, dynamic>> subscriptionStats() =>
      _get('/admin/subscriptions/stats');

  Future<Map<String, dynamic>> subscriptions({
    String? status,
    bool premiumOnly = false,
    String? plan,
    String? search,
    String? from,
    String? to,
    int page = 1,
  }) =>
      _get('/admin/subscriptions', {
        if (status != null && status.isNotEmpty) 'status': status,
        if (premiumOnly) 'premium': 'true',
        if (plan != null && plan.isNotEmpty) 'plan': plan,
        if (search != null && search.isNotEmpty) 'search': search,
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
        'page': page,
      });

  Future<Map<String, dynamic>> subscriptionDetail(String id) =>
      _get('/admin/subscriptions/$id');

  Future<Map<String, dynamic>> subscriptionPlans() =>
      _get('/admin/subscriptions/plans');

  Future<Map<String, dynamic>> subscriptionRevenue() =>
      _get('/admin/subscriptions/revenue');

  Future<Map<String, dynamic>> subscriptionPayments({
    String? search,
    String? plan,
    String? status,
    String? from,
    String? to,
    int page = 1,
  }) =>
      _get('/admin/subscriptions/payments', {
        if (search != null && search.isNotEmpty) 'search': search,
        if (plan != null && plan.isNotEmpty) 'plan': plan,
        if (status != null && status.isNotEmpty) 'status': status,
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
        'page': page,
      });

  // ─── Analytics & Reports module (Super Admin only) ──────
  Future<Map<String, dynamic>> analyticsUsers({String? from, String? to}) =>
      _get('/admin/analytics/users', {
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
      });

  Future<Map<String, dynamic>> analyticsBookings({String? from, String? to}) =>
      _get('/admin/analytics/bookings', {
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
      });

  Future<Map<String, dynamic>> analyticsTrends({int days = 30, String? to}) =>
      _get('/admin/analytics/trends', {
        'days': days,
        if (to != null && to.isNotEmpty) 'to': to,
      });

  Future<Map<String, dynamic>> analyticsTransactions({
    String? search,
    String? service,
    String? status,
    String? lawyer,
    String? client,
    String? from,
    String? to,
    int page = 1,
  }) =>
      _get('/admin/analytics/transactions', {
        if (search != null && search.isNotEmpty) 'search': search,
        if (service != null && service.isNotEmpty) 'service': service,
        if (status != null && status.isNotEmpty) 'status': status,
        if (lawyer != null && lawyer.isNotEmpty) 'lawyer': lawyer,
        if (client != null && client.isNotEmpty) 'client': client,
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
        'page': page,
      });

  // ─── Payouts & Settlements module (Super Admin only) ──────
  Future<Map<String, dynamic>> payoutStats() => _get('/admin/payouts/stats');

  Future<Map<String, dynamic>> payoutLawyers(
          {String? search, String? status, int page = 1}) =>
      _get('/admin/payouts/lawyers', {
        if (search != null && search.isNotEmpty) 'search': search,
        if (status != null && status.isNotEmpty) 'status': status,
        'page': page,
      });

  Future<Map<String, dynamic>> payoutLawyerDetail(String id, {int page = 1}) =>
      _get('/admin/payouts/lawyers/$id', {'page': page});

  Future<Map<String, dynamic>> pendingPayouts({String? search}) =>
      _get('/admin/payouts/pending', {
        if (search != null && search.isNotEmpty) 'search': search,
      });

  Future<Map<String, dynamic>> paidPayouts(
          {String? search, String? from, String? to, int page = 1}) =>
      _get('/admin/payouts/paid', {
        if (search != null && search.isNotEmpty) 'search': search,
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
        'page': page,
      });

  Future<Map<String, dynamic>> settlements({
    String? lawyer,
    String? status,
    String? search,
    String? from,
    String? to,
    int page = 1,
  }) =>
      _get('/admin/payouts/settlements', {
        if (lawyer != null && lawyer.isNotEmpty) 'lawyer': lawyer,
        if (status != null && status.isNotEmpty) 'status': status,
        if (search != null && search.isNotEmpty) 'search': search,
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
        'page': page,
      });

  Future<Map<String, dynamic>> settlementDetail(String id) =>
      _get('/admin/payouts/settlements/$id');

  Future<Map<String, dynamic>> createSettlement({
    required String lawyerId,
    String? paymentMethod,
    String? reference,
    String? notes,
  }) async {
    try {
      final res =
          await DioClient.instance.post('/admin/payouts/settlements', data: {
        'lawyer_id': lawyerId,
        if (paymentMethod != null) 'payment_method': paymentMethod,
        if (reference != null) 'reference': reference,
        if (notes != null) 'notes': notes,
      });
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AdminException(DioClient.describeError(e));
    }
  }

  Future<Map<String, dynamic>> payoutCommission() =>
      _get('/admin/payouts/commission');

  Future<Map<String, dynamic>> payoutGST() => _get('/admin/payouts/gst');

  Future<Map<String, dynamic>> payoutTrends({int days = 30, String? to}) =>
      _get('/admin/payouts/trends', {
        'days': days,
        if (to != null && to.isNotEmpty) 'to': to,
      });

  Future<Map<String, dynamic>> payoutTransactions({
    String? search,
    String? lawyer,
    String? payoutStatus,
    String? serviceType,
    String? from,
    String? to,
    int page = 1,
  }) =>
      _get('/admin/payouts/transactions', {
        if (search != null && search.isNotEmpty) 'search': search,
        if (lawyer != null && lawyer.isNotEmpty) 'lawyer': lawyer,
        if (payoutStatus != null && payoutStatus.isNotEmpty)
          'payout_status': payoutStatus,
        if (serviceType != null && serviceType.isNotEmpty)
          'service_type': serviceType,
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
        'page': page,
      });

  // ─── Audit Logs module (Super Admin only) ──────
  Future<Map<String, dynamic>> auditLogStats() =>
      _get('/admin/audit-logs/stats');

  Future<Map<String, dynamic>> auditLogs({
    String? search,
    String? role,
    String? action,
    String? module,
    String? status,
    String? from,
    String? to,
    String sort = 'created_at',
    String order = 'desc',
    int page = 1,
    int limit = 20,
  }) =>
      _get('/admin/audit-logs', {
        if (search != null && search.isNotEmpty) 'search': search,
        if (role != null && role.isNotEmpty) 'role': role,
        if (action != null && action.isNotEmpty) 'action': action,
        if (module != null && module.isNotEmpty) 'module': module,
        if (status != null && status.isNotEmpty) 'status': status,
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
        'sort': sort,
        'order': order,
        'page': page,
        'limit': limit,
      });

  Future<Map<String, dynamic>> auditLogDetail(String id) =>
      _get('/admin/audit-logs/$id');

  // ─── Support / Complaints module (Super Admin only) ──────
  Future<Map<String, dynamic>> supportStats() => _get('/admin/support/stats');

  Future<Map<String, dynamic>> supportTickets({
    String? search,
    String? role,
    String? status,
    String? priority,
    String? category,
    String? assigned,
    String? from,
    String? to,
    String sort = 'updated_at',
    String order = 'desc',
    int page = 1,
    int limit = 20,
  }) =>
      _get('/admin/support/tickets', {
        if (search != null && search.isNotEmpty) 'search': search,
        if (role != null && role.isNotEmpty) 'role': role,
        if (status != null && status.isNotEmpty) 'status': status,
        if (priority != null && priority.isNotEmpty) 'priority': priority,
        if (category != null && category.isNotEmpty) 'category': category,
        if (assigned != null && assigned.isNotEmpty) 'assigned': assigned,
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
        'sort': sort,
        'order': order,
        'page': page,
        'limit': limit,
      });

  Future<Map<String, dynamic>> supportTicketDetail(String id) =>
      _get('/admin/support/tickets/$id');

  Future<void> assignSupportTicket(String id, String superAdminId) async {
    try {
      await DioClient.instance.put('/admin/support/tickets/$id/assign',
          data: {'super_admin_id': superAdminId});
    } on DioException catch (e) {
      throw AdminException(DioClient.describeError(e));
    }
  }

  Future<void> updateSupportPriority(String id, String priority) async {
    try {
      await DioClient.instance.put('/admin/support/tickets/$id/priority',
          data: {'priority': priority});
    } on DioException catch (e) {
      throw AdminException(DioClient.describeError(e));
    }
  }

  Future<void> updateSupportStatus(String id, String status) async {
    try {
      await DioClient.instance
          .put('/admin/support/tickets/$id/status', data: {'status': status});
    } on DioException catch (e) {
      throw AdminException(DioClient.describeError(e));
    }
  }

  Future<void> replySupportTicket(String id, String message) async {
    try {
      await DioClient.instance.post('/admin/support/tickets/$id/messages',
          data: {'message': message});
    } on DioException catch (e) {
      throw AdminException(DioClient.describeError(e));
    }
  }

  Future<void> resolveSupportTicket(String id, String resolutionNote) async {
    try {
      await DioClient.instance.put('/admin/support/tickets/$id/resolve',
          data: {'resolution_note': resolutionNote});
    } on DioException catch (e) {
      throw AdminException(DioClient.describeError(e));
    }
  }

  Future<void> closeSupportTicket(String id) async {
    try {
      await DioClient.instance.put('/admin/support/tickets/$id/close');
    } on DioException catch (e) {
      throw AdminException(DioClient.describeError(e));
    }
  }

  Future<void> reopenSupportTicket(String id) async {
    try {
      await DioClient.instance.put('/admin/support/tickets/$id/reopen');
    } on DioException catch (e) {
      throw AdminException(DioClient.describeError(e));
    }
  }

  // ─── Content Management module (Super Admin only) ──────
  Future<Map<String, dynamic>> contentStats() => _get('/admin/content/stats');

  Future<Map<String, dynamic>> contentItems({
    String? type,
    String? search,
    String? status,
    String? category,
    String? audience,
    String? from,
    String? to,
    String sort = 'updated_at',
    String order = 'desc',
    int page = 1,
    int limit = 20,
  }) =>
      _get('/admin/content/items', {
        if (type != null && type.isNotEmpty) 'type': type,
        if (search != null && search.isNotEmpty) 'search': search,
        if (status != null && status.isNotEmpty) 'status': status,
        if (category != null && category.isNotEmpty) 'category': category,
        if (audience != null && audience.isNotEmpty) 'audience': audience,
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
        'sort': sort,
        'order': order,
        'page': page,
        'limit': limit,
      });

  Future<Map<String, dynamic>> contentItemDetail(String id) =>
      _get('/admin/content/items/$id');

  Future<String> createContentItem(Map<String, dynamic> data) async {
    try {
      final res =
          await DioClient.instance.post('/admin/content/items', data: data);
      return res.data['data']['id'] as String;
    } on DioException catch (e) {
      throw AdminException(DioClient.describeError(e));
    }
  }

  Future<void> updateContentItem(String id, Map<String, dynamic> data) async {
    try {
      await DioClient.instance.put('/admin/content/items/$id', data: data);
    } on DioException catch (e) {
      throw AdminException(DioClient.describeError(e));
    }
  }

  Future<void> publishContentItem(String id) async {
    try {
      await DioClient.instance.put('/admin/content/items/$id/publish');
    } on DioException catch (e) {
      throw AdminException(DioClient.describeError(e));
    }
  }

  Future<void> scheduleContentItem(String id, String publishAt,
      {String? expireAt}) async {
    try {
      await DioClient.instance.put('/admin/content/items/$id/schedule', data: {
        'publish_at': publishAt,
        if (expireAt != null) 'expire_at': expireAt
      });
    } on DioException catch (e) {
      throw AdminException(DioClient.describeError(e));
    }
  }

  Future<void> unpublishContentItem(String id) async {
    try {
      await DioClient.instance.put('/admin/content/items/$id/unpublish');
    } on DioException catch (e) {
      throw AdminException(DioClient.describeError(e));
    }
  }

  Future<void> archiveContentItem(String id) async {
    try {
      await DioClient.instance.put('/admin/content/items/$id/archive');
    } on DioException catch (e) {
      throw AdminException(DioClient.describeError(e));
    }
  }

  Future<void> deleteContentItem(String id) async {
    try {
      await DioClient.instance.delete('/admin/content/items/$id');
    } on DioException catch (e) {
      throw AdminException(DioClient.describeError(e));
    }
  }

  Future<Map<String, dynamic>> legalDocumentVersions(String docType) =>
      _get('/admin/content/legal/$docType');

  Future<Map<String, dynamic>> legalDocumentVersion(String id) =>
      _get('/admin/content/legal/version/$id');

  Future<String> createLegalDocumentDraft(
      String docType, String version, String content) async {
    try {
      final res = await DioClient.instance.post('/admin/content/legal/$docType',
          data: {'version': version, 'content': content});
      return res.data['data']['id'] as String;
    } on DioException catch (e) {
      throw AdminException(DioClient.describeError(e));
    }
  }

  Future<void> publishLegalDocument(String id) async {
    try {
      await DioClient.instance.put('/admin/content/legal/version/$id/publish');
    } on DioException catch (e) {
      throw AdminException(DioClient.describeError(e));
    }
  }

  // ─── Notifications Center module (Super Admin only) ──────
  Future<Map<String, dynamic>> notificationCenterStats() =>
      _get('/admin/notifications-center/stats');

  Future<int> estimateNotificationRecipients(
      {required String targetType, List<String>? userIds}) async {
    final res = await _get('/admin/notifications-center/estimate', {
      'target_type': targetType,
      if (userIds != null && userIds.isNotEmpty) 'user_ids': userIds.join(','),
    });
    return (res['data']?['estimated_recipients'] as num?)?.toInt() ?? 0;
  }

  Future<Map<String, dynamic>> notificationBatches({
    String? search,
    String? audience,
    String? status,
    String? from,
    String? to,
    String sort = 'created_at',
    String order = 'desc',
    int page = 1,
    int limit = 20,
  }) =>
      _get('/admin/notifications-center/batches', {
        if (search != null && search.isNotEmpty) 'search': search,
        if (audience != null && audience.isNotEmpty) 'audience': audience,
        if (status != null && status.isNotEmpty) 'status': status,
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
        'sort': sort,
        'order': order,
        'page': page,
        'limit': limit,
      });

  Future<Map<String, dynamic>> notificationBatchDetail(String id) =>
      _get('/admin/notifications-center/batches/$id');

  Future<Map<String, dynamic>> createNotificationBatch({
    required String title,
    required String message,
    String? imageUrl,
    String? deepLink,
    required String targetType,
    List<String>? targetUserIds,
    String? scheduledAt,
    required String idempotencyKey,
  }) async {
    try {
      final res = await DioClient.instance
          .post('/admin/notifications-center/batches', data: {
        'title': title,
        'message': message,
        if (imageUrl != null) 'image_url': imageUrl,
        if (deepLink != null) 'deep_link': deepLink,
        'target_type': targetType,
        if (targetUserIds != null) 'target_user_ids': targetUserIds,
        if (scheduledAt != null) 'scheduled_at': scheduledAt,
        'idempotency_key': idempotencyKey,
      });
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw AdminException(DioClient.describeError(e));
    }
  }

  Future<void> updateScheduledNotification(String id,
      {required String title,
      required String message,
      String? imageUrl,
      String? deepLink,
      required String scheduledAt}) async {
    try {
      await DioClient.instance
          .put('/admin/notifications-center/batches/$id', data: {
        'title': title,
        'message': message,
        if (imageUrl != null) 'image_url': imageUrl,
        if (deepLink != null) 'deep_link': deepLink,
        'scheduled_at': scheduledAt,
      });
    } on DioException catch (e) {
      throw AdminException(DioClient.describeError(e));
    }
  }

  Future<void> cancelScheduledNotification(String id) async {
    try {
      await DioClient.instance
          .put('/admin/notifications-center/batches/$id/cancel');
    } on DioException catch (e) {
      throw AdminException(DioClient.describeError(e));
    }
  }

  // ─── Advanced Lawyer Management (Super Admin only) ──────
  Future<Map<String, dynamic>> lawyerStats() => _get('/admin/lawyers/stats');

  Future<Map<String, dynamic>> lawyerProfile(String id) =>
      _get('/admin/lawyers/$id/profile');

  Future<Map<String, dynamic>> lawyerDocumentsList(String id) =>
      _get('/admin/lawyers/$id/documents');

  Future<void> approveLawyerDocument(String docId) async {
    try {
      await DioClient.instance.put('/admin/lawyers/documents/$docId/approve');
    } on DioException catch (e) {
      throw AdminException(DioClient.describeError(e));
    }
  }

  Future<void> rejectLawyerDocument(String docId, String reason) async {
    try {
      await DioClient.instance.put('/admin/lawyers/documents/$docId/reject',
          data: {'reason': reason});
    } on DioException catch (e) {
      throw AdminException(DioClient.describeError(e));
    }
  }

  Future<void> suspendLawyer(String id, String reason) async {
    try {
      await DioClient.instance
          .put('/admin/lawyers/$id/suspend', data: {'reason': reason});
    } on DioException catch (e) {
      throw AdminException(DioClient.describeError(e));
    }
  }

  Future<void> reactivateLawyer(String id) async {
    try {
      await DioClient.instance.put('/admin/lawyers/$id/reactivate');
    } on DioException catch (e) {
      throw AdminException(DioClient.describeError(e));
    }
  }

  Future<Map<String, dynamic>> lawyerBookings(String id,
          {String? status, int page = 1}) =>
      _get('/admin/lawyers/$id/bookings', {
        if (status != null && status.isNotEmpty) 'status': status,
        'page': page,
      });

  Future<Map<String, dynamic>> lawyerCases(String id, {int page = 1}) =>
      _get('/admin/lawyers/$id/cases', {'page': page});

  Future<Map<String, dynamic>> lawyerReviews(String id) =>
      _get('/admin/lawyers/$id/reviews');

  Future<Map<String, dynamic>> lawyerActivity(String id) =>
      _get('/admin/lawyers/$id/activity');
}
