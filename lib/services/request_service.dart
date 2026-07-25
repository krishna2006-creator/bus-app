import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:agni_college_bus_tracker/models/request.dart';
import 'package:agni_college_bus_tracker/models/app_notification.dart';
import 'package:agni_college_bus_tracker/models/user.dart';
import 'package:agni_college_bus_tracker/services/notification_service.dart';

class RequestService extends ChangeNotifier {
  static const _requestsKey = 'requests';
  List<Request> _requests = [];
  final NotificationService _notificationService;

  RequestService(this._notificationService);

  List<Request> get requests => _requests;
  List<Request> get pendingRequests =>
      _requests.where((r) => r.status == RequestStatus.pending).toList();

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final requestsJson = prefs.getString(_requestsKey);

    if (requestsJson != null) {
      try {
        final List decoded = json.decode(requestsJson);
        _requests = decoded.map((e) => Request.fromJson(e)).toList();
      } catch (e) {
        debugPrint('Error loading requests: $e');
      }
    }
    notifyListeners();
  }

  Future<void> addRequest(Request request, List<User> allUsers) async {
    _requests.insert(0, request);
    await _saveRequests();
    
    // Notify Admin about the new request
    for (final user in allUsers) {
      if (user.role == UserRole.admin) {
        await _notificationService.addNotification(AppNotification(
          id: 'request_${request.id}_${user.id}',
          userId: user.id,
          title: 'New Request from Student',
          message: '${request.userName} has submitted a new request.',
          createdAt: DateTime.now(),
        ));
      }
    }
    
    notifyListeners();
  }

  Future<void> updateRequest(Request request) async {
    final index = _requests.indexWhere((r) => r.id == request.id);
    if (index != -1) {
      _requests[index] = request;
      await _saveRequests();
      
      // Notify the student about the update
      await _notificationService.addNotification(AppNotification(
        id: 'request_update_${request.id}_${request.userId}',
        userId: request.userId,
        title: 'Request Status Updated',
        message: 'Your request status is now: ${request.status.name}.',
        createdAt: DateTime.now(),
      ));

      notifyListeners();
    }
  }

  Future<void> deleteRequest(String id) async {
    _requests.removeWhere((r) => r.id == id);
    await _saveRequests();
    notifyListeners();
  }

  Future<void> _saveRequests() async {
    final prefs = await SharedPreferences.getInstance();
    final requestsJson = json.encode(_requests.map((e) => e.toJson()).toList());
    await prefs.setString(_requestsKey, requestsJson);
  }
}
