import 'package:flutter/material.dart';
import '../../../core/services/dio_client.dart';

class BillingProvider extends ChangeNotifier {
  List<dynamic> _invoices = [];
  List<dynamic> _payments = [];
  bool _loading = false;
  String? _error;

  List<dynamic> get invoices => _invoices;
  List<dynamic> get payments => _payments;
  bool get loading => _loading;
  String? get error => _error;

  int get unpaidCount =>
      _invoices.where((i) => i['status'] == 'unpaid' || i['status'] == 'partial').length;

  double get totalPending => _invoices
      .where((i) => i['status'] == 'unpaid' || i['status'] == 'partial')
      .fold(0.0, (sum, i) => sum + ((i['total_amount'] ?? 0) - (i['paid_amount'] ?? 0)));

  Future<void> loadInvoices() async {
    _loading = true;
    notifyListeners();
    try {
      final res = await DioClient.instance.get('/invoices');
      _invoices = res.data['data'] ?? [];
    } catch (e) {
      _error = e.toString();
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> loadPayments() async {
    try {
      final res = await DioClient.instance.get('/payments');
      _payments = res.data['data'] ?? [];
      notifyListeners();
    } catch (e) {
      debugPrint('Payments error: $e');
    }
  }

  Future<bool> createInvoice(Map<String, dynamic> data) async {
    _error = null;
    try {
      await DioClient.instance.post('/invoices', data: data);
      await loadInvoices();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateInvoiceStatus(String id, String status) async {
    try {
      await DioClient.instance.put('/invoices/$id', data: {'status': status});
      final idx = _invoices.indexWhere((i) => i['id'] == id);
      if (idx != -1) {
        _invoices[idx]['status'] = status;
        notifyListeners();
      }
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> recordPayment(Map<String, dynamic> data) async {
    _error = null;
    try {
      await DioClient.instance.post('/payments', data: data);
      await loadInvoices();
      await loadPayments();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<Map<String, dynamic>?> getInvoice(String id) async {
    try {
      final res = await DioClient.instance.get('/invoices/$id');
      return res.data['data'];
    } catch (e) {
      return null;
    }
  }
}
