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
        pageBuilder: (ctx, state) => _page(state, const LibraryShell()),
      ),
      GoRoute(
        path: '/now-playing',
        pageBuilder: (ctx, state) => _page(state, const NowPlayingScreen()),
      ),
      GoRoute(
        path: '/queue',
        pageBuilder: (ctx, state) => _page(state, const QueueScreen()),
      ),
      GoRoute(
        path: '/search',
        pageBuilder: (ctx, state) => _page(state, const SearchScreen()),
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (ctx, state) => _page(state, const SettingsScreen()),
      ),
    ],
  );
});

// No transitions: on e-ink every animation frame is a partial refresh, so a
// fade or slide shows up as smearing and ghosting. Screens just appear.
NoTransitionPage<T> _page<T>(GoRouterState state, Widget child) {
  return NoTransitionPage<T>(key: state.pageKey, child: child);
}
