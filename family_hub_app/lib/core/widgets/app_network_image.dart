import 'dart:io' show File;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';

/// Where an image reference points to.
enum AppImageKind { network, file, none }

/// Classifies an image reference stored in the app: `http(s)` URLs (Cloudinary)
/// or local file paths (uploads in mock mode without Cloudinary).
AppImageKind appImageKind(String? source) {
  final src = source?.trim() ?? '';
  if (src.isEmpty) return AppImageKind.none;
  final uri = Uri.tryParse(src);
  final scheme = uri?.scheme.toLowerCase() ?? '';
  if (scheme == 'http' || scheme == 'https') return AppImageKind.network;
  if (kIsWeb) return AppImageKind.none;
  // No scheme (absolute / relative path), `file://`, or a Windows drive letter.
  if (scheme.isEmpty || scheme == 'file' || scheme.length == 1) {
    return AppImageKind.file;
  }
  return AppImageKind.none;
}

String _filePath(String source) {
  final src = source.trim();
  final uri = Uri.tryParse(src);
  if (uri != null && uri.scheme.toLowerCase() == 'file') {
    return uri.toFilePath();
  }
  return src;
}

/// [ImageProvider] for an image reference (see [appImageKind]), decoded at
/// most [cacheWidth] physical pixels wide to save memory on low-end phones.
/// Returns `null` when there is nothing to show.
ImageProvider? appImageProvider(String? source, {int? cacheWidth}) {
  final ImageProvider provider;
  switch (appImageKind(source)) {
    case AppImageKind.network:
      provider = CachedNetworkImageProvider(source!.trim());
    case AppImageKind.file:
      provider = FileImage(File(_filePath(source!)));
    case AppImageKind.none:
      return null;
  }
  return ResizeImage.resizeIfNeeded(cacheWidth, null, provider);
}

/// Physical pixel width to decode an image shown [logicalWidth] wide.
int? cacheWidthFor(BuildContext context, double? logicalWidth) {
  if (logicalWidth == null || !logicalWidth.isFinite || logicalWidth <= 0) {
    return null;
  }
  return (logicalWidth * MediaQuery.devicePixelRatioOf(context)).round();
}

/// Displays an image reference:
/// * `http(s)` → cached network image (disk + memory cache),
/// * local file path (mock uploads) → `Image.file`,
/// * empty / broken / unsupported → a neutral placeholder icon.
class AppNetworkImage extends StatelessWidget {
  const AppNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.borderRadius,
  });

  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final cacheWidth = cacheWidthFor(context, width);

    final Widget image = switch (appImageKind(url)) {
      AppImageKind.network => CachedNetworkImage(
        imageUrl: url.trim(),
        fit: fit,
        width: width,
        height: height,
        memCacheWidth: cacheWidth,
        fadeInDuration: AppDurations.fast,
        fadeOutDuration: AppDurations.fast,
        placeholder: (_, _) =>
            _ImagePlaceholder(width: width, height: height, loading: true),
        errorWidget: (_, _, _) =>
            _ImagePlaceholder(width: width, height: height),
      ),
      AppImageKind.file => Image.file(
        File(_filePath(url)),
        fit: fit,
        width: width,
        height: height,
        cacheWidth: cacheWidth,
        errorBuilder: (_, _, _) =>
            _ImagePlaceholder(width: width, height: height),
      ),
      AppImageKind.none => _ImagePlaceholder(width: width, height: height),
    };

    if (borderRadius == null) return image;
    return ClipRRect(borderRadius: borderRadius!, child: image);
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder({this.width, this.height, this.loading = false});

  final double? width;
  final double? height;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      height: height,
      child: ColoredBox(
        color: scheme.surfaceContainerHighest,
        child: Center(
          child: loading
              ? null
              : Icon(
                  AppIcons.brokenImage,
                  size: AppSizes.iconLg,
                  color: scheme.onSurfaceVariant,
                ),
        ),
      ),
    );
  }
}
