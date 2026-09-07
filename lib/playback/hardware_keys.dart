import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/theme_controller.dart';
import 'playback_controller.dart';

enum HwKeyAction {
  none,
  playPause,
  next,
  previous,
  toggleShuffle,
  cycleRepeat,
  toggleFavorite,
}

extension HwKeyActionLabel on HwKeyAction {
  String get label => switch (this) {
        HwKeyAction.none => 'No action',
        HwKeyAction.playPause => 'Play / pause',
        HwKeyAction.next => 'Next track',
        HwKeyAction.previous => 'Previous track',
        HwKeyAction.toggleShuffle => 'Toggle shuffle',
        HwKeyAction.cycleRepeat => 'Cycle repeat',
        HwKeyAction.toggleFavorite => 'Toggle favorite',
      };

  String get id => name;

  static HwKeyAction fromId(String? id) {
    if (id == null) return HwKeyAction.none;
    return HwKeyAction.values.firstWhere(
      (a) => a.id == id,
      orElse: () => HwKeyAction.none,
    );
  }
}

class HardwareKeysController {
  static const _channel =
      MethodChannel('com.muditakompakt.mudita_player/hwkeys');

  final SharedPreferences prefs;
  final PlaybackController playback;

  HardwareKeysController(this.prefs, this.playback) {
    _channel.setMethodCallHandler(_onCall);
    _applyEnabled();
  }

  HwKeyAction get doubleTap =>
      HwKeyActionLabel.fromId(prefs.getString(PrefsKeys.hwKeyDoubleTap));
  HwKeyAction get longPress =>
      HwKeyActionLabel.fromId(prefs.getString(PrefsKeys.hwKeyLongPress));

  Future<void> setDoubleTap(HwKeyAction a) async {
    await prefs.setString(PrefsKeys.hwKeyDoubleTap, a.id);
    _applyEnabled();
  }

  Future<void> setLongPress(HwKeyAction a) async {
    await prefs.setString(PrefsKeys.hwKeyLongPress, a.id);
    _applyEnabled();
  }

  Future<void> _applyEnabled() async {
    final any = doubleTap != HwKeyAction.none || longPress != HwKeyAction.none;
    try {
      await _channel.invokeMethod('setEnabled', any);
    } catch (_) {}
  }

  Future<dynamic> _onCall(MethodCall call) async {
    if (call.method != 'hwKey') return;
    final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
    final gesture = args['gesture'] as String?;
    if (gesture == null) return;
    final action = switch (gesture) {
      'doubleTap' => doubleTap,
      'longPress' => longPress,
      _ => HwKeyAction.none,
    };
    await _runAction(action);
  }

  Future<void> _runAction(HwKeyAction a) async {
    switch (a) {
      case HwKeyAction.none:
        return;
      case HwKeyAction.playPause:
        await playback.toggle();
        break;
      case HwKeyAction.next:
        await playback.next();
        break;
      case HwKeyAction.previous:
        await playback.previous();
        break;
      case HwKeyAction.toggleShuffle:
        await playback.toggleShuffle();
        break;
      case HwKeyAction.cycleRepeat:
        await playback.cycleRepeat();
        break;
      case HwKeyAction.toggleFavorite:
        // Implemented via repository — handled at UI layer when needed.
        break;
    }
  }
}

final hardwareKeysProvider = Provider<HardwareKeysController>((ref) {
  return HardwareKeysController(
    ref.watch(sharedPreferencesProvider),
    ref.read(playbackControllerProvider.notifier),
  );
});
