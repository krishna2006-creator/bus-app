import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:agni_college_bus_tracker/models/app_notification.dart';
import 'package:agni_college_bus_tracker/models/bus_location.dart';
import 'package:agni_college_bus_tracker/models/user.dart';
import 'package:agni_college_bus_tracker/services/api_service.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  debugPrint('Handling background notification: ${message.messageId}');
}

class NotificationService extends ChangeNotifier {
  static const _notificationsKey = 'notifications';
  static const _badgeCountKey = 'badge_count';
  List<AppNotification> _notifications = [];
  int _badgeCount = 0;
  WebSocketChannel? _channel;
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  List<AppNotification> get notifications => _notifications;
  int get badgeCount => _badgeCount;

  Future<void> initialize(String? userId, String? authToken) async {
    try {
      await _initLocalNotifications();
    } catch (e) {
      debugPrint('Failed to initialize local notifications: $e');
    }

    try {
      await requestPermissions();
    } catch (e) {
      debugPrint('Failed to request notification permissions: $e');
    }

    try {
      await _initializeFirebaseMessaging();
    } catch (e) {
      debugPrint('Failed to initialize FCM: $e');
    }

    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_notificationsKey);
    if (jsonStr != null) {
      try {
        final List decoded = json.decode(jsonStr);
        _notifications = decoded
            .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (e) {
        debugPrint('Failed to load notifications: $e');
      }
    }

    // Restore saved badge count and update app icon
    _badgeCount = prefs.getInt(_badgeCountKey) ?? 0;
    await _updateAppBadge();

    if (userId != null && authToken != null) {
      _connectNotificationWebSocket(userId, authToken);
    }
    notifyListeners();
  }

  Future<void> _initializeFirebaseMessaging() async {
    try {
      const androidChannel = AndroidNotificationChannel(
        'bus_tracking_channel',
        'Bus Tracking Notifications',
        description: 'Notifications for bus tracking updates and alerts',
        importance: Importance.high,
        sound: null,
      );

      await FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(androidChannel);

      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler);

      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null) {
        await _sendTokenToBackend(fcmToken);
      }
    } catch (e) {
      debugPrint('Error initializing Firebase Messaging: $e');
    }
  }

  Future<void> _sendTokenToBackend(String token) async {
    try {
      await ApiService.registerDeviceToken(token);
    } catch (e) {
      debugPrint('Failed to register FCM token: $e');
    }
  }

  void _handleForegroundMessage(RemoteMessage message) async {
    final notification = AppNotification(
      id: message.messageId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      userId: '',
      title: message.notification?.title ?? 'Notification',
      message: message.notification?.body ?? '',
      category: 'firebase',
      createdAt: DateTime.now(),
      soundEnabled: true,
    );
    await addNotification(notification);
  }

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _localNotificationsInitialized = false;

  Future<void> _initLocalNotifications() async {
    if (kIsWeb) return;
    if (_localNotificationsInitialized) return;

    const androidInit = AndroidInitializationSettings('');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (details) {},
    );

    _localNotificationsInitialized = true;
  }

  Future<void> requestPermissions() async {
    if (kIsWeb) return;

    var status = await Permission.notification.status;
    if (status.isDenied) {
      await Permission.notification.request();
    }

    var locStatus = await Permission.locationWhenInUse.status;
    if (locStatus.isDenied) {
      await Permission.locationWhenInUse.request();
    }

    await _initLocalNotifications();
  }

  Future<void> _connectNotificationWebSocket(
      String userId, String? authToken) async {
    try {
      final token = authToken ?? await ApiService.getToken();
      if (token == null) {
        debugPrint("No auth token available for WebSocket");
        return;
      }

      final baseUrl = ApiService.baseUrl.replaceFirst('http', 'ws');
      final uri = Uri.parse('$baseUrl/ws?token=$token');

      _channel = WebSocketChannel.connect(uri);
      _channel!.stream.listen((message) async {
        try {
          final data = json.decode(message);
          _messageController.add(data);

          if (data['type'] == 'NOTIFICATION') {
            final payload = data['payload'] ?? {};
            final n = AppNotification(
              id: payload['id'] ??
                  DateTime.now().millisecondsSinceEpoch.toString(),
              userId: userId,
              title: payload['title'] ?? 'Notification',
              message: payload['message'] ?? '',
              category: payload['category'] ?? 'default',
              createdAt: DateTime.now(),
              soundEnabled: true,
            );

            await addNotification(n);
          }
        } catch (e) {
          debugPrint("Notification WS Error: $e");
        }
      }, onError: (error) {
        debugPrint("Notification WebSocket error: $error");
        _scheduleNotificationReconnect(userId, token);
      }, onDone: () {
        _scheduleNotificationReconnect(userId, token);
      });
    } catch (e) {
      debugPrint("Failed to connect notification WebSocket: $e");
    }
  }

  void _scheduleNotificationReconnect(String userId, String token) {
    Future.delayed(const Duration(seconds: 5),
        () => _connectNotificationWebSocket(userId, token));
  }

  Future<void> reconnectAfterLogin(String userId) async {
    try {
      _channel?.sink.close();
      await Future.delayed(const Duration(milliseconds: 500));
      final token = await ApiService.getToken();
      if (token != null) {
        await _connectNotificationWebSocket(userId, token);
      }
    } catch (e) {
      debugPrint("Error reconnecting notification service: $e");
    }
  }

  Future<void> addNotification(AppNotification n) async {
    final now = DateTime.now();
    final existing = _notifications.firstWhere(
      (x) =>
          x.userId == n.userId &&
          x.title == n.title &&
          x.message == n.message &&
          now.difference(x.createdAt).inSeconds < 2,
      orElse: () => n,
    );

    if (existing.id != n.id) {
      debugPrint('Duplicate notification suppressed');
      return;
    }

    _notifications.insert(0, n);
    await _save();
    // Increment badge count when a new notification arrives
    _badgeCount++;
    await _updateAppBadge();
    notifyListeners();

    if (!kIsWeb) {
      try {
        final notifId = int.tryParse(n.id.toString()) ??
            (DateTime.now().millisecondsSinceEpoch ~/ 1000);

        await _localNotifications.show(
          id: notifId,
          title: n.title,
          body: n.message,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              'bus_tracking_channel',
              'Bus Tracking Notifications',
              channelDescription:
                  'Notifications for bus tracking updates and alerts',
              importance: Importance.high,
              priority: Priority.high,
              playSound: true,
              enableVibration: true,
              visibility: NotificationVisibility.public,
              icon: '@mipmap/ic_launcher',
              color: const Color(0xFF1976D2),
              channelShowBadge: true,
              enableLights: true,
              ledColor: const Color(0xFF1976D2),
              ledOnMs: 1000,
              ledOffMs: 500,
            ),
            iOS: const DarwinNotificationDetails(
              presentAlert: true,
              presentSound: true,
              presentBadge: true,
              sound: 'default.wav',
            ),
          ),
          payload: json.encode({'category': n.category, 'id': n.id}),
        );
      } catch (e) {
        debugPrint("Error showing local notification: $e");
      }
    }
  }

  Future<void> broadcastNotification(
      String title, String message, List<User> allUsers) async {
    try {
      await ApiService.createAnnouncement(title, message, 'all');
    } catch (e) {
      debugPrint('Error sending backend broadcast notification: $e');
    }

    final ts = DateTime.now();
    for (final u in allUsers) {
      final n = AppNotification(
        id: 'broadcast_${u.id}_${ts.millisecondsSinceEpoch}',
        userId: u.id,
        title: title,
        message: message,
        createdAt: ts,
        soundEnabled: true,
      );
      _notifications.insert(0, n);
      await addNotification(n);
    }
    await _save();
    notifyListeners();
  }

  Future<void> markRead(String id) async {
    final idx = _notifications.indexWhere((e) => e.id == id);
    if (idx == -1) return;
    _notifications[idx].read = true;
    await _save();
    // Decrement badge when a notification is read
    if (_badgeCount > 0) {
      _badgeCount--;
      await _updateAppBadge();
    }
    notifyListeners();
  }

  Future<void> deleteNotification(String id) async {
    _notifications.removeWhere((n) => n.id == id);
    await _save();
    // Decrement badge when a notification is deleted
    if (_badgeCount > 0) {
      _badgeCount--;
      await _updateAppBadge();
    }
    notifyListeners();
  }

  /// Clear all badge count (when user opens app or views all notifications)
  Future<void> clearBadge() async {
    _badgeCount = 0;
    await _updateAppBadge();
    notifyListeners();
  }

  /// Update the app icon badge on the home screen
  Future<void> _updateAppBadge() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_badgeCountKey, _badgeCount);
    try {
      if (!kIsWeb) {
        if (_badgeCount > 0) {
          if (await FlutterAppBadger.isAppBadgeSupported()) {
            FlutterAppBadger.updateBadgeCount(_badgeCount);
          }
        } else {
          FlutterAppBadger.removeBadge();
        }
      }
    } catch (e) {
      debugPrint("Error updating app badge: $e");
    }
  }

  List<AppNotification> forUser(String userId) {
    return _notifications.where((n) {
      if (n.userId == userId) return true;
      return false;
    }).toList();
  }

  Future<void> notifyPinnedUsers(BusLocation loc, List<User> allUsers) async {
    final bus = loc.busNumber;
    final ts = DateTime.now();
    for (final u in allUsers) {
      if ((u.role == UserRole.student || u.role == UserRole.staff) &&
          (u.pinnedBuses.contains(bus))) {
        final n = AppNotification(
          id: '${u.id}_${ts.millisecondsSinceEpoch}_$bus',
          userId: u.id,
          title: 'Bus $bus updated location',
          message: 'Bus $bus is on the move!',
          busNumber: bus,
          createdAt: ts,
          soundEnabled: true,
        );
        _notifications.insert(0, n);
        await addNotification(n);
      }
    }
    await _save();
    notifyListeners();
  }

  Future<void> notifyBusArriving(
      String userId, String busNumber, String pickupPoint) async {
    final notification = AppNotification(
      id: 'bus_arriving_${userId}_${DateTime.now().millisecondsSinceEpoch}',
      userId: userId,
      title: '🚌 Bus Arriving!',
      message: 'Bus $busNumber is arriving at $pickupPoint',
      createdAt: DateTime.now(),
      soundEnabled: true,
    );
    _notifications.insert(0, notification);
    await _save();
    notifyListeners();
    await addNotification(notification);
  }

  Future<void> notifyBusArrivedAtCollege(
      String userId, String busNumber) async {
    final notification = AppNotification(
      id: 'bus_arrived_${userId}_${DateTime.now().millisecondsSinceEpoch}',
      userId: userId,
      title: '✅ Arrived!',
      message: 'Bus $busNumber has arrived at college',
      createdAt: DateTime.now(),
      soundEnabled: true,
    );
    _notifications.insert(0, notification);
    await _save();
    notifyListeners();
    await addNotification(notification);
  }

  Future<void> notifyBusLeftBoarding(String userId, String busNumber) async {
    final notification = AppNotification(
      id: 'bus_left_boarding_${userId}_${DateTime.now().millisecondsSinceEpoch}',
      userId: userId,
      title: '🚗 Bus Departed',
      message: 'Bus $busNumber has left boarding point, heading to college',
      createdAt: DateTime.now(),
      soundEnabled: true,
    );
    _notifications.insert(0, notification);
    await _save();
    notifyListeners();
    await addNotification(notification);
  }

  Future<void> notifyDistanceUpdate(String userId, String busNumber,
      double distanceKm, int minutesETA) async {
    final notification = AppNotification(
      id: 'distance_${userId}_${DateTime.now().millisecondsSinceEpoch}',
      userId: userId,
      title: '📍 Bus Location',
      message:
          'Bus $busNumber is ${distanceKm.toStringAsFixed(1)} km away ($minutesETA min)',
      createdAt: DateTime.now(),
      soundEnabled: true,
    );
    _notifications.insert(0, notification);
    await _save();
    notifyListeners();
    await addNotification(notification);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = json.encode(_notifications.map((e) => e.toJson()).toList());
    await prefs.setString(_notificationsKey, jsonStr);
  }

  @override
  void dispose() {
    _messageController.close();
    _channel?.sink.close();
    super.dispose();
  }
}
