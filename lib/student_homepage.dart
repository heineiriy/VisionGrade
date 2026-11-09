import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firestore_service.dart';
import 'home_screen.dart';
import 'subject_view_screen.dart';

class StudentHomePage extends StatelessWidget {
  final String studentName;
  final String studentEmail;
  final String? section;
  final String? gradeLevel;
  final String? profileImageUrl;
  final List<String> assignedSubjectIds;

  const StudentHomePage({
    super.key,
    this.studentName = 'Student',
    this.studentEmail = '',
    this.section,
    this.gradeLevel,
    this.profileImageUrl,
    this.assignedSubjectIds = const [],
  });

  static bool isSubjectAvailable({
    required String subjectDocumentId,
    required Map<String, dynamic> subject,
    required List<String> assignedSubjectIds,
    String? gradeLevel,
    String? section,
  }) {
    if (subject['isArchived'] == true) return false;

    final subjectName = subject['name']?.toString().trim().toLowerCase() ?? '';
    final subjectId =
        subject['subjectId']?.toString().trim().toLowerCase() ?? '';
    final matchesAssigned = assignedSubjectIds.any((value) {
      final candidate = value.trim().toLowerCase();
      return candidate.isNotEmpty &&
          (candidate == subjectDocumentId.toLowerCase() ||
              candidate == subjectId ||
              candidate == subjectName);
    });

    if (matchesAssigned) return true;

    final studentGrade = gradeLevel?.trim().toLowerCase() ?? '';
    final subjectGrade =
        (subject['year'] ?? subject['yearLevel'])
            ?.toString()
            .trim()
            .toLowerCase() ??
        '';
    final matchesGrade =
        studentGrade.isNotEmpty &&
        subjectGrade.isNotEmpty &&
        subjectGrade == studentGrade;
    if (!matchesGrade) {
      return false;
    }

    final rawSections = subject['sections'];
    final subjectSections = <String>[];
    if (rawSections is Iterable) {
      subjectSections.addAll(
        rawSections
            .whereType<String>()
            .map((value) => value.trim().toLowerCase())
            .where((value) => value.isNotEmpty),
      );
    }
    if (subjectSections.isEmpty) return true;

    final studentSection = section?.trim().toLowerCase() ?? '';
    if (studentSection.isEmpty) return false;

    return subjectSections.any((value) => value == studentSection);
  }

  @override
  Widget build(BuildContext context) {
    final email = studentEmail.trim().isNotEmpty
        ? studentEmail.trim()
        : FirebaseAuth.instance.currentUser?.email?.trim() ?? '';

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: email.isEmpty
          ? null
          : FirestoreService.studentAccountStream(email),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildHome(
            context,
            subjects: const [],
            emptyMessage:
                'Unable to load your enrolled subjects. Please try again.',
          );
        }
        if (email.isNotEmpty && !snapshot.hasData) {
          return _buildHome(
            context,
            subjects: const [],
            emptyMessage: 'Loading your subjects...',
          );
        }

        final student = snapshot.data?.docs.isNotEmpty == true
            ? snapshot.data!.docs.first.data()
            : null;
        final savedAssignments = student == null
            ? assignedSubjectIds
            : _assignedSubjectsFrom(student);
        final currentGrade =
            _firstStudentValue(student, const [
              'gradeLevel',
              'yearLevel',
              'grade',
            ]) ??
            gradeLevel;
        final currentSection =
            _firstStudentValue(student, const ['section']) ?? section;

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirestoreService.subjectsStream(),
          builder: (context, subjectSnapshot) {
            if (subjectSnapshot.hasError) {
              return _buildHome(
                context,
                subjects: const [],
                emptyMessage:
                    'Unable to load your enrolled subjects. Please try again.',
              );
            }
            if (!subjectSnapshot.hasData) {
              return _buildHome(
                context,
                subjects: const [],
                emptyMessage: 'Loading your subjects...',
              );
            }

            final subjects = subjectSnapshot.data!.docs
                .where(
                  (doc) => isSubjectAvailable(
                    subjectDocumentId: doc.id,
                    subject: doc.data(),
                    assignedSubjectIds: savedAssignments,
                    gradeLevel: currentGrade,
                    section: currentSection,
                  ),
                )
                .map(_subjectFromDoc)
                .toList();
            return _buildHome(context, subjects: subjects);
          },
        );
      },
    );
  }

  HomeScreen _buildHome(
    BuildContext context, {
    required List<Subject> subjects,
    String? emptyMessage,
  }) {
    final effectiveEmail = studentEmail.trim().isNotEmpty
        ? studentEmail.trim()
        : FirebaseAuth.instance.currentUser?.email?.trim() ?? '';
    return HomeScreen(
      role: UserRole.student,
      userName: studentName,
      userEmail: effectiveEmail,
      profileImageUrl: profileImageUrl,
      subjects: subjects,
      emptyStateMessage: emptyMessage,
      onRefresh: () =>
          FirestoreService.refreshHomeData(studentEmail: effectiveEmail),
      onSubjectTap: (subject) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SubjectViewScreen(
              subject: subject,
              role: UserRole.student,
              studentName: studentName,
              studentEmail: effectiveEmail,
              profileImageUrl: profileImageUrl,
            ),
          ),
        );
      },
    );
  }

  static List<String> _assignedSubjectsFrom(Map<String, dynamic> student) {
    final assigned = <String>[];
    for (final key in const [
      'assignedSubjectIds',
      'subjectIds',
      'subjects',
      'enrolledSubjects',
    ]) {
      final rawValue = student[key];
      if (rawValue is Iterable) {
        for (final value in rawValue) {
          final subjectId = value is String
              ? value.trim()
              : value is Map
              ? (value['subjectId'] ?? value['id'] ?? value['name'])
                        ?.toString()
                        .trim() ??
                    ''
              : '';
          if (subjectId.isNotEmpty && !assigned.contains(subjectId)) {
            assigned.add(subjectId);
          }
        }
      } else if (rawValue is String && rawValue.trim().isNotEmpty) {
        assigned.add(rawValue.trim());
      }
    }

    final singleSubjectId = student['subjectId'];
    if (singleSubjectId is String &&
        singleSubjectId.trim().isNotEmpty &&
        !assigned.contains(singleSubjectId.trim())) {
      assigned.add(singleSubjectId.trim());
    }
    return assigned;
  }

  static String? _firstStudentValue(
    Map<String, dynamic>? student,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = student?[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  Subject _subjectFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return Subject(
      id: doc.id,
      title: data['name'] as String? ?? 'Subject',
      gradeLabel: data['year'] as String? ?? data['yearLevel'] as String? ?? '',
      instructorEmail: data['instructorEmail'] as String? ?? '',
      thumbnailUrl: data['thumbnailUrl'] as String?,
    );
  }
}
