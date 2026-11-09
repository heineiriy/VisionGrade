import 'package:http/http.dart' as http;

Future<http.MultipartFile> createMultipartFile(String path, String fileName) {
  throw UnsupportedError('File-path uploads are unavailable on this platform.');
}
