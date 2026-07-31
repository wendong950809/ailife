import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../presentation/pages/auth/login_page.dart';
import '../../presentation/pages/auth/signup_page.dart';
import '../../presentation/pages/settings/settings_page.dart';
import '../../presentation/widgets/main_shell.dart';

class AppRouter {
  static GoRouter? _router;

  static GoRouter createRouter(AuthProvider authProvider) {
    // 缓存 GoRouter 实例，避免每次 AuthProvider notify 都重建导致路由重置
    if (_router != null) return _router!;

    _router = GoRouter(
      initialLocation: '/',
      redirect: (BuildContext context, GoRouterState state) {
        final isLoggedIn = authProvider.isAuthenticated;
        final loggingIn = state.matchedLocation == '/login' ||
            state.matchedLocation == '/signup';

        if (!isLoggedIn) {
          return loggingIn ? null : '/login';
        }

        if (loggingIn) {
          return '/';
        }

        return null;
      },
      refreshListenable: authProvider,
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const MainShell(),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginPage(),
        ),
        GoRoute(
          path: '/signup',
          builder: (context, state) => const SignupPage(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsPage(),
        ),
      ],
    );
    return _router!;
  }
}
