import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:agni_college_bus_tracker/services/api_service.dart';
import 'package:agni_college_bus_tracker/models/user.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

typedef NotificationCallback = Future<void> Function(String userId);
typedef LogoutCallback = Future<void> Function();

class AuthService extends ChangeNotifier {
  static const _usersKey = 'users';
  static const _currentUserKey = 'currentUser';
  static const lastRoleKey = 'lastRole';

  List<User> _users = [];
  User? _currentUser;
  String? _token;
  NotificationCallback? _onLoginCallback;
  LogoutCallback? _onLogoutCallback;

  List<User> get users => _users;
  User? get currentUser => _currentUser;
  String? get token => _token;
  bool get isLoggedIn => _currentUser != null;

  final GlobalKey<NavigatorState> navigatorKey;

  AuthService(this.navigatorKey);

  void setNotificationCallback(NotificationCallback callback) {
    _onLoginCallback = callback;
  }

  void setLogoutCallback(LogoutCallback callback) {
    _onLogoutCallback = callback;
  }

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();

    final usersJson = prefs.getString(_usersKey);
    if (usersJson != null) {
      try {
        final List decoded = json.decode(usersJson);
        _users = decoded.map((e) => User.fromJson(e)).toList();
      } catch (e) {
        debugPrint('Error loading users: $e');
      }
    } else {
      await _loadDefaultUsers();
    }

    final currentUserJson = prefs.getString(_currentUserKey);
    _token = prefs.getString('auth_token');

    if (currentUserJson != null && _token != null) {
      try {
        _currentUser = User.fromJson(json.decode(currentUserJson));
        debugPrint('Auth: Loaded user ${_currentUser?.id} with ${_currentUser?.pinnedBuses.length} pinned buses');

        final result = await fetchMe();
        if (result == 'expired') {
          // Lifetime token (365 days) — don't force logout on expiry.
          // Keep the local session so the user stays logged in (offline mode).
          debugPrint('Auth: Token expired, keeping local session (no forced logout)');
        } else if (result == 'ok') {
          debugPrint('Auth: Session valid, user authenticated');
        } else {
          debugPrint('Auth: Network error, keeping local session (offline mode)');
        }
      } catch (e) {
        debugPrint('Error loading current user session: $e');
      }
    }
    notifyListeners();
  }

  Future<void> _loadDefaultUsers() async {
    _users = [
      User(id: 'admin001', password: 'admin@123', role: UserRole.admin, name: 'System Admin'),
      User(id: 'staff001', password: 'staff@123', role: UserRole.staff, name: 'Staff Member'),
      User(id: 'stu001', password: 'stu@123', role: UserRole.student, name: 'Student'),
    ];
    await _saveUsers();
  }

  Future<void> _saveUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final usersJson = json.encode(_users.map((e) => e.toJson()).toList());
    await prefs.setString(_usersKey, usersJson);
  }

  Future<void> changeUserId(String oldId, String newId) async {
    final index = _users.indexWhere((u) => u.id == oldId);
    if (index == -1) return;
    final existing = _users[index];
    final updated = existing.copyWith(id: newId);
    if (_users.any((u) => u.id == newId)) return;
    _users[index] = updated;
    await _saveUsers();
    if (_currentUser?.id == oldId) {
      _currentUser = updated;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_currentUserKey, json.encode(_currentUser!.toJson()));
    }
    notifyListeners();
  }

  Future<Map<String, dynamic>> login(String identifier, String password) async {
    try {
      debugPrint('LOGIN: Starting login for identifier: $identifier');

      final localUsers = _users.where((u) => u.id == identifier && u.password == password).toList();

      if (localUsers.isNotEmpty) {
        debugPrint('LOGIN: Local user found - $identifier');
        _currentUser = localUsers.first;
        debugPrint('LOGIN: User has ${_currentUser!.pinnedBuses.length} pinned buses');
      } else {
        return await _loginWithBackend(identifier, password);
      }

      try {
        final backendResult = await _loginWithBackend(identifier, password);
        if (backendResult['success'] == true) {
          debugPrint('LOGIN: Backend login successful');
          return backendResult;
        }
      } catch (e) {
        debugPrint('LOGIN: Backend unavailable, using local auth');
      }

      return {'success': true, 'message': 'Logged in successfully (offline mode)'};
    } catch (e) {
      debugPrint('LOGIN: Error - $e');
      return {'success': false, 'message': 'Login failed: ${e.toString()}'};
    }
  }

  Future<Map<String, dynamic>> _loginWithBackend(String identifier, String password) async {
    debugPrint('LOGIN: Attempting backend login at ${ApiService.baseUrl}/auth/login');
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/auth/login'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'username': identifier, 'password': password},
      ).timeout(const Duration(seconds: 10));

      debugPrint('LOGIN: Backend response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        try {
          final data = json.decode(response.body);
          _token = data['access_token'];
          debugPrint('LOGIN: Token received');

          final SharedPreferences prefs = await SharedPreferences.getInstance();
          await prefs.setString('auth_token', _token!);

          final fetchResult = await fetchMe();
          if (fetchResult == 'ok') {
            return {'success': true, 'message': 'Logged in successfully'};
          } else if (fetchResult == 'expired') {
            return {'success': false, 'message': 'Token expired, please login again'};
          } else {
            debugPrint('LOGIN: Network error during fetchMe, keeping token');
            return {'success': true, 'message': 'Logged in successfully (offline mode)'};
          }
        } catch (e) {
          debugPrint('LOGIN: Error parsing token response: $e');
          return {'success': false, 'message': 'Invalid server response format'};
        }
      } else if (response.statusCode == 401) {
        debugPrint('LOGIN: Invalid credentials');
        return {'success': false, 'message': 'Invalid ID or password'};
      } else {
        debugPrint('LOGIN: Server error - ${response.statusCode}');
        return {'success': false, 'message': 'Server error (${response.statusCode})'};
      }
    } catch (e) {
      debugPrint('LOGIN: Error - $e');
      return {'success': false, 'message': 'Login failed: ${e.toString()}'};
    }
  }

  Future<String> fetchMe() async {
    try {
      if (_token == null) {
        debugPrint('FETCHME: No token available');
        return 'expired';
      }

      debugPrint('FETCHME: Fetching user profile from ${ApiService.baseUrl}/auth/me');

      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/auth/me'),
        headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      debugPrint('FETCHME: Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        try {
          final userData = json.decode(response.body);
          final backendUser = User.fromJson(userData);

          // CRITICAL FIX: Preserve local pinned buses so they are not lost
          final localPinned = _currentUser?.pinnedBuses ?? [];
          final backendPinned = backendUser.pinnedBuses;
          final mergedPinned = <String>{...localPinned, ...backendPinned}.toList();

          _currentUser = backendUser.copyWith(pinnedBuses: mergedPinned);
          debugPrint('FETCHME: User loaded - ${_currentUser?.id} with ${_currentUser?.pinnedBuses.length} pinned buses');

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_currentUserKey, json.encode(_currentUser!.toJson()));
          await prefs.setString(lastRoleKey, _currentUser!.role.name);
          notifyListeners();

          if (_onLoginCallback != null && _currentUser != null) {
            try {
              await _onLoginCallback!(_currentUser!.id);
            } catch (e) {
              debugPrint('FETCHME: Error calling notification callback: $e');
            }
          }

          return 'ok';
        } catch (e) {
          debugPrint('FETCHME: Error parsing user data: $e');
          return 'offline';
        }
      } else if (response.statusCode == 401) {
        debugPrint('FETCHME: Token invalid or expired');
        return 'expired';
      } else {
        debugPrint('FETCHME: Server error - ${response.statusCode}');
        return 'offline';
      }
    } catch (e) {
      debugPrint('FETCHME: Error - $e');
      return 'offline';
    }
  }

  Future<void> logout([BuildContext? ctx]) async {
    if (_onLogoutCallback != null) {
      await _onLogoutCallback!();
    }

    _currentUser = null;
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_currentUserKey);
    await prefs.remove('auth_token');
    await prefs.remove(lastRoleKey);

    notifyListeners();

    if (ctx != null && ctx.mounted) {
      GoRouter.of(ctx).go('/');
    } else {
      navigatorKey.currentState?.pushNamedAndRemoveUntil('/', (route) => false);
    }
  }

  Future<void> pinBus(String busNumber) async {
    if (_currentUser == null) return;
    final pinned = List<String>.from(_currentUser!.pinnedBuses);
    if (!pinned.contains(busNumber)) {
      pinned.add(busNumber);
      _currentUser = _currentUser!.copyWith(pinnedBuses: pinned);
      await updateUser(_currentUser!);

      try {
        final success = await ApiService.pinBusByNumber(busNumber);
        if (success) {
          debugPrint('Pinned bus $busNumber saved to backend');
        } else {
          debugPrint('Failed to save pinned bus to backend, using local storage');
        }
      } catch (e) {
        debugPrint('Backend pin save failed: $e');
      }

      try {
        final topic = 'bus_$busNumber';
        await FirebaseMessaging.instance.subscribeToTopic(topic);
        debugPrint('Subscribed to FCM topic: $topic');
      } catch (e) {
        debugPrint('Failed to subscribe to FCM topic: $e');
      }
    }
  }

  Future<void> unpinBus(String busNumber) async {
    if (_currentUser == null) return;
    final pinned = List<String>.from(_currentUser!.pinnedBuses);
    pinned.remove(busNumber);
    _currentUser = _currentUser!.copyWith(pinnedBuses: pinned);
    await updateUser(_currentUser!);

    try {
      final success = await ApiService.unpinBusByNumber(busNumber);
      if (success) {
        debugPrint('Unpinned bus $busNumber from backend');
      }
    } catch (e) {
      debugPrint('Backend unpin failed: $e');
    }

    try {
      final topic = 'bus_$busNumber';
      await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
      debugPrint('Unsubscribed from FCM topic: $topic');
    } catch (e) {
      debugPrint('Failed to unsubscribe from FCM topic: $e');
    }
  }

  bool isBusPinned(String busNumber) => _currentUser?.pinnedBuses.contains(busNumber) ?? false;

  Future<void> updateUser(User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentUserKey, json.encode(user.toJson()));
    notifyListeners();
  }
}