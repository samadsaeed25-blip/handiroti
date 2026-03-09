import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Push notifications helper (FCM)
///
/// ✅ Customer device tokens -> customer_devices
/// ✅ Staff device tokens    -> staff_devices (ONLY after staff PIN login)
///
/// Notes:
/// - We intentionally keep staff registration separate so customers never receive new-order alerts.
/// - Staff registration is "best effort": if one endpoint path differs on your server,
///   we try a few common fallbacks (no breaking changes).
class PushService {
  static final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  /// Customer registration endpoint
  static const String _customerRegisterUrl =
      'https://order.handiroti.ae/api/customer/device_token';

  /// Staff registration endpoint (preferred)
  static const String _staffRegisterUrl =
      'https://order.handiroti.ae/api/staff/device_token';

  /// Some builds used different paths — we try these if the preferred one is missing.
  static const List<String> _staffRegisterFallbackUrls = [
    'https://order.handiroti.ae/staff/device_token',
    'https://order.handiroti.ae/api/admin/staff/device_token',
    'https://order.handiroti.ae/admin/staff/device_token',
  ];

  /// Registers the current Firebase user device token with backend (CUSTOMER).
  /// Call after OTP login success.
  static Future<void> registerFromFirebaseUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await _fcm.requestPermission();

    final token = await _fcm.getToken();
    if (token == null) return;

    final phone = user.phoneNumber ?? '';

    await _sendJson(
      url: _customerRegisterUrl,
      payload: {
        'phone': phone,
        'fcm_token': token,
        'platform': Platform.isAndroid ? 'android' : 'ios',
      },
    );

    // Keep backend updated if token rotates
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      _sendJson(
        url: _customerRegisterUrl,
        payload: {
          'phone': phone,
          'fcm_token': newToken,
          'platform': Platform.isAndroid ? 'android' : 'ios',
        },
      );
    });
  }

  /// Registers this device as STAFF (kitchen/staff) so it can receive NEW ORDER alerts.
  ///
  /// Call ONLY after staff PIN login succeeds.
  ///
  /// Returns `true` if registration succeeded (HTTP 200/201), otherwise `false`.
  static Future<bool> registerStaffFromPin(String staffPin, {String? staffId}) async {
    await _fcm.requestPermission();

    final token = await _fcm.getToken();
    if (token == null) return false;

    final payload = {
      'staff_id': staffId ?? 'kitchen',
      'staff_pin': staffPin,
      'fcm_token': token,
      'platform': Platform.isAndroid ? 'android' : 'ios',
    };

    final ok1 = await _sendJson(
      url: _staffRegisterUrl,
      payload: payload,
      swallowErrors: true,
    );

    if (ok1) {
      _listenStaffTokenRefresh(staffPin, staffId: staffId);
      return true;
    }

    // Try fallbacks (some servers mount routes slightly differently)
    for (final u in _staffRegisterFallbackUrls) {
      final ok2 = await _sendJson(
        url: u,
        payload: payload,
        swallowErrors: true,
      );
      if (ok2) {
        _listenStaffTokenRefresh(staffPin, staffId: staffId);
        return true;
      }
    }

    // Still failed
    if (kDebugMode) {
      debugPrint('[PushService] staff device registration failed (all endpoints tried).');
    }
    return false;
  }

  static void _listenStaffTokenRefresh(String staffPin, {String? staffId}) {
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      final payload = {
        'staff_id': staffId ?? 'kitchen',
        'staff_pin': staffPin,
        'fcm_token': newToken,
        'platform': Platform.isAndroid ? 'android' : 'ios',
      };
      _sendJson(
        url: _staffRegisterUrl,
        payload: payload,
        swallowErrors: true,
      );
    });
  }

  static Future<bool> _sendJson({
    required String url,
    required Map<String, dynamic> payload,
    bool swallowErrors = true,
  }) async {
    try {
      final resp = await http.post(
        Uri.parse(url),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      // Accept 200/201 as success
      if (resp.statusCode == 200 || resp.statusCode == 201) return true;

      if (kDebugMode) {
        debugPrint('[PushService] POST $url -> ${resp.statusCode}: ${resp.body}');
      }
      return false;
    } catch (e) {
      if (!swallowErrors) rethrow;
      if (kDebugMode) {
        debugPrint('[PushService] POST $url failed: $e');
      }
      return false;
    }
  }
}
