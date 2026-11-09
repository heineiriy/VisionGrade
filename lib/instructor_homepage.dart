import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firestore_service.dart';
import 'home_screen.dart';
import 'subject_view_screen.dart';
import 'messaging_screen.dart';

class InstructorHomePage extends StatelessWidget {
  final String instructorName;
  final String instructorEmail;
  final String? profileImageUrl;

  const InstructorHomePage({
    super.key,
    this.instructorName = 'Instructor',
    this.instructorEmail = '',
    this.profileImageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: instructorEmail.isEmpty
          ? FirestoreService.subjectsStream()
          : FirestoreService.instructorSubjectsStream(instructorEmail),
      builder: (context, snapshot) {
        final subjects = (snapshot.data?.docs ?? const [])
            .where((doc) => doc.data()['isArchived'] != true)
            .map(_subjectFromDoc)
            .toList();
        return HomeScreen(
          role: UserRole.instructor,
          userName: instructorName,
          userEmail: instructorEmail,
          profileImageUrl: profileImageUrl,
          subjects: subjects,
          onRefresh: () => FirestoreService.refreshHomeData(
            instructorEmail: instructorEmail,
          ),
          onSubjectTap: (subject) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SubjectViewScreen(
                  subject: subject,
                  role: UserRole.instructor,
                  instructorName: instructorName,
                  instructorEmail: instructorEmail,
                  profileImageUrl: profileImageUrl,
                ),
              ),
            );
          },
          floatingActionButton: Padding(
            padding: const EdgeInsets.only(bottom: 56),
            child: FloatingActionButton.extended(
              onPressed: instructorEmail.trim().isEmpty
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => InstructorMessagesScreen(
                          instructorEmail: instructorEmail,
                          instructorName: instructorName,
                        ),
                      ),
                    ),
              icon: const Icon(Icons.chat),
              label: const Text('Messages'),
            ),
          ),
        );
      },
    );
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
