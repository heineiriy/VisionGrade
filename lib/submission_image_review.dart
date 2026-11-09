import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'image_crop_screen.dart';

class ReviewedSubmissionImage {
  const ReviewedSubmissionImage({required this.file, required this.bytes});

  final XFile file;
  final Uint8List bytes;
}

Future<List<ReviewedSubmissionImage>?> showSubmissionImageReview(
  BuildContext context,
  List<XFile> images,
) async {
  final selectedImages = await Future.wait(
    images.map(
      (image) async => ReviewedSubmissionImage(
        file: image,
        bytes: await image.readAsBytes(),
      ),
    ),
  );
  if (!context.mounted) return null;

  final pageController = PageController();
  final result = await showDialog<List<ReviewedSubmissionImage>>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      var currentPage = 0;
      final screenSize = MediaQuery.sizeOf(dialogContext);

      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Review your work'),
          content: SizedBox(
            width: screenSize.width * 0.8,
            height: screenSize.height * 0.46,
            child: Column(
              children: [
                Expanded(
                  child: selectedImages.isEmpty
                      ? const Center(child: Text('No photos selected.'))
                      : PageView.builder(
                          controller: pageController,
                          itemCount: selectedImages.length,
                          onPageChanged: (page) => setState(() {
                            currentPage = page;
                          }),
                          itemBuilder: (context, index) => Stack(
                            alignment: Alignment.center,
                            children: [
                              GestureDetector(
                                onTap: () async {
                                  final cropped = await _showFullScreenImage(
                                    context,
                                    selectedImages[index].bytes,
                                  );
                                  if (cropped == null || !context.mounted) {
                                    return;
                                  }
                                  setState(() {
                                    selectedImages[index] = ReviewedSubmissionImage(
                                      file: XFile.fromData(
                                        cropped,
                                        name:
                                            'cropped_${DateTime.now().millisecondsSinceEpoch}.png',
                                        mimeType: 'image/png',
                                      ),
                                      bytes: cropped,
                                    );
                                  });
                                },
                                child: Image.memory(
                                  selectedImages[index].bytes,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Center(
                                        child: Text(
                                          'Could not preview this image.',
                                        ),
                                      ),
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: IconButton.filled(
                                  tooltip: 'Remove photo',
                                  onPressed: () {
                                    setState(() {
                                      selectedImages.removeAt(index);
                                      if (selectedImages.isEmpty) {
                                        currentPage = 0;
                                      } else if (index < currentPage) {
                                        currentPage--;
                                      } else if (currentPage >=
                                          selectedImages.length) {
                                        currentPage = selectedImages.length - 1;
                                      }
                                    });
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                          if (pageController.hasClients &&
                                              selectedImages.isNotEmpty) {
                                            pageController.jumpToPage(
                                              currentPage,
                                            );
                                          }
                                        });
                                  },
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.black54,
                                    foregroundColor: Colors.white,
                                  ),
                                  icon: const Icon(Icons.close),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
                const SizedBox(height: 12),
                if (selectedImages.length > 1)
                  Text('Photo ${currentPage + 1} of ${selectedImages.length}'),
                TextButton.icon(
                  onPressed: () async {
                    final source = await showModalBottomSheet<ImageSource>(
                      context: dialogContext,
                      builder: (sheetContext) => SafeArea(
                        child: Wrap(
                          children: [
                            ListTile(
                              leading: const Icon(Icons.camera_alt_outlined),
                              title: const Text('Camera'),
                              onTap: () => Navigator.of(
                                sheetContext,
                              ).pop(ImageSource.camera),
                            ),
                            ListTile(
                              leading: const Icon(Icons.image_outlined),
                              title: const Text('Gallery'),
                              onTap: () => Navigator.of(
                                sheetContext,
                              ).pop(ImageSource.gallery),
                            ),
                          ],
                        ),
                      ),
                    );
                    if (!dialogContext.mounted || source == null) return;

                    try {
                      final picker = ImagePicker();
                      final XFile? cameraImage = source == ImageSource.camera
                          ? await picker.pickImage(
                              source: source,
                              imageQuality: 90,
                            )
                          : null;
                      final galleryImages = source == ImageSource.gallery
                          ? await picker.pickMultiImage(imageQuality: 90)
                          : <XFile>[];
                      final files = [?cameraImage, ...galleryImages];
                      if (files.isEmpty || !dialogContext.mounted) return;

                      final addedImages = await Future.wait(
                        files.map(
                          (file) async => ReviewedSubmissionImage(
                            file: file,
                            bytes: await file.readAsBytes(),
                          ),
                        ),
                      );
                      if (!dialogContext.mounted) return;

                      setState(() {
                        selectedImages.addAll(addedImages);
                        currentPage = selectedImages.length - 1;
                      });
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (pageController.hasClients) {
                          pageController.animateToPage(
                            currentPage,
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOut,
                          );
                        }
                      });
                    } catch (error) {
                      if (!dialogContext.mounted) return;
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(content: Text('Could not add photos: $error')),
                      );
                    }
                  },
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('Add photos'),
                ),
                const SizedBox(height: 4),
                const Text(
                  'These photos will be sent to your teacher when you submit.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          actions: [
            SizedBox(
              width: double.infinity,
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: selectedImages.isEmpty
                          ? null
                          : () => Navigator.of(dialogContext).pop(
                              List<ReviewedSubmissionImage>.of(selectedImages),
                            ),
                      child: const Text('Confirm'),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );

  pageController.dispose();
  return result;
}

List<String> submissionImageUrls(Map<String, dynamic> submission) {
  final urls = <String>[
    if (submission['scanUrls'] is Iterable)
      for (final url in submission['scanUrls'] as Iterable)
        if (url is String && url.trim().isNotEmpty) url.trim(),
  ];
  if (urls.isEmpty &&
      submission['scanUrl'] is String &&
      (submission['scanUrl'] as String).trim().isNotEmpty) {
    urls.add((submission['scanUrl'] as String).trim());
  }
  return urls;
}

List<String> submissionImageDraftUrls(Map<String, dynamic> submission) {
  final value = submission['draftScanUrls'];
  if (value is! Iterable) return const [];
  return value
      .whereType<String>()
      .map((url) => url.trim())
      .where((url) => url.isNotEmpty)
      .toList();
}

Widget buildSubmittedImageGallery(
  BuildContext context,
  List<String> imageUrls, {
  Future<void> Function(String imageUrl)? onRemove,
  String title = 'Submitted works',
}) {
  if (imageUrls.isEmpty) return const SizedBox.shrink();

  return _SubmittedImageGallery(
    imageUrls: imageUrls,
    onRemove: onRemove,
    title: title,
  );
}

class _SubmittedImageGallery extends StatefulWidget {
  const _SubmittedImageGallery({
    required this.imageUrls,
    required this.onRemove,
    required this.title,
  });

  final List<String> imageUrls;
  final Future<void> Function(String imageUrl)? onRemove;
  final String title;

  @override
  State<_SubmittedImageGallery> createState() => _SubmittedImageGalleryState();
}

class _SubmittedImageGalleryState extends State<_SubmittedImageGallery> {
  late List<String> _imageUrls;
  late final PageController _pageController;
  int _currentPage = 0;
  int _imageRetryCount = 0;
  bool _isRemoving = false;

  @override
  void initState() {
    super.initState();
    _imageUrls = List.of(widget.imageUrls);
    _pageController = PageController(viewportFraction: 0.82);
  }

  @override
  void didUpdateWidget(covariant _SubmittedImageGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.imageUrls.length > _imageUrls.length) {
      _currentPage = widget.imageUrls.length - 1;
    } else if (_currentPage >= widget.imageUrls.length) {
      _currentPage = widget.imageUrls.isEmpty ? 0 : widget.imageUrls.length - 1;
    }
    _imageUrls = List.of(widget.imageUrls);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients && _imageUrls.isNotEmpty) {
        _pageController.jumpToPage(_currentPage);
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _removeCurrentImage() async {
    if (_isRemoving || _imageUrls.isEmpty || widget.onRemove == null) return;
    final imageUrl = _imageUrls[_currentPage];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove submitted photo?'),
        content: const Text(
          'This photo will be removed from your submission and your teacher will no longer see it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    setState(() => _isRemoving = true);
    try {
      await widget.onRemove!(imageUrl);
      if (!mounted) return;
      setState(() {
        _imageUrls.removeAt(_currentPage);
        if (_currentPage >= _imageUrls.length) {
          _currentPage = _imageUrls.isEmpty ? 0 : _imageUrls.length - 1;
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients && _imageUrls.isNotEmpty) {
          _pageController.jumpToPage(_currentPage);
        }
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not remove photo: $error')));
    } finally {
      if (mounted) setState(() => _isRemoving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_imageUrls.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${widget.title} (${_imageUrls.length})',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 220,
          child: PageView.builder(
            controller: _pageController,
            itemCount: _imageUrls.length,
            onPageChanged: (page) => setState(() => _currentPage = page),
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () => showFullScreenImageGallery(
                        context,
                        _imageUrls,
                        index,
                      ),
                      child: Center(
                        child: Image.network(
                          _imageUrls[index],
                          key: ValueKey(
                            '${_imageUrls[index]}-$_imageRetryCount',
                          ),
                          fit: BoxFit.contain,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return const SizedBox(
                              width: 36,
                              height: 36,
                              child: CircularProgressIndicator(strokeWidth: 3),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) => Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.broken_image_outlined, size: 48),
                              const SizedBox(height: 8),
                              const Text(
                                'Could not load this photo.',
                                textAlign: TextAlign.center,
                              ),
                              TextButton.icon(
                                onPressed: () async {
                                  await NetworkImage(_imageUrls[index]).evict();
                                  if (mounted) {
                                    setState(() => _imageRetryCount++);
                                  }
                                },
                                icon: const Icon(Icons.refresh, size: 18),
                                label: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (widget.onRemove != null)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: IconButton.filled(
                        tooltip: 'Remove submitted photo',
                        onPressed: _isRemoving || index != _currentPage
                            ? null
                            : _removeCurrentImage,
                        style: IconButton.styleFrom(
                          minimumSize: const Size(32, 32),
                          maximumSize: const Size(32, 32),
                          padding: EdgeInsets.zero,
                          backgroundColor: Colors.black54,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (_imageUrls.length > 1)
          Center(child: Text('${_currentPage + 1} of ${_imageUrls.length}')),
        const SizedBox(height: 10),
      ],
    );
  }
}

Future<Uint8List?> _showFullScreenImage(
  BuildContext context,
  Uint8List imageBytes,
) {
  return showDialog<Uint8List>(
    context: context,
    useSafeArea: false,
    builder: (dialogContext) => Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          leading: IconButton(
            tooltip: 'Close image',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ),
        body: LayoutBuilder(
          builder: (context, constraints) => Center(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 6,
              child: Image.memory(
                imageBytes,
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                fit: BoxFit.contain,
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
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.all(14),
          child: Center(
            child: FilledButton.icon(
              onPressed: () async {
                final cropped = await showImageCropper(
                  dialogContext,
                  imageBytes,
                );
                if (cropped != null && dialogContext.mounted) {
                  Navigator.of(dialogContext).pop(cropped);
                }
              },
              icon: const Icon(Icons.crop),
              label: const Text('Crop photo'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> showFullScreenImageGallery(
  BuildContext context,
  List<String> imageUrls,
  int initialPage,
) {
  return showDialog<void>(
    context: context,
    useSafeArea: false,
    builder: (dialogContext) {
      var currentPage = initialPage;
      return StatefulBuilder(
        builder: (context, setState) => Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              title: Text('${currentPage + 1} of ${imageUrls.length}'),
              leading: IconButton(
                tooltip: 'Close image',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ),
            body: PageView.builder(
              controller: PageController(initialPage: initialPage),
              itemCount: imageUrls.length,
              onPageChanged: (page) => setState(() {
                currentPage = page;
              }),
              itemBuilder: (context, index) => Center(
                child: InteractiveViewer(
                  key: ValueKey(index),
                  minScale: 1,
                  maxScale: 6,
                  child: Image.network(
                    imageUrls[index],
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
