import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:agni_college_bus_tracker/models/announcement.dart';
import 'package:agni_college_bus_tracker/models/user.dart';
import 'package:agni_college_bus_tracker/services/notification_service.dart';
import 'package:agni_college_bus_tracker/services/api_service.dart';

class AnnouncementService extends ChangeNotifier {
  static const _announcementsKey = 'announcements';
  List<Announcement> _announcements = [];
  AnnouncementService(NotificationService notificationService);

  List<Announcement> get announcements => _announcements;

  Future<void> initialize() async {
    try {
      final List<dynamic> data = await ApiService.get('/announcements');
      _announcements = data
          .map((e) => Announcement.fromJson(e as Map<String, dynamic>))
          .toList();
      await _saveAnnouncements();
    } catch (e) {
      debugPrint(
          'Error loading announcements from backend, falling back to local SharedPreferences: $e');
      final prefs = await SharedPreferences.getInstance();
      final announcementsJson = prefs.getString(_announcementsKey);

      if (announcementsJson != null) {
        try {
          final List decoded = json.decode(announcementsJson);
          _announcements =
              decoded.map((e) => Announcement.fromJson(e)).toList();
        } catch (ex) {
          debugPrint('Error loading local announcements: $ex');
        }
      }
    }
    notifyListeners();
  }

  List<Announcement> getAnnouncementsForRole(UserRole role) {
    return _announcements.where((a) {
      if (a.target == AnnouncementTarget.all) return true;
      switch (role) {
        case UserRole.student:
          return a.target == AnnouncementTarget.students;
        case UserRole.staff:
          return a.target == AnnouncementTarget.staff;
        case UserRole.driver:
          return a.target == AnnouncementTarget.drivers;
        default:
          return true;
      }
    }).toList();
  }

  Future<void> addAnnouncement(
      Announcement announcement, List<User> allUsers) async {
    String targetRole = 'all';
    if (announcement.target == AnnouncementTarget.students) {
      targetRole = 'student';
    } else if (announcement.target == AnnouncementTarget.staff) {
      targetRole = 'staff';
    } else if (announcement.target == AnnouncementTarget.drivers) {
      targetRole = 'driver';
    }

    final success = await ApiService.createAnnouncement(
      announcement.title,
      announcement.message,
      targetRole,
    );

    if (success) {
      try {
        final List<dynamic> data = await ApiService.get('/announcements/');
        _announcements = data
            .map((e) => Announcement.fromJson(e as Map<String, dynamic>))
            .toList();
        await _saveAnnouncements();
      } catch (e) {
        debugPrint('Error refreshing announcements: $e');
        _announcements.insert(0, announcement);
        await _saveAnnouncements();
      }
    } else {
      _announcements.insert(0, announcement);
      await _saveAnnouncements();
    }

    // Notifications are handled by the backend via WebSocket + FCM push.
    // No local notifications needed here to avoid duplicate alerts on the creator's device.
  }

  Future<void> deleteAnnouncement(String id) async {
    // Try to delete from backend first
    try {
      final response = await http.delete(
        Uri.parse('${ApiService.baseUrl}/announcements/$id'),
        headers: await ApiService.getHeaders(),
      );
      if (response.statusCode == 200) {
        debugPrint('Announcement deleted from backend');
      }
    } catch (e) {
      debugPrint('Backend delete failed, removing locally: $e');
    }

    _announcements.removeWhere((a) => a.id == id);
    await _saveAnnouncements();
    notifyListeners();
  }

  Future<void> _saveAnnouncements() async {
    final prefs = await SharedPreferences.getInstance();
    final announcementsJson =
        json.encode(_announcements.map((e) => e.toJson()).toList());
    await prefs.setString(_announcementsKey, announcementsJson);
  }
}
