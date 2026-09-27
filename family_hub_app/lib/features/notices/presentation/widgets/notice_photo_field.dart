import 'dart:math' as math;

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/services/cloudinary_service.dart';
import 'package:family_hub/core/widgets/widgets.dart';

/// The notice form's photo: [ImagePickerField] (folder `notices`) that also
/// reports whether an upload is running, so the form can refuse to save a
/// notice while its photo is still on the way (it would be posted without
/// it) and can ask before discarding a running upload.
///
/// [ImagePickerField] has no busy callback, so the upload service is wrapped
/// for this field only (a nested [ProviderScope] override). If the shared
/// widget gains such a callback, this wrapper can go.
class NoticePhotoField extends ConsumerStatefulWidget {
  const NoticePhotoField({
    super.key,
    required this.imageUrl,
    required this.onChanged,
    required this.onUploadingChanged,
    this.label,
    this.enabled = true,
    this.size = defaultSize,
  });

  /// Side of the square picker — a big, easy target (the shared default is
  /// avatar-sized).
  static const double defaultSize = AppSizes.thumbnail * 3;

  final String? imageUrl;
  final ValueChanged<String?> onChanged;

  /// `true` when an upload starts, `false` when it ends (success, error or
  /// cancel).
  final ValueChanged<bool> onUploadingChanged;
  final String? label;
  final bool enabled;

  /// Side of the square picker; shrinks to the available width.
  final double size;

  @override
  ConsumerState<NoticePhotoField> createState() => _NoticePhotoFieldState();
}

class _NoticePhotoFieldState extends ConsumerState<NoticePhotoField> {
  late final _UploadTrackingService _service = _UploadTrackingService(
    // Resolved per upload from this widget's (outer) scope, so the real
    // service is always the current one.
    () => ref.read(cloudinaryServiceProvider),
    (uploading) {
      if (mounted) widget.onUploadingChanged(uploading);
    },
  );

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !widget.enabled,
      child: ProviderScope(
        overrides: [cloudinaryServiceProvider.overrideWithValue(_service)],
        child: LayoutBuilder(
          builder: (context, constraints) => ImagePickerField(
            imageUrl: widget.imageUrl,
            folder: UploadFolder.notices,
            label: widget.label,
            size: constraints.hasBoundedWidth
                ? math.min(widget.size, constraints.maxWidth)
                : widget.size,
            onChanged: widget.onChanged,
          ),
        ),
      ),
    );
  }
}

/// Delegates to the real [CloudinaryService] and counts running uploads.
class _UploadTrackingService implements CloudinaryService {
  _UploadTrackingService(this._delegate, this._onUploadingChanged);

  final CloudinaryService Function() _delegate;
  final ValueChanged<bool> _onUploadingChanged;
  int _running = 0;

  @override
  int get maxBytes => _delegate().maxBytes;

  @override
  Future<String> uploadImage(
    XFile file, {
    required UploadFolder folder,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (_running++ == 0) _onUploadingChanged(true);
    try {
      return await _delegate().uploadImage(
        file,
        folder: folder,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
    } finally {
      if (--_running == 0) _onUploadingChanged(false);
    }
  }
}
