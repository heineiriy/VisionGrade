import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'local_notification_service.dart';
import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'instructor_homepage.dart';
import 'instructorscreen.dart';
import 'presence_service.dart';
import 'remember_me_store.dart';
import 'student_homepage.dart';
import 'studentscreen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _isRestoringSession = true;

  @override
  void initState() {
    super.initState();
    _restoreRememberedSession();
  }

  Future<void> _restoreRememberedSession() async {
    try {
      final role = await RememberMeStore.getRole();
      if (role == null) {
        return;
      }
      final user = await FirebaseAuth.instance.authStateChanges().first;
      if (user?.email == null || (role != 'instructor' && role != 'student')) {
        await RememberMeStore.clear();
        return;
      }

      final email = user!.email!.trim();
      if (role == 'instructor') {
        final accounts = await FirebaseFirestore.instance
            .collection('instructor_accounts')
            .where('email', isEqualTo: email)
            .limit(1)
            .get();
        if (accounts.docs.isEmpty ||
            accounts.docs.first.data()['isActive'] != true) {
          await _clearUnavailableRememberedSession();
          return;
        }

        final account = accounts.docs.first.data();
        await PresenceService.start(
          userDocument: accounts.docs.first.reference,
          role: 'instructor',
        );
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => InstructorHomePage(
              instructorName: account['name'] as String? ?? 'Instructor',
              instructorEmail: email,
              profileImageUrl:
                  account['profileImageUrl'] as String? ??
                  account['photoUrl'] as String? ??
                  user.photoURL,
            ),
          ),
        );
        return;
      }

      final students = await FirebaseFirestore.instance
          .collection('students')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (students.docs.isEmpty ||
          students.docs.first.data()['isActive'] != true) {
        await _clearUnavailableRememberedSession();
        return;
      }

      final student = students.docs.first.data();
      await PresenceService.start(
        userDocument: students.docs.first.reference,
        role: 'student',
      );
      if (!mounted) return;

      final assignedSubjectIds = <String>[];
      for (final key in [
        'assignedSubjectIds',
        'subjectIds',
        'subjects',
        'enrolledSubjects',
      ]) {
        final rawAssignedSubjects = student[key];
        if (rawAssignedSubjects is Iterable) {
          for (final value in rawAssignedSubjects) {
            if (value is String && value.trim().isNotEmpty) {
              assignedSubjectIds.add(value.trim());
            }
          }
        } else if (rawAssignedSubjects is String &&
            rawAssignedSubjects.trim().isNotEmpty) {
          assignedSubjectIds.add(rawAssignedSubjects.trim());
        }
      }
      final subjectId = student['subjectId'];
      if (subjectId is String && subjectId.trim().isNotEmpty) {
        assignedSubjectIds.add(subjectId.trim());
      }
      unawaited(
        LocalNotificationService.startForStudent(
          email: email,
          assignedSubjectIds: assignedSubjectIds,
        ),
      );

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => StudentHomePage(
            studentName: student['name'] as String? ?? 'Student',
            studentEmail: email,
            section: student['section'] as String?,
            gradeLevel:
                student['gradeLevel'] as String? ??
                student['yearLevel'] as String? ??
                student['grade'] as String?,
            profileImageUrl:
                student['profileImageUrl'] as String? ??
                student['photoUrl'] as String? ??
                user.photoURL,
            assignedSubjectIds: assignedSubjectIds,
          ),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint(
        'Could not restore the remembered session: $error\n$stackTrace',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not restore your session. Please log in again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isRestoringSession = false);
    }
  }

  Future<void> _clearUnavailableRememberedSession() async {
    await RememberMeStore.clear();
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'This account is no longer active. Please contact your administrator.',
        ),
      ),
    );
  }

  void _showRoleDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) {
        return Dialog(
          backgroundColor: AppPalette.burgundy,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 28),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 18),
                  child: Text(
                    'Are you an instructor or a student?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: const BorderSide(
                            color: Color(0xFFF0C7C8),
                            width: 1.2,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () {
                          Navigator.of(context).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const InstructorLoginScreen(),
                            ),
                          );
                        },
                        child: const Text(
                          'Instructor',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: const BorderSide(
                            color: Color(0xFFF0C7C8),
                            width: 1.2,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () {
                          Navigator.of(context).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const StudentLoginScreen(),
                            ),
                          );
                        },
                        child: const Text(
                          'Student',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: AppPalette.burgundy,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                Expanded(
                  flex: 6,
                  child: Center(
                    child: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: VisionGradeWordmark(fontSize: 34, light: true),
                    ),
                  ),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 48),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _isRestoringSession
                              ? null
                              : () => _showRoleDialog(context),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide.none,
                            backgroundColor: const Color(0xFFE8C1C5),
                            foregroundColor: AppPalette.burgundyDark,
                            shape: const StadiumBorder(),
                            padding: const EdgeInsets.symmetric(vertical: 18),
                          ),
                          child: _isRestoringSession
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Log in',
                                  style: TextStyle(
                                    color: AppPalette.burgundyDark,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
