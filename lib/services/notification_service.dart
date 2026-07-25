import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
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
  List<AppNotification> _notifications = [];
  WebSocketChannel? _channel;
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  List<AppNotification> get notifications => _notifications;

  Future<void> initialize(String? userId, String? authToken) async {
    try {
      await _initLocalNotifications();
    } catch (e) {
      debugPrint('Failed to initialize local notifications: $e');
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

    if (userId != null && authToken != null) {
      _connectNotificationWebSocket(userId, authToken);
    }
    notifyListeners();
  }

  Future<void> _initializeFirebaseMessaging() async {
    try {
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

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

  void _handleForegroundMessage(RemoteMessage message) {
    final notification = AppNotification(
      id: message.messageId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      userId: '',
      title: message.notification?.title ?? 'Notification',
      message: message.notification?.body ?? '',
      category: 'firebase',
      createdAt: DateTime.now(),
    );
    addNotification(notification);
  }

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _localNotificationsInitialized = false;

  Future<void> _initLocalNotifications() async {
    if (kIsWeb) return;
    if (_localNotificationsInitialized) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();

    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (details) {
        // No navigation from notification in this repo yet.
      },
    );

    _localNotificationsInitialized = true;
  }

  // NEW METHOD: Request Notification Permission
  Future<void> requestPermissions() async {
    if (kIsWeb) return;

    // Request OS permission (iOS/Android 13+)
    var status = await Permission.notification.status;
    if (status.isDenied) {
      await Permission.notification.request();
    }

    // For tracking features, we also need location permission
    var locStatus = await Permission.locationWhenInUse.status;
    if (locStatus.isDenied) {
      await Permission.locationWhenInUse.request();
    }

    await _initLocalNotifications();
  }

  Future<void> _connectNotificationWebSocket(
      String userId, String? authToken) async {
    try {
      // Use provided token or fetch from SharedPreferences
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
            );

            await addNotification(n);

            // Show OS notification with sound/alert (Android/iOS)
            if (!kIsWeb) {
              final notifId = int.tryParse(n.id.toString()) ??
                  (DateTime.now().millisecondsSinceEpoch ~/ 1000);

              await _localNotifications.show(
                id: notifId,
                title: n.title,
                body: n.message,
                notificationDetails: NotificationDetails(
                  android: const AndroidNotificationDetails(
                    'bus_alerts',
                    'Bus Alerts',
                    channelDescription: 'Bus tracking alerts',
                    importance: Importance.max,
                    priority: Priority.high,
                    playSound: true,
                  ),
                  iOS: const DarwinNotificationDetails(
                    presentAlert: true,
                    presentSound: true,
                  ),
                ),
                payload: json.encode({'category': n.category, 'id': n.id}),
              );
            }
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

  // Call this after successful login to reconnect WebSocket with new token
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
    _notifications.insert(0, n);
    await _save();
    notifyListeners();
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
      );
      _notifications.insert(0, n);
    }
    await _save();
    notifyListeners();
  }

  Future<void> markRead(String id) async {
    final idx = _notifications.indexWhere((e) => e.id == id);
    if (idx == -1) return;
    _notifications[idx].read = true;
    await _save();
    notifyListeners();
  }

  Future<void> deleteNotification(String id) async {
    _notifications.removeWhere((n) => n.id == id);
    await _save();
    notifyListeners();
  }

  List<AppNotification> forUser(String userId) =>
      _notifications.where((n) => n.userId == userId).toList();

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
        );
        _notifications.insert(0, n);
      }
    }
    await _save();
    notifyListeners();
  }

  // Tracking-specific notifications
  Future<void> notifyBusArriving(
      String userId, String busNumber, String pickupPoint) async {
    final notification = AppNotification(
      id: 'bus_arriving_${userId}_${DateTime.now().millisecondsSinceEpoch}',
      userId: userId,
      title: '🚌 Bus Arriving!',
      message: 'Bus $busNumber is arriving at $pickupPoint',
      createdAt: DateTime.now(),
    );
    _notifications.insert(0, notification);
    await _save();
    notifyListeners();
  }

  Future<void> notifyBusArrivedAtCollege(
      String userId, String busNumber) async {
    final notification = AppNotification(
      id: 'bus_arrived_${userId}_${DateTime.now().millisecondsSinceEpoch}',
      userId: userId,
      title: '✅ Arrived!',
      message: 'Bus $busNumber has arrived at college',
      createdAt: DateTime.now(),
    );
    _notifications.insert(0, notification);
    await _save();
    notifyListeners();
  }

  Future<void> notifyBusLeftBoarding(String userId, String busNumber) async {
    final notification = AppNotification(
      id: 'bus_left_boarding_${userId}_${DateTime.now().millisecondsSinceEpoch}',
      userId: userId,
      title: '🚗 Bus Departed',
      message: 'Bus $busNumber has left boarding point, heading to college',
      createdAt: DateTime.now(),
    );
    _notifications.insert(0, notification);
    await _save();
    notifyListeners();
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
    );
    _notifications.insert(0, notification);
    await _save();
    notifyListeners();
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
