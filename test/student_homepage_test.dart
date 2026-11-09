import 'package:flutter_test/flutter_test.dart';
import 'package:visiongrade/student_homepage.dart';

void main() {
  group('StudentHomePage.isSubjectAvailable', () {
    test('shows an explicitly assigned subject', () {
      expect(
        StudentHomePage.isSubjectAvailable(
          subjectDocumentId: 'subject-document',
          subject: {
            'name': 'Science',
            'year': 'Grade 5',
            'sections': ['A'],
          },
          assignedSubjectIds: ['subject-document'],
          gradeLevel: 'Grade 6',
          section: 'B',
        ),
        isTrue,
      );
    });

    test(
      'shows a grade and section match when a saved subject id is stale',
      () {
        expect(
          StudentHomePage.isSubjectAvailable(
            subjectDocumentId: 'science-document',
            subject: {
              'name': 'Science',
              'year': 'Grade 5',
              'sections': ['A'],
            },
            assignedSubjectIds: ['old-subject-document'],
            gradeLevel: 'Grade 5',
            section: 'A',
          ),
          isTrue,
        );
      },
    );

    test(
      'shows a matching grade and section when no assignments are saved',
      () {
        expect(
          StudentHomePage.isSubjectAvailable(
            subjectDocumentId: 'subject-document',
            subject: {
              'name': 'Science',
              'year': 'Grade 5',
              'sections': ['A'],
            },
            assignedSubjectIds: [],
            gradeLevel: 'Grade 5',
            section: 'a',
          ),
          isTrue,
        );
      },
    );

    test('shows a student when their section is one of several assigned sections', () {
      expect(
        StudentHomePage.isSubjectAvailable(
          subjectDocumentId: 'subject-document',
          subject: {
            'name': 'Science',
            'year': 'Grade 5',
            'sections': ['Bayabas 5.1', 'Bayabas 5.2'],
          },
          assignedSubjectIds: [],
          gradeLevel: 'Grade 5',
          section: 'Bayabas 5.2',
        ),
        isTrue,
      );
    });

    test('does not match a different section with a similar name', () {
      expect(
        StudentHomePage.isSubjectAvailable(
          subjectDocumentId: 'subject-document',
          subject: {
            'name': 'Science',
            'year': 'Grade 5',
            'sections': ['Bayabas 5.1'],
          },
          assignedSubjectIds: [],
          gradeLevel: 'Grade 5',
          section: 'Bayabas 5.10',
        ),
        isFalse,
      );
    });

    test('does not match a different grade with a similar name', () {
      expect(
        StudentHomePage.isSubjectAvailable(
          subjectDocumentId: 'subject-document',
          subject: {
            'name': 'Science',
            'year': 'Grade 5',
            'sections': ['Bayabas 5.1'],
          },
          assignedSubjectIds: [],
          gradeLevel: 'Grade 50',
          section: 'Bayabas 5.1',
        ),
        isFalse,
      );
    });

    test('requires a section when the subject lists assigned sections', () {
      expect(
        StudentHomePage.isSubjectAvailable(
          subjectDocumentId: 'subject-document',
          subject: {
            'name': 'Science',
            'year': 'Grade 5',
            'sections': ['Bayabas 5.1'],
          },
          assignedSubjectIds: [],
          gradeLevel: 'Grade 5',
        ),
        isFalse,
      );
    });

    test('does not show unrelated subjects when no assignments are saved', () {
      expect(
        StudentHomePage.isSubjectAvailable(
          subjectDocumentId: 'subject-document',
          subject: {
            'name': 'Science',
            'year': 'Grade 5',
            'sections': ['A'],
          },
          assignedSubjectIds: [],
          gradeLevel: 'Grade 6',
          section: 'A',
        ),
        isFalse,
      );
    });

    test('does not expose every subject when grade information is missing', () {
      expect(
        StudentHomePage.isSubjectAvailable(
          subjectDocumentId: 'subject-document',
          subject: {'name': 'Science', 'year': 'Grade 5'},
          assignedSubjectIds: [],
        ),
        isFalse,
      );
    });
  });
}
