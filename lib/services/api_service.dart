import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:agni_college_bus_tracker/config/app_config.dart';

class ApiService {
  // Backend URL - dynamically loaded from AppConfig
  static String get baseUrl => AppConfig.baseUrl;

  static Future<void> postPublicLocation(
    int busId,
    double latitude,
    double longitude,
    bool isPublic, {
    double? speed,
  }) async {
    final url = Uri.parse('$baseUrl/buses/public-location');
    try {
      final response = await http.post(
        url,
        headers: await getHeaders(),
        body: json.encode({
          'bus_id': busId,
          'latitude': latitude,
          'longitude': longitude,
          'speed': speed ?? 0.0,
          'is_public': isPublic,
        }),
      );
      if (response.statusCode == 200) {
        // Success
        debugPrint('Location posted successfully');
      } else {
        debugPrint(
            'Failed to post public location: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('Exception while posting public location: $e');
    }
  }

  static Future<void> clearPublicLocation(int busId) async {
    final url = Uri.parse('$baseUrl/buses/public-location/$busId');
    try {
      final response = await http.delete(
        url,
        headers: await getHeaders(),
      );
      if (response.statusCode == 200) {
        debugPrint('Location cleared successfully');
      } else {
        debugPrint('Failed to clear location: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Exception while clearing location: $e');
    }
  }

  static Future<void> clearToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_token');
    } catch (e) {
      debugPrint('Exception while clearing token: $e');
    }
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  static Future<Map<String, String>> getHeaders() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<bool> pinBusByNumber(String busNumber) async {
    final url = Uri.parse('$baseUrl/students/pin-bus');
    try {
      final response = await http.post(
        url,
        headers: await getHeaders(),
        body: json.encode({'bus_number': busNumber}),
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint('Exception while pinning bus: $e');
      return false;
    }
  }

  static Future<bool> unpinBusByNumber(String busNumber) async {
    final url = Uri.parse('$baseUrl/students/unpin-bus');
    try {
      final response = await http.post(
        url,
        headers: await getHeaders(),
        body: json.encode({'bus_number': busNumber}),
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint('Exception while unpinning bus: $e');
      return false;
    }
  }

  static Future<bool> registerDeviceToken(String token,
      {String platform = 'android'}) async {
    final url = Uri.parse('$baseUrl/notifications/device-token');
    try {
      final response = await http.post(
        url,
        headers: await getHeaders(),
        body: json.encode({'token': token, 'platform': platform}),
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint('Exception while registering device token: $e');
      return false;
    }
  }

  static Future<bool> createAnnouncement(
      String title, String message, String targetRole) async {
    final url = Uri.parse('$baseUrl/announcements');
    try {
      final response = await http.post(
        url,
        headers: await getHeaders(),
        body: json.encode({
          'title': title,
          'message': message,
          'target_role': targetRole,
        }),
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint('Exception while creating announcement: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>?> getBusLocation(int busId) async {
    final url = Uri.parse('$baseUrl/buses/$busId/location');
    try {
      final response = await http.get(url, headers: await getHeaders());
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      debugPrint('Exception while getting bus location: $e');
    }
    return null;
  }

  static Future<List<dynamic>?> getStops() async {
    final url = Uri.parse('$baseUrl/stops');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) return json.decode(response.body);
    } catch (e) {
      debugPrint('Exception while getting stops: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> getUserProfile() async {
    final url = Uri.parse('$baseUrl/auth/me');
    try {
      final response = await http.get(url, headers: await getHeaders());
      if (response.statusCode == 200) return json.decode(response.body);
    } catch (e) {
      debugPrint('Exception while getting user profile: $e');
    }
    return null;
  }

  static Future<bool> updateUserBoardingStop(int stopId) async {
    final primaryUrl = Uri.parse('$baseUrl/students/me/boarding_stop/$stopId');
    final fallbackUrl =
        Uri.parse('$baseUrl/students/me/boarding_stop?stop_id=$stopId');

    try {
      final response = await http.put(primaryUrl, headers: await getHeaders());
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return true;
      }

      debugPrint(
          'Primary boarding stop update failed: ${response.statusCode} ${response.body}');
      if (response.statusCode == 404 || response.statusCode == 405) {
        final fallbackResponse =
            await http.put(fallbackUrl, headers: await getHeaders());
        if (fallbackResponse.statusCode >= 200 &&
            fallbackResponse.statusCode < 300) {
          debugPrint('Fallback boarding stop update succeeded');
          return true;
        }
        debugPrint(
            'Fallback boarding stop update failed: ${fallbackResponse.statusCode} ${fallbackResponse.body}');
      }
      return false;
    } catch (e) {
      debugPrint('Exception while updating boarding stop: $e');
      return false;
    }
  }

  static Future<List<dynamic>?> getPredictions(int stopId) async {
    final url = Uri.parse('$baseUrl/predictions?stop_id=$stopId');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) return json.decode(response.body);
    } catch (e) {
      debugPrint('Exception while getting predictions: $e');
    }
    return null;
  }

  static Future<Map<String, double>?> getSavedPinForBus(int busId) async {
    final url = Uri.parse('$baseUrl/buses/$busId/pin');
    try {
      final response = await http.get(url, headers: await getHeaders());
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'latitude': double.parse(data['latitude'].toString()),
          'longitude': double.parse(data['longitude'].toString()),
        };
      }
    } catch (e) {
      debugPrint('Exception while getting saved pin for bus: $e');
    }
    return null;
  }

  static Future<bool> pinBus(
      int busId, double latitude, double longitude) async {
    final url = Uri.parse('$baseUrl/buses/$busId/pin');
    try {
      final response = await http.post(
        url,
        headers: await getHeaders(),
        body: json.encode({'latitude': latitude, 'longitude': longitude}),
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint('Exception while pinning bus: $e');
      return false;
    }
  }

  static Future<bool> unpinBus(int busId) async {
    final url = Uri.parse('$baseUrl/buses/$busId/pin');
    try {
      final response = await http.delete(url, headers: await getHeaders());
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Exception while unpinning bus: $e');
      return false;
    }
  }

  // Generic methods for tracking and other endpoints
  static Future<dynamic> get(String endpoint) async {
    final url = Uri.parse('$baseUrl$endpoint');
    try {
      final response = await http.get(
        url,
        headers: await getHeaders(),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('GET error on $endpoint: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> post(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    final url = Uri.parse('$baseUrl$endpoint');
    try {
      final response = await http.post(
        url,
        headers: await getHeaders(),
        body: json.encode(body),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return json.decode(response.body);
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('POST error on $endpoint: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> put(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    final url = Uri.parse('$baseUrl$endpoint');
    try {
      final response = await http.put(
        url,
        headers: await getHeaders(),
        body: json.encode(body),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('PUT error on $endpoint: $e');
      rethrow;
    }
  }
}
