import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'core/router/app_router.dart';
import 'core/theme/theme_controller.dart';
import 'playback/media_session_bridge.dart';
import 'playback/playback_controller.dart';

class MuditaApp extends ConsumerStatefulWidget {
  const MuditaApp({super.key});

  @override
  ConsumerState<MuditaApp> createState() => _MuditaAppState();
}

class _MuditaAppState extends ConsumerState<MuditaApp> {
  @override
  void initState() {
    super.initState();
    // After first frame, attempt to restore the last session so the user
    // picks up roughly where they left off after a crash or relaunch.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      MediaSessionBridge? bridge;
      try {
        // Eagerly construct the media-session bridge so the OS sees us as
        // an active media app the moment playback starts.
        bridge = ref.read(mediaSessionBridgeProvider);
      } catch (_) {}
      try {
        await ref
            .read(playbackControllerProvider.notifier)
            .restoreLastSession();
      } catch (_) {}
      // First-launch only: ask Mudita to stop killing us in the background,
      // so volume keys keep controlling music when the screen is off / we're
      // backgrounded. Without this the OS kills the media service.
      try {
        final prefs = ref.read(sharedPreferencesProvider);
        final asked = prefs.getBool(PrefsKeys.askedBatteryExemption) ?? false;
        if (!asked && bridge != null) {
          final exempt = await bridge.isBatteryExempt();
          if (!exempt) {
            await bridge.requestBatteryExemption();
          }
          await prefs.setBool(PrefsKeys.askedBatteryExemption, true);
        }
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeControllerProvider);
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Mudita Player',
      debugShowCheckedModeBanner: false,
      theme: lightThemeFor(theme),
      darkTheme: darkThemeFor(theme),
      themeMode: theme.materialMode,
      routerConfig: router,
      builder: (context, child) =>
          _BootErrorBanner(child: child ?? const SizedBox.shrink()),
    );
  }
}

/// Catches widget-build errors and shows them on screen instead of leaving
/// the user staring at the splash forever.
class _BootErrorBanner extends StatefulWidget {
  final Widget child;
  const _BootErrorBanner({required this.child});

  @override
  State<_BootErrorBanner> createState() => _BootErrorBannerState();
}

class _BootErrorBannerState extends State<_BootErrorBanner> {
  FlutterErrorDetails? _err;

  @override
  void initState() {
    super.initState();
    final prev = FlutterError.onError;
    FlutterError.onError = (details) {
      if (!mounted) {
        prev?.call(details);
        return;
      }
      setState(() => _err ??= details);
      prev?.call(details);
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_err != null) {
      return Material(
        color: Colors.black,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Mudita Player crashed at startup',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(
                      '${_err!.exception}\n\n${_err!.stack}',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => setState(() => _err = null),
                  child: const Text('Dismiss & continue'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return widget.child;
  }
}
