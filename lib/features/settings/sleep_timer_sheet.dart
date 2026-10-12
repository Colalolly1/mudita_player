import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/theme_controller.dart';
import '../../playback/playback_controller.dart';

final sleepTimerProvider =
    StateNotifierProvider<SleepTimerController, DateTime?>((ref) {
  return SleepTimerController(ref);
});

/// The state is the clock time the music will stop at, or null when off. A
/// fixed time reads right whenever the sheet is opened; a countdown froze.
class SleepTimerController extends StateNotifier<DateTime?> {
  final Ref _ref;
  Timer? _timer;

  SleepTimerController(this._ref) : super(null);

  void start(Duration d) {
    cancel();
    state = DateTime.now().add(d);
    _timer = Timer(d, () async {
      final prefs = _ref.read(sharedPreferencesProvider);
      final fade = prefs.getBool(PrefsKeys.sleepFadeOut) ?? true;
      final pb = _ref.read(playbackControllerProvider.notifier);
      if (fade) {
        await pb.fadeOutAndPause(const Duration(seconds: 10));
      } else {
        await pb.pause();
      }
      state = null;
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    state = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class SleepTimerSheet extends ConsumerWidget {
  const SleepTimerSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(sleepTimerProvider);
    final ctrl = ref.read(sleepTimerProvider.notifier);
    final prefs = ref.watch(sharedPreferencesProvider);
    final options = const [5, 10, 15, 30, 45, 60, 90];
    final fade = prefs.getBool(PrefsKeys.sleepFadeOut) ?? true;

    final pb = ref.read(playbackControllerProvider.notifier);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('Sleep Timer',
                  style: Theme.of(context).textTheme.titleLarge),
            ),
            if (pb.stopAfterAlbum)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.stop_circle_outlined),
                title: const Text('Stopping at end of this album'),
                trailing: TextButton(
                  onPressed: () {
                    pb.stopAfterAlbum = false;
                    Navigator.pop(context);
                  },
                  child: const Text('Cancel'),
                ),
              ),
            if (pb.stopAfterCurrent)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.stop_circle_outlined),
                title: const Text('Stopping at end of this song'),
                trailing: TextButton(
                  onPressed: () {
                    pb.stopAfterCurrent = false;
                    Navigator.pop(context);
                  },
                  child: const Text('Cancel'),
                ),
              ),
            if (active != null) ...[
              Text(
                'Stops at ${TimeOfDay.fromDateTime(active).format(context)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () {
                  ctrl.cancel();
                  Navigator.pop(context);
                },
                child: const Text('Cancel timer'),
              ),
              const SizedBox(height: 12),
              const Divider(),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Fade out (10s)'),
              value: fade,
              onChanged: (v) async {
                await prefs.setBool(PrefsKeys.sleepFadeOut, v);
                (context as Element).markNeedsBuild();
              },
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.music_note, size: 16),
                  label: const Text('End of track'),
                  onPressed: () {
                    pb.stopAfterCurrent = true;
                    pb.stopAfterAlbum = false;
                    ctrl.cancel();
                    Navigator.pop(context);
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.album_outlined, size: 16),
                  label: const Text('End of album'),
                  onPressed: () {
                    pb.stopAfterAlbum = true;
                    pb.stopAfterCurrent = false;
                    ctrl.cancel();
                    Navigator.pop(context);
                  },
                ),
                ...options.map((m) {
                  return ActionChip(
                    label: Text('$m min'),
                    onPressed: () {
                      pb.stopAfterCurrent = false;
                      pb.stopAfterAlbum = false;
                      ctrl.start(Duration(minutes: m));
                      Navigator.pop(context);
                    },
                  );
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
