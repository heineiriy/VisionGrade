import 'package:flutter_test/flutter_test.dart';
import 'package:visiongrade/curriculum_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads unique curriculum lessons for Grades 7 through 10', () async {
    final lessons = await CurriculumService.loadLessons();

    expect(lessons, hasLength(19));
    expect(lessons.map((lesson) => lesson.id).toSet(), hasLength(19));
    expect(lessons.map((lesson) => lesson.grade).toSet(), {7, 8, 9, 10});
    expect(
      lessons.every(
        (lesson) =>
            lesson.learningObjectives.isNotEmpty &&
            lesson.expectedConcepts.isNotEmpty,
      ),
      isTrue,
    );
  });
}
