import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:agni_college_bus_tracker/models/feedback.dart';
import 'package:agni_college_bus_tracker/services/auth_service.dart';
import 'package:agni_college_bus_tracker/services/api_service.dart';

class FeedbackService extends ChangeNotifier {
  static const _feedbackKey = 'feedbacks';
  final AuthService _authService;
  List<Feedback> _feedbacks = [];

  FeedbackService(this._authService);

  List<Feedback> get feedbacks => _feedbacks;

  Future<void> initialize() async {
    // Try to load from backend first
    try {
      final data = await ApiService.get('/feedback');
      if (data is List) {
        _feedbacks = data.map((e) => Feedback.fromJson(e)).toList();
        await _save();
        notifyListeners();
        return;
      }
    } catch (e) {
      debugPrint('Error loading feedbacks from backend: $e');
    }

    // Fallback to local storage
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_feedbackKey);
    if (jsonStr != null) {
      try {
        final List decoded = json.decode(jsonStr);
        _feedbacks = decoded.map((e) => Feedback.fromJson(e)).toList();
      } catch (e) {
        debugPrint('Error loading local feedbacks: $e');
      }
    }
    notifyListeners();
  }

  Future<void> submitFeedback(String subject, String message) async {
    final user = _authService.currentUser;
    if (user == null) return;

    final feedback = Feedback(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      userId: user.id,
      userName: user.name ?? 'Anonymous',
      userRole: user.role.name,
      subject: subject,
      message: message,
    );

    _feedbacks.insert(0, feedback);
    await _save();
    notifyListeners();

    // Try to sync to backend
    try {
      await ApiService.post('/feedback', {
        'subject': subject,
        'message': message,
      });
    } catch (e) {
      debugPrint('Error syncing feedback to backend: $e');
    }
  }

  Future<void> addReply(String feedbackId, String reply) async {
    final idx = _feedbacks.indexWhere((f) => f.id == feedbackId);
    if (idx == -1) return;

    _feedbacks[idx] = Feedback(
      id: _feedbacks[idx].id,
      userId: _feedbacks[idx].userId,
      userName: _feedbacks[idx].userName,
      userRole: _feedbacks[idx].userRole,
      subject: _feedbacks[idx].subject,
      message: _feedbacks[idx].message,
      reply: reply,
      replied: true,
      createdAt: _feedbacks[idx].createdAt,
      repliedAt: DateTime.now(),
    );

    await _save();
    notifyListeners();

    // Try to sync reply to backend
    try {
      await ApiService.post('/feedback/$feedbackId/reply', {
        'reply': reply,
      });
    } catch (e) {
      debugPrint('Error syncing reply to backend: $e');
    }
  }

  List<Feedback> forUser(String userId) {
    return _feedbacks.where((f) => f.userId == userId).toList();
  }

  List<Feedback> get unanswered => _feedbacks.where((f) => !f.replied).toList();

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = json.encode(_feedbacks.map((e) => e.toJson()).toList());
    await prefs.setString(_feedbackKey, jsonStr);
  }
}
