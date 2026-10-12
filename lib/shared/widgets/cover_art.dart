import 'dart:io';

import 'package:flutter/material.dart';

class CoverArt extends StatelessWidget {
  final String? artUri;
  final double size;
  final double radius;

  const CoverArt({
    super.key,
    required this.artUri,
    this.size = 56,
    this.radius = 4,
  });

  /// Convert any of the URI shapes we store (`file:///path`, `/path`,
  /// `http://...`) into something Image.* can actually load.
  static Widget? _imageFor(String uri,
      {double? width,
      double? height,
      BoxFit? fit,
      Widget? errorWidget,
      int? cacheWidth}) {
    if (uri.startsWith('http://') || uri.startsWith('https://')) {
      return Image.network(
        uri,
        width: width,
        height: height,
        fit: fit,
        cacheWidth: cacheWidth,
        errorBuilder: (_, __, ___) => errorWidget ?? const SizedBox.shrink(),
      );
    }
    String path = uri;
    if (path.startsWith('file://')) {
      path = path.substring(7);
    }
    return Image.file(
      File(path),
      width: width,
      height: height,
      fit: fit,
      cacheWidth: cacheWidth,
      errorBuilder: (_, __, ___) => errorWidget ?? const SizedBox.shrink(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: size == double.infinity ? null : size,
      height: size == double.infinity ? null : size,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(
        Icons.music_note,
        color: scheme.onSurfaceVariant,
        size: size == double.infinity ? 64 : size * 0.4,
      ),
    );

    if (artUri == null || artUri!.isEmpty) return placeholder;

    if (size != double.infinity) return _image(context, size, placeholder);
    // Full-width covers: take the size from the space they are given.
    return LayoutBuilder(builder: (context, c) {
      final side = c.hasBoundedWidth ? c.maxWidth : c.maxHeight;
      return _image(context, side, placeholder);
    });
  }

  /// Decode at the size the cover is shown, not the size of the file, so a
  /// big cover in a 44 px row doesn't cost a full-size bitmap.
  Widget _image(BuildContext context, double side, Widget placeholder) {
    final px = side * MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = px.isFinite && px > 0 ? px.round() : null;
    final w = size == double.infinity ? null : size;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: _imageFor(
            artUri!,
            width: w,
            height: w,
            fit: BoxFit.cover,
            errorWidget: placeholder,
            cacheWidth: cacheWidth,
          ) ??
          placeholder,
    );
  }
}
