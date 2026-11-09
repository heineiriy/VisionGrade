import 'package:http/http.dart' as http;

Future<http.MultipartFile> createMultipartFile(String path, String fileName) {
  return http.MultipartFile.fromPath('file', path, filename: fileName);
}
