import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'cloudinary_file_upload.dart'
    if (dart.library.io) 'cloudinary_file_upload_io.dart'
    as file_upload;

class CloudinaryUploadException implements Exception {
  final String message;

  const CloudinaryUploadException(this.message);

  @override
  String toString() => message;
}

class CloudinaryService {
  CloudinaryService._();

  static const _cloudName = 'vfclgqlo';
  static const _uploadPreset = 'pen4kzrh';

  static Future<String> uploadBytes({
    required Uint8List bytes,
    required String fileName,
    String resourceType = 'auto',
    Duration? timeout,
  }) async {
    final request =
        http.MultipartRequest(
            'POST',
            Uri.parse(
              'https://api.cloudinary.com/v1_1/$_cloudName/$resourceType/upload',
            ),
          )
          ..files.add(
            http.MultipartFile.fromBytes('file', bytes, filename: fileName),
          );
    _setUploadOptions(request);

    return _sendUpload(request, timeout);
  }

  static Future<String> uploadStream({
    required Stream<List<int>> stream,
    required int length,
    required String fileName,
    String resourceType = 'auto',
    Duration? timeout,
  }) async {
    if (length <= 0) {
      throw const CloudinaryUploadException(
        'The selected file is empty or its size could not be determined.',
      );
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse(
        'https://api.cloudinary.com/v1_1/$_cloudName/$resourceType/upload',
      ),
    )..files.add(http.MultipartFile('file', stream, length, filename: fileName));
    _setUploadOptions(request);

    return _sendUpload(request, timeout);
  }

  static Future<String> uploadFile({
    required String path,
    required String fileName,
    String resourceType = 'auto',
    Duration? timeout,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse(
        'https://api.cloudinary.com/v1_1/$_cloudName/$resourceType/upload',
      ),
    )..files.add(await file_upload.createMultipartFile(path, fileName));
    _setUploadOptions(request);

    return _sendUpload(request, timeout);
  }

  static void _setUploadOptions(http.MultipartRequest request) {
    request.fields['upload_preset'] = _uploadPreset;
  }

  static Future<String> _sendUpload(
    http.MultipartRequest request,
    Duration? timeout,
  ) async {
    final client = http.Client();
    try {
      final response = await client
          .send(request)
          .timeout(timeout ?? const Duration(minutes: 2));
      final body = await response.stream.bytesToString().timeout(
        timeout ?? const Duration(minutes: 2),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw CloudinaryUploadException(
          'Cloudinary upload failed (${response.statusCode}): $body',
        );
      }

      final responseData = jsonDecode(body) as Map<String, dynamic>;
      final secureUrl = responseData['secure_url'] as String?;
      if (secureUrl == null || secureUrl.isEmpty) {
        throw const CloudinaryUploadException(
          'Cloudinary did not return an uploaded file URL.',
        );
      }
      return secureUrl;
    } finally {
      client.close();
    }
  }
}
