import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

/// Centralized push setup:
/// - requests permissions (iOS)
/// - creates Android channel
/// - registers FCM token to backend (guest + after login)
/// - listens for token refresh
/// - shows foreground notifications (local notification)
class NotificationService {
  NotificationService._();

  static final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();

  static bool _inited = false;
  static String? _customerPhone;
  static StreamSubscription<String>? _tokenSub;

  /// Set this to your API base URL (no trailing slash).
  /// Using your production domain as per current setup.
  static const String apiBaseUrl = 'https://order.handiroti.ae';

  /// Call once at app start (even in guest mode). This ensures broadcast pushes
  /// work for every installation.
  static Future<void> initGuest() async {
    await _initCore();
    await _registerTokenToServer(phone: null);
  }

  /// Call after login when you know the phone number. This links tokens to a customer
  /// so targeted pushes by phone work.
  static Future<void> setCustomerPhone(String phone) async {
    _customerPhone = phone.trim();
    await _initCore();
    await _registerTokenToServer(phone: _customerPhone);
  }

  static Future<void> _initCore() async {
    if (_inited) return;
    _inited = true;

    // iOS permission prompt (safe on Android too)
    try {
      await _fcm.requestPermission(alert: true, badge: true, sound: true);
    } catch (e) {
      debugPrint('[push] requestPermission failed: $e');
    }

    // Android notification channel (for high priority)
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'handiroti_high',
      'High Priority Notifications',
      description: 'Instant order updates and promotions',
      importance: Importance.max,
    );

    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosInit = DarwinInitializationSettings();

    await _local.initialize(const InitializationSettings(android: androidInit, iOS: iosInit));

    // Android 13+ runtime notifications permission
    try {
      await _local
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('[push] android notifications permission request failed: $e');
    }


    await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Foreground: show a local notification so user sees it instantly.
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final n = message.notification;
      if (n == null) return;

      _local.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        n.title,
        n.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'handiroti_high',
            'High Priority Notifications',
            importance: Importance.max,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    });

    // Token refresh: always update backend
    _tokenSub?.cancel();
    _tokenSub = _fcm.onTokenRefresh.listen((token) async {
      await _registerTokenToServer(phone: _customerPhone, tokenOverride: token);
    });
  }

  static Future<void> _registerTokenToServer({String? phone, String? tokenOverride}) async {
    try {
      final token = tokenOverride ?? await _fcm.getToken();
      if (token == null || token.trim().isEmpty) return;

      final uri = Uri.parse('$apiBaseUrl/api/customer/device_token');
      final payload = <String, dynamic>{
        'fcm_token': token,
        'platform': Platform.isIOS ? 'ios' : 'android',
      };
      if (phone != null && phone.trim().isNotEmpty) {
        payload['phone'] = phone.trim();
      }

      final resp = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        debugPrint('[push] device_token save failed ${resp.statusCode}: ${resp.body}');
      } else {
        debugPrint('[push] device_token saved (phone=${phone ?? 'guest'})');
      }
    } catch (e) {
      debugPrint('[push] registerToken error: $e');
    }
  }
}
