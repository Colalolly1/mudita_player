import 'package:flutter/material.dart';

/// A slim A–Z strip pinned to the right edge of a uniform-row ListView.
/// Tap or drag to jump to the first item starting with that letter.
///
/// Works by proportional offset (rows are uniform height), so it needs the
/// list's ScrollController, the total item count, and a resolver that maps
/// a letter to the first matching item index (or null when none).
class AlphabetScrollBar extends StatefulWidget {
  final ScrollController controller;
  final int itemCount;
  final int? Function(String letter) firstIndexForLetter;

  const AlphabetScrollBar({
    super.key,
    required this.controller,
    required this.itemCount,
    required this.firstIndexForLetter,
  });

  static const letters = [
    '#', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
  ];

  /// Sort/lookup key for a display string: uppercase first letter, or '#'
  /// for digits/symbols/empty.
  static String letterFor(String s) {
    if (s.isEmpty) return '#';
    final c = s[0].toUpperCase();
    return RegExp(r'[A-Z]').hasMatch(c) ? c : '#';
  }

  @override
  State<AlphabetScrollBar> createState() => _AlphabetScrollBarState();
}

class _AlphabetScrollBarState extends State<AlphabetScrollBar> {
  String? _active;

  void _jumpTo(String letter) {
    final idx = widget.firstIndexForLetter(letter);
    if (idx == null || widget.itemCount == 0) return;
    if (!widget.controller.hasClients) return;
    final pos = widget.controller.position;
    // Uniform rows: total content height = maxScrollExtent + viewport.
    final rowH =
        (pos.maxScrollExtent + pos.viewportDimension) / widget.itemCount;
    final target =
        (idx * rowH).clamp(0.0, pos.maxScrollExtent);
    widget.controller.jumpTo(target);
    setState(() => _active = letter);
  }

  void _handle(Offset local, double height) {
    final n = AlphabetScrollBar.letters.length;
    final i = ((local.dy / height) * n).floor().clamp(0, n - 1);
    _jumpTo(AlphabetScrollBar.letters[i]);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (ctx, constraints) {
      final h = constraints.maxHeight;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (d) => _handle(d.localPosition, h),
        onVerticalDragEnd: (_) => setState(() => _active = null),
        onTapDown: (d) => _handle(d.localPosition, h),
        onTapUp: (_) => setState(() => _active = null),
        child: Container(
          width: 22,
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final l in AlphabetScrollBar.letters)
                Expanded(
                  child: Center(
                    child: Text(
                      l,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight:
                            l == _active ? FontWeight.w700 : FontWeight.w400,
                        color: l == _active
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }
}
