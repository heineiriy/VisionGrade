import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class GradingApiException implements Exception {
  final String message;

  const GradingApiException(this.message);

  @override
  String toString() => message;
}

class GradingService {
  static const _configuredBaseUrl = String.fromEnvironment('GRADING_API_URL');

  static Uri get _gradeUri {
    final configuredUrl = _configuredBaseUrl.trim();
    final baseUrl = configuredUrl.isNotEmpty
        ? configuredUrl
        : kIsWeb
        ? 'http://127.0.0.1:8000'
        : defaultTargetPlatform == TargetPlatform.android
        ? 'http://10.59.80.76:8000'
        : 'http://127.0.0.1:8000';
    return Uri.parse(baseUrl).resolve('/api/grade/');
  }

  static Future<Map<String, dynamic>> gradeText({
    required String studentText,
    required Map<String, dynamic> task,
  }) async {
    final trimmedText = studentText.trim();
    if (trimmedText.isEmpty) {
      throw const GradingApiException('The submitted answer is empty.');
    }
    final expectedAnswers = _expectedAnswers(task);
    if (expectedAnswers.isEmpty && !_hasRubric(task)) {
      throw const GradingApiException(
        'Add rubric criteria or task instructions before requesting AI grading.',
      );
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const GradingApiException(
        'Sign in as an instructor before grading.',
      );
    }
    final String? idToken;
    try {
      idToken = await user.getIdToken();
    } on FirebaseAuthException catch (error) {
      throw GradingApiException(
        'Could not verify your instructor sign-in (${error.code}).',
      );
    } catch (error) {
      throw GradingApiException(
        'Could not verify your instructor sign-in: $error',
      );
    }
    if (idToken == null || idToken.isEmpty) {
      throw const GradingApiException(
        'Could not verify your instructor sign-in. Please sign in again.',
      );
    }

    final rubric = task['rubric'];
    final rubricData = rubric is Map ? rubric : null;
    final payload = {
      'expected_answers': expectedAnswers,
      'student_text': trimmedText,
      'rubric': rubric,
      'task_title': task['title']?.toString() ?? '',
      'task_instructions': task['body']?.toString() ?? '',
      'task_type':
          task['taskType']?.toString() ??
          task['task_type']?.toString() ??
          rubricData?['taskType']?.toString() ??
          '',
      'learning_objectives':
          task['learningObjectives'] ??
          task['learning_objectives'] ??
          rubricData?['learningObjectives'] ??
          rubricData?['curriculumStandards'] ??
          const [],
      'expected_concepts':
          task['expectedConcepts'] ??
          task['expected_concepts'] ??
          rubricData?['expectedConcepts'] ??
          const [],
      'submission_metadata': {'source': 'text_submission'},
      'curriculum_standards':
          task['curriculumStandards'] ?? rubricData?['curriculumStandards'],
    };

    try {
      final response = await http
          .post(
            _gradeUri,
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 120));
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const GradingApiException(
          'The grading service returned an invalid response.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw GradingApiException(
          decoded['error']?.toString() ?? 'AI grading failed.',
        );
      }
      final result = decoded['result'];
      if (result is! Map<String, dynamic>) {
        throw const GradingApiException(
          'The grading service returned no grading result.',
        );
      }
      return {...result, 'expected_answer': expectedAnswers.values.join('\n')};
    } on GradingApiException {
      rethrow;
    } on FormatException {
      throw const GradingApiException(
        'The grading service returned an invalid response.',
      );
    } catch (error) {
      throw GradingApiException(
        'Could not connect to the grading service: $error',
      );
    }
  }

  static Future<Map<String, dynamic>> gradeScans({
    required List<Uint8List> images,
    required Map<String, dynamic> task,
    String expectedStudentName = '',
  }) async {
    final expectedAnswers = _expectedAnswers(task);
    if (expectedAnswers.isEmpty && !_hasRubric(task)) {
      throw const GradingApiException(
        'Add rubric criteria or task instructions before requesting AI grading.',
      );
    }
    if (images.isEmpty) {
      throw const GradingApiException('No scanned pages were provided.');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const GradingApiException(
        'Sign in as an instructor before grading.',
      );
    }
    final String? idToken;
    try {
      idToken = await user.getIdToken();
    } on FirebaseAuthException catch (error) {
      throw GradingApiException(
        'Could not verify your instructor sign-in (${error.code}).',
      );
    } catch (error) {
      throw GradingApiException(
        'Could not verify your instructor sign-in: $error',
      );
    }
    if (idToken == null || idToken.isEmpty) {
      throw const GradingApiException(
        'Could not verify your instructor sign-in. Please sign in again.',
      );
    }

    final request = http.MultipartRequest('POST', _gradeUri)
      ..headers['Authorization'] = 'Bearer $idToken';
    final rubric = task['rubric'];
    final rubricData = rubric is Map ? rubric : null;
    request.fields['payload'] = jsonEncode({
      'expected_answers': expectedAnswers,
      'rubric': rubric,
      'task_title': task['title']?.toString() ?? '',
      'task_instructions': task['body']?.toString() ?? '',
      'task_type':
          task['taskType']?.toString() ??
          task['task_type']?.toString() ??
          rubricData?['taskType']?.toString() ??
          '',
      'learning_objectives':
          task['learningObjectives'] ??
          task['learning_objectives'] ??
          rubricData?['learningObjectives'] ??
          rubricData?['curriculumStandards'] ??
          const [],
      'expected_concepts':
          task['expectedConcepts'] ??
          task['expected_concepts'] ??
          rubricData?['expectedConcepts'] ??
          const [],
      'submission_metadata': {
        'source': 'hardcopy_scan',
        'page_count': images.length,
        if (expectedStudentName.trim().isNotEmpty)
          'expected_student_name': expectedStudentName.trim(),
      },
      'curriculum_standards':
          task['curriculumStandards'] ?? rubricData?['curriculumStandards'],
    });
    for (var index = 0; index < images.length; index++) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'images',
          images[index],
          filename: 'scan_${index + 1}.jpg',
        ),
      );
    }

    try {
      final response = await request.send().timeout(
        const Duration(seconds: 180),
      );
      final responseBody = await response.stream.bytesToString();
      final decoded = jsonDecode(responseBody);
      if (decoded is! Map<String, dynamic>) {
        throw const GradingApiException(
          'The grading service returned an invalid response.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw GradingApiException(
          decoded['error']?.toString() ?? 'AI grading failed.',
        );
      }
      final result = decoded['result'];
      if (result is! Map<String, dynamic>) {
        throw const GradingApiException(
          'The grading service returned no grading result.',
        );
      }
      return {...result, 'expected_answer': expectedAnswers.values.join('\n')};
    } on GradingApiException {
      rethrow;
    } on FormatException {
      throw const GradingApiException(
        'The grading service returned an invalid response.',
      );
    } catch (error) {
      throw GradingApiException(
        'Could not connect to the grading service: $error',
      );
    }
  }

  static Map<String, String> _expectedAnswers(Map<String, dynamic> task) {
    final taskInstructions = task['body']?.toString().trim() ?? '';
    if (taskInstructions.isNotEmpty) {
      return {'task_instructions': taskInstructions};
    }
    return {};
  }

  static bool _hasRubric(Map<String, dynamic> task) {
    final rubric = task['rubric'];
    final criteria = rubric is Map ? rubric['criteria'] : null;
    return criteria is List && criteria.isNotEmpty;
  }
}
