import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:agni_college_bus_tracker/models/request.dart';
import 'package:agni_college_bus_tracker/models/app_notification.dart';
import 'package:agni_college_bus_tracker/models/user.dart';
import 'package:agni_college_bus_tracker/services/notification_service.dart';
import 'package:agni_college_bus_tracker/services/api_service.dart';

class RequestService extends ChangeNotifier {
  static const _requestsKey = 'requests';
  List<Request> _requests = [];
  final NotificationService _notificationService;

  RequestService(this._notificationService);

  List<Request> get requests => _requests;
  List<Request> get pendingRequests =>
      _requests.where((r) => r.status == RequestStatus.pending).toList();

  Future<void> initialize() async {
    // Try to load from backend first
    try {
      final data = await ApiService.get('/requests/');
      if (data is List) {
        _requests = data.map((e) => _parseBackendRequest(e)).toList();
        await _saveRequests();
        notifyListeners();
        return;
      }
    } catch (e) {
      debugPrint('Error loading requests from backend: $e');
    }

    // Fallback to local storage
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

  Request _parseBackendRequest(Map<String, dynamic> json) {
    return Request(
      id: json['id']?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      userId: json['user_id'] as String? ?? '',
      userName: json['user_name'] as String? ?? 'Unknown',
      busNumber: json['bus_number'] as String? ?? 'N/A',
      type: _parseRequestType(json['request_type'] as String? ?? 'general'),
      message: json['description'] as String? ?? '',
      status: _parseRequestStatus(json['status'] as String? ?? 'pending'),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      updatedAt: json['resolved_at'] != null
          ? DateTime.parse(json['resolved_at'])
          : DateTime.now(),
    );
  }

  RequestType _parseRequestType(String type) {
    switch (type.toLowerCase()) {
      case 'missed_bus':
      case 'missedBus':
        return RequestType.missedBus;
      case 'stop_bus':
      case 'stopBus':
        return RequestType.stopBus;
      case 'delay_bus':
      case 'delayBus':
        return RequestType.delayBus;
      case 'bus_issue':
      case 'busIssue':
        return RequestType.busIssue;
      default:
        return RequestType.missedBus;
    }
  }

  RequestStatus _parseRequestStatus(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return RequestStatus.approved;
      case 'rejected':
        return RequestStatus.rejected;
      default:
        return RequestStatus.pending;
    }
  }

  Future<void> addRequest(Request request, List<User> allUsers) async {
    _requests.insert(0, request);
    await _saveRequests();

    // Sync to backend
    try {
      await ApiService.post('/requests/', {
        'bus_id': null,
        'request_type': _requestTypeToBackend(request.type),
        'description': request.message,
      });
    } catch (e) {
      debugPrint('Error syncing request to backend: $e');
    }

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

  String _requestTypeToBackend(RequestType type) {
    switch (type) {
      case RequestType.missedBus:
        return 'missed_bus';
      case RequestType.stopBus:
        return 'stop_bus';
      case RequestType.delayBus:
        return 'delay_bus';
      case RequestType.busIssue:
        return 'bus_issue';
    }
  }

  Future<void> updateRequest(Request request) async {
    final index = _requests.indexWhere((r) => r.id == request.id);
    if (index != -1) {
      _requests[index] = request;
      await _saveRequests();

      // Sync status update to backend
      try {
        await ApiService.post('/requests/${request.id}/status/', {
          'status': _requestStatusToBackend(request.status),
        });
      } catch (e) {
        debugPrint('Error syncing request status to backend: $e');
      }

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

  String _requestStatusToBackend(RequestStatus status) {
    switch (status) {
      case RequestStatus.pending:
        return 'pending';
      case RequestStatus.approved:
        return 'approved';
      case RequestStatus.rejected:
        return 'rejected';
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
