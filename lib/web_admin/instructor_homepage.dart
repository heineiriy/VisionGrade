import 'package:flutter/material.dart';
import '../home_screen.dart';
import '../subject_view_screen.dart';

class InstructorHomePage extends StatelessWidget {
  final String instructorName;
  final String? profileImageUrl;

  const InstructorHomePage({
    super.key,
    this.instructorName = 'Instructor',
    this.profileImageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return HomeScreen(
      role: UserRole.instructor,
      userName: instructorName,
      profileImageUrl: profileImageUrl,
      subjects: const [],
      onSubjectTap: (subject) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SubjectViewScreen(
              subject: subject,
              role: UserRole.instructor,
              profileImageUrl: profileImageUrl,
            ),
          ),
        );
      },
    );
  }
}
