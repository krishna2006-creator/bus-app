// App configuration constants.

/// Application Configuration - Centralized constants
class AppConfig {
  // Backend Configuration
  static const String apiScheme =
      String.fromEnvironment('API_SCHEME', defaultValue: 'https');
  static const String wsScheme =
      String.fromEnvironment('WS_SCHEME', defaultValue: 'wss');

  static String get domain {
    const override = String.fromEnvironment('API_DOMAIN');
    if (override.isNotEmpty) {
      return override;
    }

    // Production backend URL (Render)
    const productionUrl = 'bus-app-7ito.onrender.com';

    // For web builds, use production URL
    // For mobile builds, use the override or fallback
    return productionUrl;
  }

  static String get baseUrl => '$apiScheme://$domain/api';
  static String get wsUrl => '$wsScheme://$domain';

  // API Keys
  static const String googleMapsApiKey = String.fromEnvironment('MAPS_API_KEY',
      defaultValue: 'AIzaSyAaxPNw_ihcEM97viIeqlpiD6XTMgU-6IE');

  // Map Configuration
  // Agni College of Technology, Old Mahabalipuram Road, Thalambur, Chennai – 600130
  // Correct Coordinates: 12.836371, 80.222332
  static const double collegeLatitude = 12.836371;
  static const double collegeLongitude = 80.222332;
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
