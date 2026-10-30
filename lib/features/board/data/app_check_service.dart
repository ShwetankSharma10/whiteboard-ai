import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

/// Service managing Firebase App Check and Google Play Integrity attestation.
/// Protects Firebase RTDB and backend endpoints from unauthorized clients.
class AppCheckService {
  const AppCheckService();

  static bool _isInitialized = false;

  /// Whether App Check is currently activated and enforcing tokens.
  static bool get isInitialized => _isInitialized;

  /// Initializes Firebase App Check with Play Integrity on Android
  /// and debug provider in development / local testing environments.
  static Future<void> initialize() async {
    try {
      // Check if Firebase Core is configured
      if (Firebase.apps.isEmpty) {
        debugPrint(
          '[AppCheck] Firebase not yet initialized. Skipping App Check activation (Local mode).',
        );
        return;
      }

      await FirebaseAppCheck.instance.activate(
        providerAndroid: kDebugMode
            ? const AndroidDebugProvider()
            : const AndroidPlayIntegrityProvider(),
        providerApple: const AppleAppAttestProvider(),
      );

      _isInitialized = true;
      debugPrint(
        '[AppCheck] Firebase App Check activated with ${kDebugMode ? "Debug Provider" : "Play Integrity"}.',
      );
    } catch (e) {
      debugPrint('[AppCheck] App Check activation skipped or failed: $e');
    }
  }

  /// Retrieves the current valid App Check attestation token, if available.
  Future<String?> getToken({bool forceRefresh = false}) async {
    if (!_isInitialized) return null;
    try {
      return await FirebaseAppCheck.instance.getToken(forceRefresh);
    } catch (e) {
      debugPrint('[AppCheck] Failed to retrieve token: $e');
      return null;
    }
  }
}
