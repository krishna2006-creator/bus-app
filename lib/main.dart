import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart' show DefaultFirebaseOptions;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'theme.dart';
import 'models/user.dart';
import 'models/bus.dart';
import 'models/uploaded_file.dart';
import 'services/auth_service.dart';
import 'services/api_service.dart';
import 'services/bus_service.dart';
import 'services/location_service.dart';
import 'services/announcement_service.dart';
import 'services/notification_service.dart';
import 'services/request_service.dart';
import 'services/trip_service.dart';
import 'services/file_service.dart';
import 'services/live_tracking_service.dart';
import 'services/pinned_bus_monitor_service.dart';
import 'services/feedback_service.dart';
import 'package:agni_college_bus_tracker/providers/stop_prediction_provider.dart';
import 'screens/home_page.dart';
import 'screens/login_page.dart';
import 'screens/admin/admin_dashboard.dart';
import 'screens/student/student_dashboard.dart';
import 'screens/staff/staff_dashboard.dart';
import 'screens/driver/driver_dashboard.dart';
import 'screens/admin/add_bus_page.dart';
import 'screens/admin/edit_bus_page.dart';
import 'screens/admin/manage_drivers_page.dart';
import 'screens/common/announcements_page.dart';
import 'screens/admin/requests_form_page.dart';
import 'screens/common/request_form_page.dart';
import 'screens/common/my_requests_page.dart';
import 'screens/common/track_bus_page.dart';
import 'screens/common/notifications_page.dart';
import 'screens/common/documents_page.dart';
import 'screens/student/student_share_location_screen.dart';
import 'screens/driver/driver_share_location_screen.dart';
import 'screens/file_viewer_screen.dart';
import 'screens/student/share_document_page.dart';
import 'screens/student/student_feedback_page.dart';
import 'screens/admin/admin_feedback_page.dart';
import 'package:agni_college_bus_tracker/screens/student/stop_prediction_screen_v2.dart';
import 'package:agni_college_bus_tracker/screens/student/pinned_bus_tracking_screen.dart';
import 'package:agni_college_bus_tracker/screens/student/shared_bus_tracking_screen.dart';
import 'package:agni_college_bus_tracker/screens/admin/admin_live_tracking_screen.dart';
import 'package:agni_college_bus_tracker/screens/common/bus_live_tracking_map_screen.dart';
import 'package:agni_college_bus_tracker/screens/common/live_tracking_map_screen.dart';

// Placeholder for StaffRequestsPage
class StaffRequestsPage extends StatelessWidget {
  const StaffRequestsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff Requests'),
      ),
      body: const Center(
        child: Text('Staff requests will be displayed here.'),
      ),
    );
  }
}

Future<void> safeInit(String name, Future<void> Function() fn) async {
  try {
    await fn();
  } catch (e) {
    debugPrint('Init failed: $name - $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (kIsWeb) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } else {
      await Firebase.initializeApp();
    }
  } catch (e) {
    debugPrint('Firebase init failed: $e');
  }

  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrint('Flutter Error: ${details.exception}');
    debugPrint('Stack trace: ${details.stack}');
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('Uncaught async error: $error');
    debugPrint('Stack trace: $stack');
    return true;
  };

  final navigatorKey = GlobalKey<NavigatorState>();
  final authService = AuthService(navigatorKey);
  final busService = BusService();
  final locationService = LocationService();
  final notificationService = NotificationService();
  final liveTrackingService = LiveTrackingService();
  final announcementService = AnnouncementService(notificationService);
  final requestService = RequestService(notificationService);
  final fileService = FileService(notificationService);
  final tripService = TripService();
  final feedbackService = FeedbackService(authService);
  final stopPredictionProvider = StopPredictionProvider();
  stopPredictionProvider.setLiveTrackingService(liveTrackingService);

  await safeInit('auth', () async => await authService.initialize());
  final authToken = await ApiService.getToken();

  await Future.wait([
    safeInit('bus', () => busService.initialize()),
    safeInit('location', () => locationService.initialize()),
    safeInit('announcement', () => announcementService.initialize()),
    safeInit(
        'notification',
        () => notificationService.initialize(
            authService.currentUser?.id, authToken)),
    safeInit('request', () => requestService.initialize()),
    safeInit('trip', () => tripService.initialize()),
    safeInit('file', () => fileService.initialize()),
    safeInit('feedback', () => feedbackService.initialize()),
  ]);

  authService.setNotificationCallback(
      (userId) => notificationService.reconnectAfterLogin(userId));
  locationService.listenToWebSocketUpdates(notificationService.messages);

  final pinnedBusMonitorService = PinnedBusMonitorService(
    locationService,
    notificationService,
    authService,
  );
  
  // CRITICAL FIX: Always start monitoring for a logged-in user at launch. The
  // monitor is a cheap no-op when there are no pinned buses, but keeping it
  // running means a bus pinned later in the session is detected within ~1s.
  if (authService.currentUser != null) {
    debugPrint('🚌 Main: Starting pinned bus monitoring at launch');
    pinnedBusMonitorService.startMonitoring();
  } else {
    debugPrint('🚌 Main: No user logged in on startup');
  }

  authService.setLogoutCallback(() async {
    debugPrint('🚌 Main: Logout - stopping monitoring');
    pinnedBusMonitorService.stopMonitoring();
  });
  
  // CRITICAL FIX: Single merged post-login callback. The old code registered
  // TWO setNotificationCallback calls; the second overwrote the first, so the
  // notification-service reconnect after login was silently dropped. Both jobs
  // (reconnect notifications + (re)start pinned-bus monitoring) live here now.
  authService.setNotificationCallback((userId) async {
    debugPrint('🔄 Main: post-login callback for user $userId');
    try {
      await notificationService.reconnectAfterLogin(userId);
    } catch (e) {
      debugPrint('⚠️ Main: notification reconnect failed: $e');
    }
    await Future.delayed(const Duration(milliseconds: 500));
    if (authService.currentUser != null) {
      debugPrint('🌙 Main: (Re)starting pinned bus monitoring for user $userId');
      pinnedBusMonitorService.startMonitoring();
    }
  });

  runApp(MyApp(
    authService: authService,
    busService: busService,
    liveTrackingService: liveTrackingService,
    locationService: locationService,
    announcementService: announcementService,
    notificationService: notificationService,
    requestService: requestService,
    tripService: tripService,
    feedbackService: feedbackService,
    stopPredictionProvider: stopPredictionProvider,
    fileService: fileService,
    pinnedBusMonitorService: pinnedBusMonitorService,
    navigatorKey: navigatorKey,
  ));
}

class MyApp extends StatelessWidget {
  final AuthService authService;
  final BusService busService;
  final LiveTrackingService liveTrackingService;
  final LocationService locationService;
  final AnnouncementService announcementService;
  final NotificationService notificationService;
  final RequestService requestService;
  final TripService tripService;
  final FileService fileService;
  final FeedbackService feedbackService;
  final StopPredictionProvider stopPredictionProvider;
  final PinnedBusMonitorService pinnedBusMonitorService;
  final GlobalKey<NavigatorState> navigatorKey;

  const MyApp({
    super.key,
    required this.authService,
    required this.busService,
    required this.liveTrackingService,
    required this.locationService,
    required this.announcementService,
    required this.notificationService,
    required this.requestService,
    required this.tripService,
    required this.fileService,
    required this.feedbackService,
    required this.stopPredictionProvider,
    required this.pinnedBusMonitorService,
    required this.navigatorKey,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authService),
        ChangeNotifierProvider.value(value: busService),
        ChangeNotifierProvider.value(value: liveTrackingService),
        ChangeNotifierProvider.value(value: locationService),
        ChangeNotifierProvider.value(value: announcementService),
        ChangeNotifierProvider.value(value: notificationService),
        ChangeNotifierProvider.value(value: requestService),
        ChangeNotifierProvider.value(value: tripService),
        ChangeNotifierProvider.value(value: fileService),
        ChangeNotifierProvider.value(value: feedbackService),
        ChangeNotifierProvider.value(value: stopPredictionProvider),
        ChangeNotifierProvider.value(value: pinnedBusMonitorService),
      ],
      child: MaterialApp.router(
        title: 'Agni College Bus Tracker',
        debugShowCheckedModeBanner: false,
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: ThemeMode.light,
        routerConfig: GoRouter(
          navigatorKey: navigatorKey,
          initialLocation: '/',
          refreshListenable: authService,
          redirect: (context, state) {
            final loggedIn = authService.currentUser != null;
            final onLoginPage = state.matchedLocation == '/login';

            if (!loggedIn) {
              return onLoginPage ? null : '/';
            }

            final userRole = authService.currentUser!.role;
            if (loggedIn && (onLoginPage || state.matchedLocation == '/')) {
              switch (userRole) {
                case UserRole.admin:
                  return '/admin/dashboard';
                case UserRole.student:
                  return '/student/dashboard';
                case UserRole.staff:
                  return '/staff/dashboard';
                case UserRole.driver:
                  return '/driver/dashboard';
              }
            }

            return null;
          },
          routes: [
            GoRoute(
              path: '/',
              name: 'home',
              pageBuilder: (context, state) =>
                  MaterialPage(child: HomePage()),
            ),
            GoRoute(
              path: '/login',
              name: 'login',
              pageBuilder: (context, state) {
                final role = state.extra as UserRole?;
                return MaterialPage(
                    child: LoginPage(role: role ?? UserRole.student));
              },
            ),
            GoRoute(
              path: '/file-viewer',
              name: 'file-viewer',
              pageBuilder: (context, state) {
                final file = state.extra as UploadedFile;
                return MaterialPage(
                  child: FileViewerScreen(
                    filePath: file.path,
                    fileType: file.type,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/admin/dashboard',
              name: 'admin-dashboard',
              pageBuilder: (context, state) =>
                  const MaterialPage(child: AdminDashboard()),
            ),
            GoRoute(
              path: '/student/dashboard',
              name: 'student-dashboard',
              pageBuilder: (context, state) =>
                  const MaterialPage(child: StudentDashboard()),
            ),
            GoRoute(
              path: '/staff/dashboard',
              name: 'staff-dashboard',
              pageBuilder: (context, state) =>
                  const MaterialPage(child: StaffDashboard()),
            ),
            GoRoute(
              path: '/driver/dashboard',
              name: 'driver-dashboard',
              pageBuilder: (context, state) =>
                  const MaterialPage(child: DriverDashboard()),
            ),
            GoRoute(
              path: '/admin/add-bus',
              name: 'admin-add-bus',
              pageBuilder: (context, state) =>
                  const MaterialPage(child: AddBusPage()),
            ),
            GoRoute(
              path: '/admin/edit-bus',
              name: 'admin-edit-bus',
              pageBuilder: (context, state) {
                final bus = state.extra as Bus;
                return MaterialPage(child: EditBusPage(bus: bus));
              },
            ),
            GoRoute(
              path: '/admin/track-bus',
              name: 'admin-track-bus',
              pageBuilder: (context, state) {
                final bus = state.extra as Bus;
                return MaterialPage(child: TrackBusPage(bus: bus));
              },
            ),
            GoRoute(
              path: '/admin/announcements',
              name: 'admin-announcements',
              pageBuilder: (context, state) => const MaterialPage(
                  child: AnnouncementsPage(
                      title: 'Announcements', allowCreate: true)),
            ),
            GoRoute(
              path: '/admin/documents',
              name: 'admin-documents',
              pageBuilder: (context, state) =>
                  const MaterialPage(child: DocumentsPage()),
            ),
            GoRoute(
              path: '/admin/requests',
              name: 'admin-requests',
              pageBuilder: (context, state) =>
                  const MaterialPage(child: AdminRequestsPage()),
            ),
            GoRoute(
              path: '/admin/drivers',
              name: 'admin-drivers',
              pageBuilder: (context, state) =>
                  const MaterialPage(child: ManageDriversPage()),
            ),
            GoRoute(
              path: '/admin/live-tracking',
              name: 'admin-live-tracking',
              pageBuilder: (context, state) =>
                  const MaterialPage(child: AdminLiveTrackingScreen()),
            ),
            GoRoute(
              path: '/student/track-bus',
              name: 'student-track-bus',
              pageBuilder: (context, state) {
                final bus = state.extra as Bus;
                return MaterialPage(child: TrackBusPage(bus: bus));
              },
            ),
            GoRoute(
              path: '/student/share-location',
              name: 'student-share-location',
              pageBuilder: (context, state) {
                final bus = state.extra as Bus;
                return MaterialPage(
                    child: StudentShareLocationScreen(bus: bus));
              },
            ),
            GoRoute(
              path: '/student/share-document',
              name: 'student-share-document',
              pageBuilder: (context, state) =>
                  const MaterialPage(child: ShareDocumentPage()),
            ),
            GoRoute(
              path: '/student/announcements',
              name: 'student-announcements',
              pageBuilder: (context, state) => const MaterialPage(
                  child: AnnouncementsPage(title: 'Announcements')),
            ),
            GoRoute(
              path: '/student/documents',
              name: 'student-documents',
              pageBuilder: (context, state) =>
                  const MaterialPage(child: DocumentsPage()),
            ),
            GoRoute(
              path: '/student/stop-prediction',
              name: 'student-stop-prediction',
              pageBuilder: (context, state) =>
                  const MaterialPage(child: StopPredictionScreenV2()),
            ),
            GoRoute(
              path: '/student/pinned-buses',
              name: 'student-pinned-buses',
              pageBuilder: (context, state) {
                final buses = state.extra as List<Bus>? ?? [];
                return MaterialPage(
                  child: PinnedBusTrackingScreen(pinnedBuses: buses),
                );
              },
            ),
            GoRoute(
              path: '/student/shared-tracking/:busId',
              name: 'student-shared-tracking',
              pageBuilder: (context, state) {
                final bus = state.extra as Bus;
                return MaterialPage(
                  child: SharedBusTrackingScreen(bus: bus),
                );
              },
            ),
            GoRoute(
              path: '/student/request',
              name: 'student-request',
              pageBuilder: (context, state) =>
                  MaterialPage(child: RequestFormPage(title: 'New Request')),
            ),
            GoRoute(
              path: '/student/my-requests',
              name: 'student-my-requests',
              pageBuilder: (context, state) =>
                  const MaterialPage(child: MyRequestsPage()),
            ),
            GoRoute(
              path: '/staff/track-bus',
              name: 'staff-track-bus',
              pageBuilder: (context, state) {
                final bus = state.extra as Bus;
                return MaterialPage(child: TrackBusPage(bus: bus));
              },
            ),
            GoRoute(
              path: '/staff/announcements',
              name: 'staff-announcements',
              pageBuilder: (context, state) => const MaterialPage(
                  child: AnnouncementsPage(title: 'Announcements')),
            ),
            GoRoute(
              path: '/staff/documents',
              name: 'staff-documents',
              pageBuilder: (context, state) =>
                  const MaterialPage(child: DocumentsPage()),
            ),
            GoRoute(
              path: '/staff/requests',
              name: 'staff-requests',
              pageBuilder: (context, state) =>
                  const MaterialPage(child: StaffRequestsPage()),
            ),
            GoRoute(
              path: '/staff/request',
              name: 'staff-request',
              pageBuilder: (context, state) =>
                  MaterialPage(child: RequestFormPage(title: 'New Request')),
            ),
            GoRoute(
              path: '/staff/my-requests',
              name: 'staff-my-requests',
              pageBuilder: (context, state) =>
                  const MaterialPage(child: MyRequestsPage()),
            ),
            GoRoute(
              path: '/driver/share-location',
              name: 'driver-share-location',
              pageBuilder: (context, state) =>
                  const MaterialPage(child: DriverShareLocationScreen()),
            ),
            GoRoute(
              path: '/driver/announcements',
              name: 'driver-announcements',
              pageBuilder: (context, state) => const MaterialPage(
                  child: AnnouncementsPage(title: 'Announcements')),
            ),
            GoRoute(
              path: '/driver/documents',
              name: 'driver-documents',
              pageBuilder: (context, state) =>
                  const MaterialPage(child: DocumentsPage()),
            ),
            GoRoute(
              path: '/driver/request',
              name: 'driver-request',
              pageBuilder: (context, state) =>
                  MaterialPage(child: RequestFormPage(title: 'New Request')),
            ),
            GoRoute(
              path: '/driver/my-requests',
              name: 'driver-my-requests',
              pageBuilder: (context, state) =>
                  const MaterialPage(child: MyRequestsPage()),
            ),
            GoRoute(
              path: '/track-bus-maps',
              name: 'track-bus-maps',
              pageBuilder: (context, state) {
                final bus = state.extra as Bus;
                return MaterialPage(child: BusLiveTrackingMapScreen(bus: bus));
              },
            ),
            GoRoute(
              path: '/student/live-tracking',
              name: 'student-live-tracking',
              pageBuilder: (context, state) => MaterialPage(
                child: LiveTrackingMapScreen(showOnlyPinnedBuses: true),
              ),
            ),
            GoRoute(
              path: '/staff/live-tracking',
              name: 'staff-live-tracking',
              pageBuilder: (context, state) => MaterialPage(
                child: LiveTrackingMapScreen(showOnlyPinnedBuses: true),
              ),
            ),
            GoRoute(
              path: '/notifications',
              name: 'notifications',
              pageBuilder: (context, state) =>
                  const MaterialPage(child: NotificationsPage()),
            ),
            GoRoute(
              path: '/student/feedback',
              name: 'student-feedback',
              pageBuilder: (context, state) =>
                  const MaterialPage(child: StudentFeedbackPage()),
            ),
            GoRoute(
              path: '/admin/feedback',
              name: 'admin-feedback',
              pageBuilder: (context, state) =>
                  const MaterialPage(child: AdminFeedbackPage()),
            ),
          ],
        ),
      ),
    );
  }
}