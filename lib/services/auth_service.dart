import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:agni_college_bus_tracker/services/api_service.dart';
import 'package:agni_college_bus_tracker/models/user.dart';

// Callback types
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
  LogoutCallback? _onLogoutCallback; // CRITICAL FIX: Add logout callback

  List<User> get users => _users;
  User? get currentUser => _currentUser;
  String? get token => _token;
  bool get isLoggedIn => _currentUser != null;

  final GlobalKey<NavigatorState> navigatorKey;

  AuthService(this.navigatorKey);

  // Set callback for notification service reconnection after login
  void setNotificationCallback(NotificationCallback callback) {
    _onLoginCallback = callback;
  }

  // CRITICAL FIX: Set callback for cleanup on logout
  void setLogoutCallback(LogoutCallback callback) {
    _onLogoutCallback = callback;
  }

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();

    // Load local users (fallbacks)
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

    // Load current session and token
    final currentUserJson = prefs.getString(_currentUserKey);
    _token = prefs.getString('auth_token');

    if (currentUserJson != null && _token != null) {
      try {
        _currentUser = User.fromJson(json.decode(currentUserJson));
        // Verify token is still valid by calling fetchMe()
        final isValid = await fetchMe();
        if (!isValid) {
          // Token expired - clear it and require login again
          _currentUser = null;
          _token = null;
          await prefs.remove('auth_token');
          await prefs.remove(_currentUserKey);
          await prefs.remove(lastRoleKey);
        }
      } catch (e) {
        debugPrint('Error loading current user session: $e');
      }
    }
    notifyListeners();
  }

  Future<void> _loadDefaultUsers() async {
    // Default admin and staff for initial local testing
    _users = [
      User(
          id: 'admin001',
          password: 'admin@123',
          role: UserRole.admin,
          name: 'System Admin'),
      User(
          id: 'staff001',
          password: 'staff@123',
          role: UserRole.staff,
          name: 'Staff Member'),
      User(
          id: 'stu001',
          password: 'stu@123',
          role: UserRole.student,
          name: 'Student'),
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
      await prefs.setString(
          _currentUserKey, json.encode(_currentUser!.toJson()));
    }
    notifyListeners();
  }

  /// LOGIN logic connected to Backend
  /// Returns tuple: (success, errorMessage)
  Future<Map<String, dynamic>> login(String identifier, String password) async {
    try {
      debugPrint('🔐 LOGIN: Starting login for identifier: $identifier');

      // 1. Check local users first (for pre-defined admin/staff)
      final localUsers = _users
          .where((u) => u.id == identifier && u.password == password)
          .toList();

      if (localUsers.isNotEmpty) {
        debugPrint('✅ LOGIN: Local user found - $identifier');
        _currentUser = localUsers.first;

        // Use the user's ID directly as the token since the backend's get_current_user
        // function first checks if the token matches a user ID directly.
        // This allows local admin users to make authenticated API calls without a JWT.
        return await _loginWithBackend(identifier, password);
      }

      return await _loginWithBackend(identifier, password);
    } on SocketException catch (e) {
      debugPrint('❌ LOGIN: Network error - $e');
      return {
        'success': false,
        'message': 'No internet connection or server unreachable'
      };
    } on TimeoutException catch (e) {
      debugPrint('❌ LOGIN: Request timeout - $e');
      return {
        'success': false,
        'message': 'Request timeout - server not responding'
      };
    } catch (e) {
      debugPrint('❌ LOGIN: Unexpected error - $e');
      return {'success': false, 'message': 'Login failed: ${e.toString()}'};
    }
  }

  Future<Map<String, dynamic>> _loginWithBackend(
      String identifier, String password) async {
    debugPrint(
        '🔐 LOGIN: Attempting backend login at ${ApiService.baseUrl}/auth/login');
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/auth/login'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'username': identifier, // OAuth2 expects 'username' (can be email)
          'password': password,
        },
      ).timeout(const Duration(seconds: 10));

      debugPrint('🔐 LOGIN: Backend response status: ${response.statusCode}');
      debugPrint('🔐 LOGIN: Backend response body: ${response.body}');

      if (response.statusCode == 200) {
        try {
          final data = json.decode(response.body);
          _token = data['access_token'];
          debugPrint('✅ LOGIN: Token received: ${_token?.substring(0, 20)}...');

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('auth_token', _token!);

          // Fetch user profile after login
          final fetchResult = await fetchMe();
          if (fetchResult) {
            return {'success': true, 'message': 'Logged in successfully'};
          } else {
            return {
              'success': false,
              'message': 'Failed to fetch user profile'
            };
          }
        } catch (e) {
          debugPrint('❌ LOGIN: Error parsing token response: $e');
          return {
            'success': false,
            'message': 'Invalid server response format'
          };
        }
      } else if (response.statusCode == 401) {
        debugPrint('❌ LOGIN: Invalid credentials');
        return {'success': false, 'message': 'Invalid ID or password'};
      } else {
        debugPrint('❌ LOGIN: Server error - ${response.statusCode}');
        return {
          'success': false,
          'message':
              'Server error (${response.statusCode}). Make sure backend is running at ${ApiService.baseUrl}'
        };
      }
    } on SocketException catch (e) {
      debugPrint('❌ LOGIN: Network error - $e');
      return {
        'success': false,
        'message': 'No internet connection or server unreachable'
      };
    } on TimeoutException catch (e) {
      debugPrint('❌ LOGIN: Request timeout - $e');
      return {
        'success': false,
        'message': 'Request timeout - server not responding'
      };
    } catch (e) {
      debugPrint('❌ LOGIN: Unexpected error - $e');
      return {'success': false, 'message': 'Login failed: ${e.toString()}'};
    }
  }

  Future<bool> fetchMe() async {
    try {
      if (_token == null) {
        debugPrint('❌ FETCHME: No token available');
        return false;
      }

      debugPrint(
          '🔐 FETCHME: Fetching user profile from ${ApiService.baseUrl}/auth/me');

      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/auth/me'),
        headers: {
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      debugPrint('🔐 FETCHME: Response status: ${response.statusCode}');
      debugPrint('🔐 FETCHME: Response body: ${response.body}');

      if (response.statusCode == 200) {
        try {
          final userData = json.decode(response.body);
          _currentUser = User.fromJson(userData);
          debugPrint('✅ FETCHME: User loaded - ${_currentUser?.id}');

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
              _currentUserKey, json.encode(_currentUser!.toJson()));
          await prefs.setString(lastRoleKey, _currentUser!.role.name);
          notifyListeners();

          // Notify notification service to reconnect with new token and user ID
          if (_onLoginCallback != null && _currentUser != null) {
            try {
              await _onLoginCallback!(_currentUser!.id);
            } catch (e) {
              debugPrint('⚠️ FETCHME: Error calling notification callback: $e');
            }
          }

          return true;
        } catch (e) {
          debugPrint('❌ FETCHME: Error parsing user data: $e');
          return false;
        }
      } else if (response.statusCode == 401) {
        debugPrint('❌ FETCHME: Token invalid or expired');
        return false;
      } else {
        debugPrint('❌ FETCHME: Server error - ${response.statusCode}');
        return false;
      }
    } on SocketException catch (e) {
      debugPrint('❌ FETCHME: Network error - $e');
      return false;
    } on TimeoutException catch (e) {
      debugPrint('❌ FETCHME: Request timeout - $e');
      return false;
    } catch (e) {
      debugPrint('❌ FETCHME: Unexpected error - $e');
      return false;
    }
  }

  Future<void> logout([BuildContext? ctx]) async {
    // CRITICAL FIX: Call logout callback before clearing user
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

  // --- Bus Pinning ---
  Future<void> pinBus(String busNumber) async {
    if (_currentUser == null) return;
    final pinned = List<String>.from(_currentUser!.pinnedBuses);
    if (!pinned.contains(busNumber)) {
      pinned.add(busNumber);
      _currentUser = _currentUser!.copyWith(pinnedBuses: pinned);
      await updateUser(_currentUser!);
    }
  }

  Future<void> unpinBus(String busNumber) async {
    if (_currentUser == null) return;
    final pinned = List<String>.from(_currentUser!.pinnedBuses);
    pinned.remove(busNumber);
    _currentUser = _currentUser!.copyWith(pinnedBuses: pinned);
    await updateUser(_currentUser!);
  }

  bool isBusPinned(String busNumber) =>
      _currentUser?.pinnedBuses.contains(busNumber) ?? false;

  Future<void> updateUser(User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentUserKey, json.encode(user.toJson()));
    notifyListeners();
  }
}
