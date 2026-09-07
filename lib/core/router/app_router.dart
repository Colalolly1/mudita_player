import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/library/library_shell.dart';
import '../../features/now_playing/now_playing_screen.dart';
import '../../features/queue/queue_screen.dart';
import '../../features/search/search_screen.dart';
import '../../features/settings/settings_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/library',
    routes: [
      GoRoute(
        path: '/library',
        pageBuilder: (ctx, state) => _fade(state, const LibraryShell()),
      ),
      GoRoute(
        path: '/now-playing',
        pageBuilder: (ctx, state) => _slideUp(state, const NowPlayingScreen()),
      ),
      GoRoute(
        path: '/queue',
        pageBuilder: (ctx, state) => _slideUp(state, const QueueScreen()),
      ),
      GoRoute(
        path: '/search',
        pageBuilder: (ctx, state) => _fade(state, const SearchScreen()),
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (ctx, state) => _fade(state, const SettingsScreen()),
      ),
    ],
  );
});

CustomTransitionPage<T> _fade<T>(GoRouterState state, Widget child) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 150),
    transitionsBuilder: (_, anim, __, child) =>
        FadeTransition(opacity: anim, child: child),
  );
}

CustomTransitionPage<T> _slideUp<T>(GoRouterState state, Widget child) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 220),
    transitionsBuilder: (_, anim, __, child) {
      final tween = Tween(begin: const Offset(0, 1), end: Offset.zero)
          .chain(CurveTween(curve: Curves.easeOutCubic));
      return SlideTransition(position: anim.drive(tween), child: child);
    },
  );
}
