import 'dart:convert';

import 'package:flutter/services.dart';

class CurriculumLesson {
  final String id;
  final int grade;
  final String learningArea;
  final String lessonTitle;
  final String sourceLanguage;
  final List<String> learningObjectives;
  final List<String> expectedConcepts;

  const CurriculumLesson({
    required this.id,
    required this.grade,
    required this.learningArea,
    required this.lessonTitle,
    required this.sourceLanguage,
    required this.learningObjectives,
    required this.expectedConcepts,
  });

  factory CurriculumLesson.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final grade = json['grade'];
    final learningArea = json['learning_area'];
    final lessonTitle = json['lesson_title'];
    final sourceLanguage = json['source_language'];
    final learningObjectives = json['learning_objectives'];
    final expectedConcepts = json['expected_concepts'];
    if (id is! String ||
        grade is! int ||
        learningArea is! String ||
        lessonTitle is! String ||
        sourceLanguage is! String ||
        learningObjectives is! List ||
        expectedConcepts is! List ||
        !learningObjectives.every((item) => item is String) ||
        !expectedConcepts.every((item) => item is String)) {
      throw const FormatException('Invalid lesson plan curriculum record.');
    }

    return CurriculumLesson(
      id: id,
      grade: grade,
      learningArea: learningArea,
      lessonTitle: lessonTitle,
      sourceLanguage: sourceLanguage,
      learningObjectives: List<String>.unmodifiable(
        learningObjectives.cast<String>(),
      ),
      expectedConcepts: List<String>.unmodifiable(
        expectedConcepts.cast<String>(),
      ),
    );
  }
}

class CurriculumService {
  CurriculumService._();

  static const _assetPath = 'assets/curriculum/lesson_plans_g7_g10.json';

  static Future<List<CurriculumLesson>> loadLessons() async {
    final decoded = jsonDecode(await rootBundle.loadString(_assetPath));
    if (decoded is! Map || decoded['lessons'] is! List) {
      throw const FormatException(
        'The curriculum asset has an invalid format.',
      );
    }
    return List<CurriculumLesson>.unmodifiable(
      (decoded['lessons'] as List).map((lesson) {
        if (lesson is! Map) {
          throw const FormatException('Invalid lesson plan curriculum record.');
        }
        return CurriculumLesson.fromJson(Map<String, dynamic>.from(lesson));
      }),
    );
  }
}
