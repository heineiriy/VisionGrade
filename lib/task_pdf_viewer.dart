import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:url_launcher/url_launcher.dart';

String _pdfViewerUrl(String url) {
  if (url.contains('/image/upload/') && !url.contains('/fl_attachment/')) {
    return url.replaceFirst('/image/upload/', '/image/upload/fl_attachment/');
  }
  return url;
}

bool isPdfAttachment({required String url, required String name}) {
  final uri = Uri.tryParse(url);
  return name.trim().toLowerCase().endsWith('.pdf') ||
      (uri?.path ?? '').toLowerCase().endsWith('.pdf');
}

Future<void> openTaskAttachment(
  BuildContext context, {
  required String url,
  required String name,
}) async {
  if (isPdfAttachment(url: url, name: name)) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TaskPdfViewer(url: url, title: name),
      ),
    );
    return;
  }

  final uri = Uri.tryParse(url);
  if (uri == null ||
      !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open this attachment.')),
    );
  }
}

class TaskPdfViewer extends StatefulWidget {
  const TaskPdfViewer({required this.url, required this.title, super.key});

  final String url;
  final String title;

  @override
  State<TaskPdfViewer> createState() => _TaskPdfViewerState();
}

class _TaskPdfViewerState extends State<TaskPdfViewer> {
  String? _loadError;
  var _retryCount = 0;

  void _handleLoadFailure(PdfDocumentLoadFailedDetails details) {
    setState(() {
      _loadError = details.description;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: _loadError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.picture_as_pdf_outlined,
                      color: Colors.white,
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'This PDF could not be loaded. If it is an older attachment, ask the teacher to upload it again.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _loadError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => setState(() {
                        _loadError = null;
                        _retryCount++;
                      }),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final uri = Uri.tryParse(widget.url);
                        if (uri == null ||
                            !await launchUrl(
                              uri,
                              mode: LaunchMode.externalApplication,
                            )) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Could not open this PDF.'),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.open_in_browser),
                      label: const Text('Try opening in browser'),
                    ),
                  ],
                ),
              ),
            )
          : SfPdfViewer.network(
              _pdfViewerUrl(widget.url),
              key: ValueKey(_retryCount),
              pageLayoutMode: PdfPageLayoutMode.continuous,
              scrollDirection: PdfScrollDirection.vertical,
              pageSpacing: 8,
              canShowScrollHead: true,
              canShowScrollStatus: true,
              enableDoubleTapZooming: true,
              onDocumentLoadFailed: _handleLoadFailure,
            ),
    );
  }
}
