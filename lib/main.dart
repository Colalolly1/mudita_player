import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/theme/theme_controller.dart';

Future<void> main() async {
  // Show errors on screen instead of just hanging on the splash if startup
  // throws — much better than staring at a logo forever.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };

  WidgetsFlutterBinding.ensureInitialized();

  // SAFE MODE: All non-essential native init wrapped in best-effort try/catch.
  // None of these will block app start.
  Future<void> safe(Future<void> Function() f) async {
    try {
      await f();
    } catch (e, st) {
      debugPrint('Startup task failed (non-fatal): $e\n$st');
    }
  }

  await safe(() async {
    await FlutterDisplayMode.setHighRefreshRate();
  });

  await safe(() async {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
    );
  });

  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const MuditaApp(),
    ),
  );
}
