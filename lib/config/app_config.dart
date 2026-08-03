import 'package:flutter/foundation.dart' show kIsWeb;

// App configuration constants.

/// Application Configuration - Centralized constants
class AppConfig {
  // Backend Configuration
  // Debug mode uses http/ws for local testing; release uses https/wss for production
  static String get apiScheme {
    if (const bool.fromEnvironment('dart.vm.product') == false) {
      return 'http';
    }
    return String.fromEnvironment('API_SCHEME', defaultValue: 'https');
  }

  static String get wsScheme {
    if (const bool.fromEnvironment('dart.vm.product') == false) {
      return 'ws';
    }
    return String.fromEnvironment('WS_SCHEME', defaultValue: 'wss');
  }

  static String get domain {
    const override = String.fromEnvironment('API_DOMAIN');
    if (override.isNotEmpty) {
      return override;
    }

    // Production backend URL (Railway)
    const productionUrl = 'bus-app-production-2836.up.railway.app';

    // Local development URL
    // - Web browser (run on same PC): use localhost
    // - Android emulator: use 10.0.2.2
    // - Physical phone on same Wi-Fi: use your PC's local IP (192.168.29.123)
    const webLocalUrl = 'localhost:8000';
    const localUrl = '192.168.29.123:8000';

    // Use local URL for debug mode, production for release
    // This allows local testing without Railway
    if (const bool.fromEnvironment('dart.vm.product') == false) {
      // Debug mode - use local backend
      // Web (same PC) -> localhost; Android/others -> local IP
      if (kIsWeb) return webLocalUrl;
      return localUrl;
    }

    return productionUrl;
  }

  static String get baseUrl => '$apiScheme://$domain/api';
  static String get wsUrl => '$wsScheme://$domain';

  // API Keys
  static const String googleMapsApiKey = String.fromEnvironment('MAPS_API_KEY',
      defaultValue: 'AIzaSyAaxPNw_ihcEM97viIeqlpiD6XTMgU-6IE');

  // Map Configuration
  // Agni College of Technology, Old Mahabalipuram Road, Thalambur, Chennai – 600130
  // Correct Coordinates: 12.848476, 80.194434 (Agni College of Technology)
  static const double collegeLatitude = 12.848476;
  static const double collegeLongitude = 80.194434;
  static const String collegeName =
      'Agni College of Technology, Old Mahabalipuram Road, Thalambur, Chennai – 600130';

  // Map Zoom Levels
  static const double defaultZoom = 13.0;
  static const double detailedZoom = 15.0;
  static const double trackingZoom = 16.0;

  // Location Update Configuration
  static const Duration locationUpdateInterval = Duration(seconds: 5);
  static const Duration locationCleanupInterval = Duration(minutes: 1);
  static const int driverLocationTimeoutMinutes = 10;
  static const int studentLocationTimeoutMinutes = 5;

  // WebSocket Configuration
  static const Duration webSocketTimeout = Duration(seconds: 10);
  static const Duration webSocketReconnectInterval = Duration(seconds: 5);

  // GPS Validation Bounds
  static const double minLatitude = -90.0;
  static const double maxLatitude = 90.0;
  static const double minLongitude = -180.0;
  static const double maxLongitude = 180.0;

  // Speed Constraints
  static const double minSpeed = 0.0;
  static const double maxReasonableSpeed = 120.0; // km/h for bus

  // Distance Calculation
  static const double studentToCollegeThresholdMeters = 100.0;
}