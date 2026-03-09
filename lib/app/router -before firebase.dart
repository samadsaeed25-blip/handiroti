import 'package:go_router/go_router.dart';

import '../features/menu/menu_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/menu',
  routes: [
    GoRoute(
      path: '/menu',
      builder: (context, state) => const MenuScreen(),
    ),
  ],
);
