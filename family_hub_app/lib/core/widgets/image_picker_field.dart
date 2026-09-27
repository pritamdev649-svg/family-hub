import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/services/cloudinary_service.dart';

import 'package:family_hub/core/widgets/app_network_image.dart';
import 'package:family_hub/core/widgets/snackbars.dart';

enum _PhotoAction { camera, gallery, remove }

/// Picks a photo (camera / gallery bottom sheet), uploads it through
/// [cloudinaryServiceProvider] and reports the resulting URL via [onChanged].
///
/// * Shows the picked image immediately with an upload progress overlay.
/// * Images are resized before upload (max 1600 px, JPEG quality 80).
/// * "Remove photo" reports `null`.
/// * Permission / upload errors are shown as localised snackbars; the previous
///   [imageUrl] stays in place.
/// * An upload still running when the field is disposed is cancelled.
class ImagePickerField extends ConsumerStatefulWidget {
  const ImagePickerField({
    super.key,
    this.imageUrl,
    required this.onChanged,
    required this.folder,
    this.size = 96,
    this.circular = false,
    this.label,
  });

  final String? imageUrl;
  final ValueChanged<String?> onChanged;
  final UploadFolder folder;
  final double size;
  final bool circular;
  final String? label;

  @override
  ConsumerState<ImagePickerField> createState() => _ImagePickerFieldState();
}

class _ImagePickerFieldState extends ConsumerState<ImagePickerField> {
  static const double _maxDimension = 1600;
  static const int _jpegQuality = 80;

  final ImagePicker _picker = ImagePicker();
  CancelToken? _cancelToken;
  String? _localPreview;
  double? _progress;
  bool _busy = false;

  bool get _hasImage => (widget.imageUrl ?? '').trim().isNotEmpty;

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  bool _supports(ImageSource source) {
    try {
      return _picker.supportsImageSource(source);
    } catch (_) {
      return source == ImageSource.gallery;
    }
  }

  Future<void> _openSheet() async {
    if (_busy) return;
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final canUseCamera = _supports(ImageSource.camera);

    final action = await showModalBottomSheet<_PhotoAction>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canUseCamera)
                ListTile(
                  leading: const Icon(AppIcons.camera),
                  title: Text(l10n.commonCamera),
                  onTap: () =>
                      Navigator.of(sheetContext).pop(_PhotoAction.camera),
                ),
              ListTile(
                leading: const Icon(AppIcons.gallery),
                title: Text(l10n.commonGallery),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_PhotoAction.gallery),
              ),
              if (_hasImage)
                ListTile(
                  leading: Icon(AppIcons.delete, color: scheme.error),
                  title: Text(
                    l10n.commonRemovePhoto,
                    style: TextStyle(color: scheme.error),
                  ),
                  onTap: () =>
                      Navigator.of(sheetContext).pop(_PhotoAction.remove),
                ),
            ],
          ),
        ),
      ),
    );

    if (!mounted || action == null) return;
    switch (action) {
      case _PhotoAction.remove:
        widget.onChanged(null);
      case _PhotoAction.camera:
        await _pickAndUpload(ImageSource.camera);
      case _PhotoAction.gallery:
        await _pickAndUpload(ImageSource.gallery);
    }
  }

  Future<void> _pickAndUpload(ImageSource source) async {
    final l10n = context.l10n;
    if (!_supports(source)) {
      context.showInfo(l10n.widgetPhotoSourceUnavailable);
      return;
    }

    XFile? file;
    try {
      file = await _picker.pickImage(
        source: source,
        maxWidth: _maxDimension,
        maxHeight: _maxDimension,
        imageQuality: _jpegQuality,
        requestFullMetadata: false,
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      final code = e.code.toLowerCase();
      if (code.contains('access_denied') || code.contains('permission')) {
        context.showInfo(l10n.widgetPhotoPermissionDenied);
      } else {
        context.showError(e);
      }
      return;
    } catch (e) {
      if (mounted) context.showError(e);
      return;
    }
    if (file == null || !mounted) return;
    final picked = file;

    final cancelToken = CancelToken();
    setState(() {
      _busy = true;
      _localPreview = picked.path;
      _progress = null;
      _cancelToken = cancelToken;
    });

    try {
      final url = await ref
          .read(cloudinaryServiceProvider)
          .uploadImage(
            picked,
            folder: widget.folder,
            cancelToken: cancelToken,
            onProgress: (p) {
              if (!mounted || !p.isFinite) return;
              setState(() => _progress = p.clamp(0.0, 1.0));
            },
          );
      if (!mounted) return;
      widget.onChanged(url);
    } catch (e) {
      if (mounted) context.showError(e);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _localPreview = null;
          _progress = null;
          _cancelToken = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final size = widget.size;
    final preview =
        _localPreview ?? (_hasImage ? widget.imageUrl!.trim() : null);

    final ShapeBorder shape = widget.circular
        ? const CircleBorder()
        : const RoundedRectangleBorder(borderRadius: AppRadius.brLg);

    final tile = Material(
      color: scheme.surfaceContainerHighest,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _busy ? null : _openSheet,
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (preview == null)
                Center(
                  child: Icon(
                    AppIcons.addPhoto,
                    size: AppSizes.iconLg,
                    color: scheme.onSurfaceVariant,
                  ),
                )
              else
                AppNetworkImage(url: preview, width: size, height: size),
              if (_busy)
                ColoredBox(
                  color: scheme.surface.withValues(
                    alpha: AppColors.scrimOpacity,
                  ),
                  child: Center(
                    child: SizedBox.square(
                      dimension: AppSizes.spinnerLg,
                      child: CircularProgressIndicator(
                        value: (_progress == null || _progress == 0)
                            ? null
                            : _progress,
                        strokeWidth: AppSizes.spinnerStroke,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    final badge = DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primary,
        shape: BoxShape.circle,
        border: Border.all(
          color: scheme.surface,
          width: AppSizes.borderFocused,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xs + AppSpacing.xxs),
        child: Icon(
          preview == null ? AppIcons.add : AppIcons.edit,
          size: AppSizes.iconXs,
          color: scheme.onPrimary,
        ),
      ),
    );

    return Semantics(
      button: true,
      enabled: !_busy,
      label: widget.label ?? l10n.widgetPhotoLabel,
      value: _busy ? l10n.commonUploading : null,
      hint: _busy ? null : l10n.commonChoosePhoto,
      onTap: _busy ? null : _openSheet,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: size,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(child: tile),
                if (!_busy)
                  PositionedDirectional(
                    end: widget.circular ? 0 : -AppSpacing.xs,
                    bottom: widget.circular ? 0 : -AppSpacing.xs,
                    child: IgnorePointer(child: badge),
                  ),
              ],
            ),
          ),
          if (_busy) ...[
            AppGap.sm,
            Text(
              l10n.commonUploading,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ] else if (widget.label != null) ...[
            AppGap.sm,
            Text(
              widget.label!,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelLarge,
            ),
          ],
        ],
      ),
    );
  }
}
