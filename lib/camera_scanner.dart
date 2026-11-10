import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'app_theme.dart';

class HardcopyScanner {
  HardcopyScanner._();

  static Future<List<XFile>?> capture(BuildContext context) async {
    List<CameraDescription> cameras;
    try {
      cameras = await availableCameras();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Camera access failed: $error')));
      }
      return null;
    }
    if (!context.mounted || cameras.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No camera is available on this device.'),
          ),
        );
      }
      return null;
    }

    final rearCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    if (!context.mounted) return null;
    final navigator = Navigator.of(context);
    try {
      return await navigator.push<List<XFile>>(
        MaterialPageRoute(
          builder: (_) => _CameraCapturePage(camera: rearCamera),
          fullscreenDialog: true,
        ),
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to open camera: $error')),
        );
      }
      return null;
    }
  }
}

class _CameraCapturePage extends StatefulWidget {
  final CameraDescription camera;

  const _CameraCapturePage({required this.camera});

  @override
  State<_CameraCapturePage> createState() => _CameraCapturePageState();
}

class _CameraCapturePageState extends State<_CameraCapturePage> {
  late final CameraController _controller;
  late final Future<void> _initialization;
  bool _capturing = false;
  bool _showCapturedPreview = false;
  final List<XFile> _capturedImages = [];
  final List<Uint8List> _capturedBytes = [];
  XFile? _pendingImage;
  Uint8List? _pendingBytes;

  @override
  void initState() {
    super.initState();
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.high,
      enableAudio: false,
    );
    _initialization = _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _takePicture() async {
    if (_capturing || !_controller.value.isInitialized) return;
    setState(() {
      _capturing = true;
      _showCapturedPreview = false;
    });
    try {
      final image = await _controller.takePicture();
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() {
        _pendingImage = image;
        _pendingBytes = bytes;
        _showCapturedPreview = true;
      });
      final saveCapture = await _showCapturedPopup();
      if (!mounted) return;
      if (saveCapture && _pendingImage != null && _pendingBytes != null) {
        _capturedImages.add(_pendingImage!);
        _capturedBytes.add(_pendingBytes!);
      }
      setState(() {
        _pendingImage = null;
        _pendingBytes = null;
        _showCapturedPreview = false;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to capture image: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<bool> _showCapturedPopup() async {
    final saveCapture = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      elevation: 0,
      isDismissible: false,
      enableDrag: false,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _CaptureActionButton(
                icon: Icons.close,
                color: Colors.redAccent,
                onPressed: () => Navigator.of(sheetContext).pop(false),
              ),
              _CaptureActionButton(
                icon: Icons.check,
                color: Colors.greenAccent,
                onPressed: () => Navigator.of(sheetContext).pop(true),
              ),
            ],
          ),
        ),
      ),
    );
    return saveCapture ?? false;
  }

  void _saveCapturedPhotos() {
    if (_capturedImages.isNotEmpty) {
      Navigator.of(context).pop(List<XFile>.from(_capturedImages));
    }
  }

  void _deleteCapturedPhoto(int index) {
    setState(() {
      _capturedImages.removeAt(index);
      _capturedBytes.removeAt(index);
    });
  }

  Future<void> _showFullScreenImages(
    List<Uint8List> images,
    int initialIndex,
  ) async {
    if (images.isEmpty) return;
    await showDialog<void>(
      context: context,
      useSafeArea: false,
      builder: (_) =>
          _ScannedImageGallery(images: images, initialIndex: initialIndex),
    );
  }

  Future<void> _showCapturedImages() async {
    if (_capturedBytes.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF303030),
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GridView.builder(
            shrinkWrap: true,
            itemCount: _capturedBytes.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemBuilder: (context, index) => Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: GestureDetector(
                      onTap: () async {
                        await _showFullScreenImages(
                          _capturedBytes,
                          index,
                        );
                      },
                      child: Image.memory(
                        _capturedBytes[index],
                        fit: BoxFit.cover,
                        cacheWidth:
                            (MediaQuery.sizeOf(context).width *
                                    MediaQuery.devicePixelRatioOf(context) /
                                    3)
                                .round(),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: IconButton(
                    tooltip: 'Delete image',
                    onPressed: () {
                      _deleteCapturedPhoto(index);
                      if (_capturedBytes.isEmpty && sheetContext.mounted) {
                        Navigator.of(sheetContext).pop();
                      } else if (sheetContext.mounted) {
                        Navigator.of(sheetContext).pop();
                        _showCapturedImages();
                      }
                    },
                    icon: const Icon(Icons.delete_outline, color: Colors.white),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.burgundy,
      body: SafeArea(
        child: FutureBuilder<void>(
          future: _initialization,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Camera permission or initialization failed:\n${snapshot.error}',
                    style: const TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final previewBytes = _pendingBytes;
            final thumbnail = GestureDetector(
              onTap: _capturedBytes.isEmpty ? null : _showCapturedImages,
              child: _capturedBytes.isEmpty
                  ? const SizedBox(width: 42, height: 42)
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image.memory(
                        _capturedBytes.first,
                        width: 42,
                        height: 42,
                        fit: BoxFit.cover,
                      ),
                    ),
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Scan Assignment here',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Point your camera at the activity and capture it.',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 8, 28, 12),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5DED9),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: const Color(0xFFC8BBB4),
                          width: 7,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CameraPreview(_controller),
                            if (_showCapturedPreview && previewBytes != null)
                              GestureDetector(
                                onTap: () async {
                                  await _showFullScreenImages([
                                    previewBytes,
                                  ], 0);
                                },
                                child: Image.memory(
                                  previewBytes,
                                  fit: BoxFit.contain,
                                  cacheWidth:
                                      ((MediaQuery.sizeOf(context).width - 56) *
                                              MediaQuery.devicePixelRatioOf(
                                                context,
                                              ))
                                          .round(),
                                  frameBuilder:
                                      (
                                        context,
                                        child,
                                        frame,
                                        wasSynchronouslyLoaded,
                                      ) =>
                                          wasSynchronouslyLoaded ||
                                              frame != null
                                          ? child
                                          : const Center(
                                              child:
                                                  CircularProgressIndicator(),
                                            ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(36, 4, 36, 26),
                  child: Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: thumbnail,
                        ),
                      ),
                      Semantics(
                        button: true,
                        label: 'Capture assignment photo',
                        child: SizedBox(
                          width: 58,
                          height: 58,
                          child: Material(
                            color: Colors.transparent,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: _capturing ? null : _takePicture,
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2.5,
                                  ),
                                ),
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppPalette.burgundy,
                                  ),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: const Color(0xFFF2F2F2),
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2.5,
                                      ),
                                    ),
                                    child: _capturing
                                        ? const Padding(
                                            padding: EdgeInsets.all(11),
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: _capturedImages.isEmpty
                              ? FilledButton(
                                  onPressed: _capturing ? null : _takePicture,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF08A51A),
                                    minimumSize: const Size(0, 40),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    textStyle: const TextStyle(fontSize: 13),
                                  ),
                                  child: const Text('Scan'),
                                )
                              : FilledButton(
                                  onPressed: _saveCapturedPhotos,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF08A51A),
                                    minimumSize: const Size(0, 40),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 8,
                                    ),
                                    textStyle: const TextStyle(fontSize: 13),
                                  ),
                                  child: const Text('Scan'),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CaptureActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _CaptureActionButton({
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          shape: const CircleBorder(),
          side: const BorderSide(color: Colors.black, width: 1.2),
          padding: EdgeInsets.zero,
        ),
        child: Icon(icon, color: color, size: 32),
      ),
    );
  }
}

class _ScannedImageGallery extends StatefulWidget {
  const _ScannedImageGallery({
    required this.images,
    required this.initialIndex,
  });

  final List<Uint8List> images;
  final int initialIndex;

  @override
  State<_ScannedImageGallery> createState() => _ScannedImageGalleryState();
}

class _ScannedImageGalleryState extends State<_ScannedImageGallery> {
  late final PageController _pageController;
  late final List<Uint8List> _previewImages;
  late int _currentPage;

  @override
  void initState() {
    super.initState();
    _previewImages = List<Uint8List>.of(widget.images);
    _currentPage = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text('${_currentPage + 1} of ${_previewImages.length}'),
          leading: IconButton(
            tooltip: 'Close image',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(_previewImages),
          ),
        ),
        body: LayoutBuilder(
          builder: (context, constraints) => PageView.builder(
            controller: _pageController,
            itemCount: _previewImages.length,
            onPageChanged: (page) => setState(() => _currentPage = page),
            itemBuilder: (context, index) => Center(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 6,
                child: Image.memory(
                  _previewImages[index],
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  fit: BoxFit.contain,
                  cacheWidth:
                      (constraints.maxWidth *
                              MediaQuery.devicePixelRatioOf(context))
                          .round(),
                  frameBuilder:
                      (context, child, frame, wasSynchronouslyLoaded) {
                        if (wasSynchronouslyLoaded || frame != null) {
                          return child;
                        }
                        return const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        );
                      },
                  errorBuilder: (context, error, stackTrace) => const Center(
                    child: Text(
                      'Could not display this photo.',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
