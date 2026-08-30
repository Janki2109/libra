import 'package:flutter/material.dart';
import '../../../core/services/dio_client.dart';

class DocumentProvider extends ChangeNotifier {
  List<dynamic> _documents = [];
  bool _loading = false;
  String? _error;

  List<dynamic> get documents => _documents;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> loadDocuments({String? caseId, String? clientId}) async {
    _loading = true;
    notifyListeners();
    try {
      String path = '/documents';
      if (caseId != null) path += '?case_id=$caseId';
      else if (clientId != null) path += '?client_id=$clientId';
      final res = await DioClient.instance.get(path);
      _documents = res.data['data'] ?? [];
    } catch (e) {
      _error = e.toString();
    }
    _loading = false;
    notifyListeners();
  }

  Future<bool> uploadDocument(Map<String, dynamic> data) async {
    _error = null;
    try {
      await DioClient.instance.post('/documents/upload', data: data);
      await loadDocuments();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteDocument(String id) async {
    try {
      await DioClient.instance.delete('/documents/$id');
      _documents.removeWhere((d) => d['id'] == id);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }
}
