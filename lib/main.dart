import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_analytics/firebase_analytics.dart';

import 'services/notification_service.dart';

import 'app/router.dart';
import 'features/staff/order_ringer.dart';
import 'features/staff/staff_orders_screen.dart';
import 'features/staff/staff_session.dart';

/// Background handler (kept minimal). The OS handles the notification UI + sound
/// when you send an FCM *notification* payload.
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // Firebase Analytics
  await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);
  unawaited(FirebaseAnalytics.instance.logAppOpen());
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Hide Android system bars in a Samsung Gallery-style way:
  // users can still reveal them with an edge swipe when needed.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await NotificationService.initGuest();
  runApp(const ProviderScope(child: HandiRotiApp()));
}

/// Premium Desi theme (Charcoal + Saffron + Ivory)
ThemeData buildHandiTheme() {
  const charcoal = Color(0xFF1C1C1E);
  const saffron = Color(0xFFE0A100);
  const ivory = Color(0xFFFAF9F6);
  const danger = Color(0xFFD64545);

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: ivory,
    fontFamily: 'Inter',
    colorScheme: ColorScheme.fromSeed(
      seedColor: saffron,
      brightness: Brightness.light,
      primary: charcoal,
      secondary: saffron,
      surface: Colors.white,
      error: danger,
    ),
  );

  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: charcoal,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 1.2,
      shadowColor: Colors.black.withOpacity(0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: EdgeInsets.zero,
    ),
    dividerColor: const Color(0xFFE6E6E6),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: saffron,
        foregroundColor: charcoal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: charcoal,
        side: const BorderSide(color: Color(0xFFE0E0E0)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE6E6E6)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE6E6E6)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: saffron, width: 1.2),
      ),
    ),
    textTheme: base.textTheme.copyWith(
      titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
      titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      titleSmall: base.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.25),
      bodySmall: base.textTheme.bodySmall?.copyWith(
        height: 1.25,
        color: const Color(0xFF6B7280),
      ),
    ),
    extensions: const <ThemeExtension<dynamic>>[],
  );
}

class HandiRotiApp extends ConsumerStatefulWidget {
  const HandiRotiApp({super.key});

  @override
  ConsumerState<HandiRotiApp> createState() => _HandiRotiAppState();
}

class _HandiRotiAppState extends ConsumerState<HandiRotiApp> {
  final OrderRinger _ringer = OrderRinger();

  bool _isNewOrderMessage(RemoteMessage message) {
    final kind = (message.data['kind'] ?? '').toString().toLowerCase();
    if (kind == 'new_order') return true;

    // Some FCM sends arrive without `data.kind` (notification-only).
    // Fall back to a few safe heuristics.
    final title = (message.notification?.title ?? '').toLowerCase();
    final body = (message.notification?.body ?? '').toLowerCase();
    if (title.contains('new order') || body.contains('new order')) return true;

    // Many of our order pushes include one of these keys.
    if (message.data.containsKey('order_id') || message.data.containsKey('orderId')) return true;

    return false;
  }


  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onMessageOpenedSub;

  BuildContext? _rootContext;

  @override
  void initState() {
    super.initState();

    // Foreground messages:
    // Do NOT ring or show a popup while the staff app is open on screen.
    // New-order alerts should only be seen when the app is backgrounded/closed,
    // where the OS will show the FCM notification normally for registered staff devices.
    _onMessageSub = FirebaseMessaging.onMessage.listen((message) async {
      final isStaff = ref.read(staffAuthedProvider);
      final kind = (message.data['kind'] ?? '').toString();
      final isNewOrder = _isNewOrderMessage(message);
      debugPrint('[FCM][onMessage] isStaff=$isStaff kind=$kind isNewOrder=$isNewOrder title=${message.notification?.title} dataKeys=${message.data.keys.toList()}');
      if (!isStaff) return; // Customers must never behave like staff devices.
      if (!isNewOrder) return;

      // Intentionally no ringing / popup in foreground.
      // Background + terminated state notifications are handled by the OS.
      return;
    });

    // If user taps the notification: stop ringer and (optionally) open staff orders.
    _onMessageOpenedSub = FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final isStaff = ref.read(staffAuthedProvider);
      if (!isStaff) return;
      _ringer.stop();

      // Best-effort: if you have a staff orders screen accessible, open it.
      final ctx = _rootContext;
      if (ctx != null) {
        Navigator.of(ctx).push(
          MaterialPageRoute(builder: (_) => const StaffOrdersScreen()),
        );
      }
    });
  }

  void _showNewOrderPopup(RemoteMessage message) {
    final ctx = _rootContext;
    if (ctx == null) return;

    final title = (message.notification?.title ?? '🛎️ New Order').toString();
    final body = (message.notification?.body ?? 'A new order has arrived.').toString();

    // Avoid stacking multiple dialogs
    final nav = Navigator.of(ctx);
    if (nav.canPop()) {
      // If something is already open (rare), just show a snackbar.
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text(body),
          action: SnackBarAction(
            label: 'OPEN',
            onPressed: () {
              _ringer.stop();
              Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => const StaffOrdersScreen()));
            },
          ),
        ),
      );
      return;
    }

    showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (dctx) {
        return AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () {
                _ringer.stop();
                Navigator.of(dctx).pop();
              },
              child: const Text('Silence'),
            ),
            FilledButton(
              onPressed: () {
                _ringer.stop();
                Navigator.of(dctx).pop();
                Navigator.of(ctx).push(
                  MaterialPageRoute(builder: (_) => const StaffOrdersScreen()),
                );
              },
              child: const Text('Open Orders'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _onMessageSub?.cancel();
    _onMessageOpenedSub?.cancel();
    _ringer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Handi Roti',
      theme: buildHandiTheme(),
      routerConfig: appRouter,
      builder: (context, child) {
        _rootContext = context;
        final body = child ?? const SizedBox.shrink();

        return Stack(
          fit: StackFit.expand,
          children: [
            body,
            IgnorePointer(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  top: false,
                  minimum: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                  child: Opacity(
                    opacity: 0.55,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.bolt_rounded,
                          size: 12,
                          color: Color(0xFFE0A100),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'HorizonX',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
