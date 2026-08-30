import 'package:flutter/material.dart';
import '../../../core/services/dio_client.dart';

class PortalProvider extends ChangeNotifier {
  List<dynamic> _cases = [];
  List<dynamic> _hearings = [];
  List<dynamic> _invoices = [];
  List<dynamic> _documents = [];
  List<dynamic> _notifications = [];
  bool _loading = false;
  String? _error;

  List<dynamic> get cases => _cases;
  List<dynamic> get hearings => _hearings;
  List<dynamic> get invoices => _invoices;
  List<dynamic> get documents => _documents;
  List<dynamic> get notifications => _notifications;
  bool get loading => _loading;
  String? get error => _error;

  int get unreadNotifications =>
      _notifications.where((n) => !(n['is_read'] ?? false)).length;

  int get pendingInvoicesCount =>
      _invoices.where((i) => i['status'] == 'unpaid' || i['status'] == 'partial').length;

  Future<void> loadAll() async {
    _loading = true;
    notifyListeners();
    try {
      await Future.wait([
        _loadCases(),
        _loadHearings(),
        _loadInvoices(),
        _loadDocuments(),
      ]);
    } catch (e) {
      _error = e.toString();
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> _loadCases() async {
    final res = await DioClient.instance.get('/portal/my-cases');
    _cases = res.data['data'] ?? [];
  }

  Future<void> _loadHearings() async {
    final res = await DioClient.instance.get('/portal/my-hearings');
    _hearings = res.data['data'] ?? [];
  }

  Future<void> _loadInvoices() async {
    final res = await DioClient.instance.get('/portal/my-invoices');
    _invoices = res.data['data'] ?? [];
  }

  Future<void> _loadDocuments() async {
    final res = await DioClient.instance.get('/portal/my-documents');
    _documents = res.data['data'] ?? [];
  }

  Future<void> refreshCases() async {
    try {
      await _loadCases();
      notifyListeners();
    } catch (e) {
      debugPrint('Cases refresh error: $e');
    }
  }

  Future<void> refreshInvoices() async {
    try {
      await _loadInvoices();
      notifyListeners();
    } catch (e) {
      debugPrint('Invoices refresh error: $e');
    }
  }

  Future<void> refreshDocuments() async {
    try {
      await _loadDocuments();
      notifyListeners();
    } catch (e) {
      debugPrint('Documents refresh error: $e');
    }
  }
}
