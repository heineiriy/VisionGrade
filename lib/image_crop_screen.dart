import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

Future<Uint8List?> showImageCropper(
  BuildContext context,
  Uint8List imageBytes,
) {
  return showDialog<Uint8List>(
    context: context,
    useSafeArea: false,
    builder: (_) => _ImageCropScreen(imageBytes: imageBytes),
  );
}

class _ImageCropScreen extends StatefulWidget {
  const _ImageCropScreen({required this.imageBytes});

  final Uint8List imageBytes;

  @override
  State<_ImageCropScreen> createState() => _ImageCropScreenState();
}

class _ImageCropScreenState extends State<_ImageCropScreen> {
  ui.Image? _image;
  Rect? _cropRect;
  Rect? _imageRect;
  Offset? _dragStart;
  Rect? _cropStart;
  Offset? _resizeAnchor;
  bool _isResizing = false;
  bool _isDrawing = false;
  bool _isEncoding = false;
  bool _isLayoutReady = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _decodeImage();
  }

  Future<void> _decodeImage() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.imageBytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (frame.image.width <= 0 || frame.image.height <= 0) {
        frame.image.dispose();
        throw StateError('The selected photo has no image dimensions.');
      }
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => _image = frame.image);
    } catch (error) {
      if (mounted) setState(() => _loadError = 'Could not open photo: $error');
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Rect _fitImage(Size size, ui.Image image) {
    if (!size.width.isFinite ||
        !size.height.isFinite ||
        size.width <= 0 ||
        size.height <= 0 ||
        image.width <= 0 ||
        image.height <= 0) {
      return Rect.zero;
    }
    final scale = (size.width / image.width).clamp(
      0.0,
      size.height / image.height,
    );
    if (!scale.isFinite || scale <= 0) return Rect.zero;
    final width = image.width * scale;
    final height = image.height * scale;
    return Rect.fromLTWH(
      (size.width - width) / 2,
      (size.height - height) / 2,
      width,
      height,
    );
  }

  Rect _clampCrop(Rect rect, Rect bounds) {
    if (!_isFiniteRect(rect) ||
        !_isFiniteRect(bounds) ||
        bounds.width <= 0 ||
        bounds.height <= 0) {
      return Rect.zero;
    }
    final width = rect.width.clamp(
      bounds.width < 80 ? bounds.width : 80.0,
      bounds.width,
    );
    final height = rect.height.clamp(
      bounds.height < 80 ? bounds.height : 80.0,
      bounds.height,
    );
    final left = rect.left.clamp(bounds.left, bounds.right - width);
    final top = rect.top.clamp(bounds.top, bounds.bottom - height);
    return Rect.fromLTWH(left, top, width, height);
  }

  bool _isFiniteRect(Rect rect) =>
      rect.left.isFinite &&
      rect.top.isFinite &&
      rect.right.isFinite &&
      rect.bottom.isFinite;

  void _startCropGesture(DragStartDetails details, Rect imageRect) {
    final cropRect = _cropRect;
    final position = details.localPosition;
    _dragStart = position;
    _cropStart = cropRect;
    _resizeAnchor = null;
    _isDrawing = false;
    _isResizing = false;
    if (cropRect != null) {
      final corners = <(Offset, Offset)>[
        (cropRect.topLeft, cropRect.bottomRight),
        (cropRect.topRight, cropRect.bottomLeft),
        (cropRect.bottomLeft, cropRect.topRight),
        (cropRect.bottomRight, cropRect.topLeft),
      ];
      for (final (corner, anchor) in corners) {
        if ((position - corner).distance < 36) {
          _isResizing = true;
          _resizeAnchor = anchor;
          break;
        }
      }
    }
    if (!_isResizing && (cropRect == null || !cropRect.contains(position))) {
      _isDrawing = true;
      _cropStart = Rect.fromPoints(position, position);
    }
    _imageRect = imageRect;
  }

  void _updateCropGesture(DragUpdateDetails details) {
    final start = _dragStart;
    final crop = _cropStart;
    final imageRect = _imageRect;
    if (start == null || crop == null || imageRect == null) return;
    final delta = details.localPosition - start;
    setState(() {
      if (_isDrawing) {
        _cropRect = _clampCrop(
          Rect.fromPoints(start, details.localPosition),
          imageRect,
        );
      } else if (_isResizing && _resizeAnchor != null) {
        _cropRect = _clampCrop(
          Rect.fromPoints(_resizeAnchor!, details.localPosition),
          imageRect,
        );
      } else {
        _cropRect = _clampCrop(crop.shift(delta), imageRect);
      }
    });
  }

  Future<void> _applyCrop() async {
    final image = _image;
    final imageRect = _imageRect;
    final cropRect = _cropRect;
    if (image == null || imageRect == null || cropRect == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The photo is not ready to crop yet.')),
      );
      return;
    }
    if (!_isFiniteRect(imageRect) ||
        !_isFiniteRect(cropRect) ||
        imageRect.width <= 0 ||
        imageRect.height <= 0 ||
        cropRect.width <= 0 ||
        cropRect.height <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wait for the photo to finish loading.')),
      );
      return;
    }

    setState(() => _isEncoding = true);
    try {
      final scaleX = image.width / imageRect.width;
      final scaleY = image.height / imageRect.height;
      final sourceRect = Rect.fromLTWH(
        (cropRect.left - imageRect.left) * scaleX,
        (cropRect.top - imageRect.top) * scaleY,
        cropRect.width * scaleX,
        cropRect.height * scaleY,
      );
      if (!_isFiniteRect(sourceRect) ||
          sourceRect.width <= 0 ||
          sourceRect.height <= 0) {
        throw StateError('The selected crop area is invalid.');
      }
      final outputWidth = sourceRect.width.round().clamp(1, image.width);
      final outputHeight = sourceRect.height.round().clamp(1, image.height);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        image,
        sourceRect,
        Rect.fromLTWH(0, 0, outputWidth.toDouble(), outputHeight.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );
      final picture = recorder.endRecording();
      final croppedImage = await picture.toImage(outputWidth, outputHeight);
      picture.dispose();
      final data = await croppedImage.toByteData(
        format: ui.ImageByteFormat.png,
      );
      croppedImage.dispose();
      if (data == null) throw StateError('Could not encode the cropped photo.');
      if (mounted) Navigator.of(context).pop(data.buffer.asUint8List());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not crop photo: $error')));
        setState(() => _isEncoding = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('Crop photo'),
          leading: IconButton(
            tooltip: 'Cancel crop',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: image == null
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(
                    widget.imageBytes,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Could not display scanned photo: $error',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: _loadError == null
                        ? const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(color: Colors.white),
                              SizedBox(height: 12),
                              Text(
                                'Preparing crop tools…',
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          )
                        : Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _loadError!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                  ),
                ],
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  final imageRect = _fitImage(
                    Size(constraints.maxWidth, constraints.maxHeight),
                    image,
                  );
                  if (imageRect.width <= 0 || imageRect.height <= 0) {
                    _isLayoutReady = false;
                    return const Center(
                      child: Text(
                        'Preparing photo…',
                        style: TextStyle(color: Colors.white),
                      ),
                    );
                  }
                  final cropRect =
                      _cropRect ??
                      Rect.fromLTRB(
                        imageRect.left + imageRect.width * 0.08,
                        imageRect.top + imageRect.height * 0.08,
                        imageRect.right - imageRect.width * 0.08,
                        imageRect.bottom - imageRect.height * 0.08,
                      );
                  final cropWidth =
                      (cropRect.width * image.width / imageRect.width).round();
                  final cropHeight =
                      (cropRect.height * image.height / imageRect.height)
                          .round();
                  _imageRect = imageRect;
                  _isLayoutReady = true;
                  if (_cropRect == null) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && _cropRect == null) {
                        setState(() => _cropRect = cropRect);
                      }
                    });
                  }
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (details) =>
                        _startCropGesture(details, imageRect),
                    onPanUpdate: _updateCropGesture,
                    onPanEnd: (_) {
                      _dragStart = null;
                      _cropStart = null;
                    },
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(
                          widget.imageBytes,
                          fit: BoxFit.contain,
                          frameBuilder:
                              (context, child, frame, wasSynchronouslyLoaded) {
                                if (wasSynchronouslyLoaded || frame != null) {
                                  return child;
                                }
                                return const Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                  ),
                                );
                              },
                          errorBuilder: (context, error, stackTrace) => Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'Could not display scanned photo: $error',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                        CustomPaint(painter: _CropOverlayPainter(cropRect)),
                        Positioned(
                          left: cropRect.left,
                          top: cropRect.top,
                          width: cropRect.width,
                          height: cropRect.height,
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2.5,
                                ),
                              ),
                              child: Stack(
                                children: [
                                  for (final alignment in const [
                                    Alignment.topLeft,
                                    Alignment.topRight,
                                    Alignment.bottomLeft,
                                    Alignment.bottomRight,
                                  ])
                                    Align(
                                      alignment: alignment,
                                      child: Container(
                                        width: 14,
                                        height: 14,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.black54,
                                            width: 1,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 14,
                          child: Text(
                            'Drag inside to move · drag a corner to resize\n'
                            '$cropWidth × $cropHeight px',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              shadows: const [
                                Shadow(blurRadius: 4, color: Colors.black),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.all(14),
          child: Center(
            child: FilledButton.icon(
              onPressed:
                  _image == null ||
                      _cropRect == null ||
                      !_isLayoutReady ||
                      _isEncoding
                  ? null
                  : _applyCrop,
              icon: _isEncoding
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.crop),
              label: Text(
                _isEncoding
                    ? 'Cropping...'
                    : _image == null
                    ? 'Preparing photo...'
                    : 'Apply crop',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CropOverlayPainter extends CustomPainter {
  const _CropOverlayPainter(this.cropRect);

  final Rect cropRect;

  @override
  void paint(Canvas canvas, Size size) {
    final overlay = Paint()..color = Colors.black54;
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(cropRect);
    canvas.drawPath(outside, overlay);

    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.75)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (var section = 1; section < 3; section++) {
      final x = cropRect.left + cropRect.width * section / 3;
      final y = cropRect.top + cropRect.height * section / 3;
      canvas.drawLine(
        Offset(x, cropRect.top),
        Offset(x, cropRect.bottom),
        grid,
      );
      canvas.drawLine(
        Offset(cropRect.left, y),
        Offset(cropRect.right, y),
        grid,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter oldDelegate) =>
      cropRect != oldDelegate.cropRect;
}
