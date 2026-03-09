import 'package:go_router/go_router.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_analytics/observer.dart';

import '../features/menu/menu_screen.dart';

final appRouter = GoRouter(
  observers: [FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance)],
  initialLocation: '/menu',
  routes: [
    GoRoute(
      path: '/menu',
      builder: (context, state) => const MenuScreen(),
    ),
  ],
);
