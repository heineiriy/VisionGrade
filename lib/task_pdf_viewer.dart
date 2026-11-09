import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:url_launcher/url_launcher.dart';

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
  late Future<Uint8List> _documentFuture;

  @override
  void initState() {
    super.initState();
    _documentFuture = _downloadDocument();
  }

  Future<Uint8List> _downloadDocument() async {
    final uri = Uri.tryParse(widget.url);
    if (uri == null || !uri.hasScheme) {
      throw const FormatException('The PDF URL is invalid.');
    }

    final response = await http.get(uri).timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('The PDF server returned ${response.statusCode}.');
    }
    if (response.bodyBytes.isEmpty) {
      throw const FormatException('The PDF file is empty.');
    }
    return response.bodyBytes;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE5E5E5),
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: FutureBuilder<Uint8List>(
        future: _documentFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _buildLoadError(context, snapshot.error.toString());
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }
          return SfPdfViewer.memory(
            snapshot.data!,
            pageLayoutMode: PdfPageLayoutMode.continuous,
            scrollDirection: PdfScrollDirection.vertical,
            pageSpacing: 12,
            canShowScrollHead: true,
            canShowScrollStatus: true,
            enableDoubleTapZooming: true,
            enableTextSelection: true,
          );
        },
      ),
    );
  }

  Widget _buildLoadError(BuildContext context, String error) {
    return Center(
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
              'This PDF could not be loaded. Please try again or open it in your browser.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 12),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => setState(() {
                _documentFuture = _downloadDocument();
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
                    const SnackBar(content: Text('Could not open this PDF.')),
                  );
                }
              },
              icon: const Icon(Icons.open_in_browser),
              label: const Text('Try opening in browser'),
            ),
          ],
        ),
      ),
    );
  }
}
