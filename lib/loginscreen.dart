import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'local_notification_service.dart';
import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'instructor_homepage.dart';
import 'student_homepage.dart';
import 'presence_service.dart';
import 'remember_me_store.dart';

class LoginScreen extends StatefulWidget {
  final bool isInstructor;

  const LoginScreen({super.key, this.isInstructor = true});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _rememberMe = false;
  bool _isPasswordVisible = false;
  bool _isSubmitting = false;
  String? _emailError;
  String? _passwordError;
  String? _loginError;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required';
    }

    final email = value.trim();
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRegex.hasMatch(email)) {
      return 'Enter a valid email';
    }

    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Password is required';
    }

    if (value.trim().length < 6) {
      return 'Password must be at least 6 characters';
    }

    return null;
  }

  InputDecoration _fieldDecoration({
    required String label,
    bool hasError = false,
  }) {
    final borderColor = hasError ? Colors.redAccent : AppPalette.ink;
    return InputDecoration(
      hintText: label,
      hintStyle: const TextStyle(color: AppPalette.ink, fontSize: 10),
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      constraints: const BoxConstraints.tightFor(height: 48),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(
          color: hasError ? Colors.redAccent : AppPalette.burgundy,
          width: 1.5,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
    );
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    final emailError = _validateEmail(_emailController.text);
    final passwordError = _validatePassword(_passwordController.text);
    setState(() {
      _loginError = null;
      _emailError = emailError;
      _passwordError = passwordError;
    });
    if (emailError != null || passwordError != null) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    setState(() => _isSubmitting = true);
    var authenticated = false;
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      authenticated = true;

      if (widget.isInstructor) {
        final accounts = await FirebaseFirestore.instance
            .collection('instructor_accounts')
            .where('email', isEqualTo: email)
            .limit(1)
            .get();
        if (accounts.docs.isEmpty ||
            accounts.docs.first.data()['isActive'] != true) {
          throw FirebaseAuthException(code: 'account-disabled');
        }
        await PresenceService.start(
          userDocument: accounts.docs.first.reference,
          role: 'instructor',
        );
        await RememberMeStore.save(remember: _rememberMe, role: 'instructor');
        if (!mounted) return;
        final instructor = accounts.docs.first.data();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => InstructorHomePage(
              instructorName: instructor['name'] as String? ?? 'Instructor',
              instructorEmail: email,
              profileImageUrl:
                  instructor['profileImageUrl'] as String? ??
                  instructor['photoUrl'] as String? ??
                  FirebaseAuth.instance.currentUser?.photoURL,
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
        throw FirebaseAuthException(code: 'student-disabled');
      }
      await PresenceService.start(
        userDocument: students.docs.first.reference,
        role: 'student',
      );
      await RememberMeStore.save(remember: _rememberMe, role: 'student');
      if (!mounted) return;
      final student = students.docs.first.data();
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
                FirebaseAuth.instance.currentUser?.photoURL,
            assignedSubjectIds: assignedSubjectIds,
          ),
        ),
      );
    } on FirebaseAuthException catch (error) {
      final sessionCleared = await _clearFailedLoginSession(authenticated);
      if (!mounted) return;
      setState(
        () => _loginError = sessionCleared
            ? _authErrorMessage(error.code)
            : 'Unable to securely complete sign-in. Please try again.',
      );
    } on FirebaseException catch (error) {
      final sessionCleared = await _clearFailedLoginSession(authenticated);
      if (!mounted) return;
      setState(
        () => _loginError = sessionCleared
            ? _firebaseErrorMessage(error.code)
            : 'Unable to securely complete sign-in. Please try again.',
      );
    } catch (error, stackTrace) {
      debugPrint('Unexpected login error: $error\n$stackTrace');
      final sessionCleared = await _clearFailedLoginSession(authenticated);
      if (!mounted) return;
      setState(
        () => _loginError = sessionCleared
            ? 'Unable to log in right now. Please try again.'
            : 'Unable to securely complete sign-in. Please try again.',
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<bool> _clearFailedLoginSession(bool authenticated) async {
    if (!authenticated) return true;

    try {
      await FirebaseAuth.instance.signOut();
      await RememberMeStore.clear();
      return true;
    } catch (error, stackTrace) {
      debugPrint(
        'Could not clear the Firebase session after login failure: '
        '$error\n$stackTrace',
      );
      return false;
    }
  }

  String _authErrorMessage(String code) {
    return switch (code) {
      'wrong-password' ||
      'user-not-found' ||
      'invalid-credential' ||
      'invalid-login-credentials' => 'Incorrect email or password',
      'invalid-email' => 'Enter a valid email address',
      'user-disabled' =>
        'This account has been disabled. Contact your administrator.',
      'too-many-requests' => 'Too many attempts. Please wait and try again.',
      'network-request-failed' =>
        'Unable to connect. Check your internet connection and try again.',
      'account-disabled' || 'student-disabled' =>
        'This account is not active for this role. Contact your administrator.',
      _ => 'Unable to log in right now. Please try again.',
    };
  }

  String _firebaseErrorMessage(String code) {
    return switch (code) {
      'permission-denied' =>
        'Unable to verify your account access. Contact your administrator.',
      'unavailable' || 'deadline-exceeded' =>
        'Unable to verify your account right now. Please try again.',
      _ => 'Unable to verify your account. Please try again.',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.burgundy,
      body: SafeArea(
        top: false,
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final headerHeight = (constraints.maxHeight * 0.285).clamp(
              170.0,
              240.0,
            );
            final formWidth = (constraints.maxWidth * 0.9).clamp(0.0, 360.0);

            return Column(
              children: [
                SizedBox(
                  height: headerHeight,
                  width: double.infinity,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Transform.translate(
                        offset: Offset(0, headerHeight * 0.135),
                        child: const VisionGradeWordmark(
                          fontSize: 18,
                          light: true,
                        ),
                      ),
                      Positioned(
                        top: 24,
                        left: 8,
                        child: IconButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: Image.asset(
                            'white_curved_back_arrow.png',
                            width: 18,
                            height: 18,
                            fit: BoxFit.contain,
                          ),
                          tooltip: 'Back',
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        top: BorderSide(color: AppPalette.rose, width: 3),
                      ),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(25),
                      ),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(0, 27, 0, 24),
                      child: Center(
                        child: SizedBox(
                          width: formWidth,
                          child: Column(
                            children: [
                              SizedBox(
                                height: 60,
                                child: Column(
                                  children: [
                                    SizedBox(
                                      height: 48,
                                      child: TextFormField(
                                        controller: _emailController,
                                        onChanged: (_) {
                                          setState(() {
                                            _emailError = null;
                                            _loginError = null;
                                          });
                                        },
                                        keyboardType:
                                            TextInputType.emailAddress,
                                        textAlignVertical:
                                            TextAlignVertical.center,
                                        style: const TextStyle(
                                          color: AppPalette.ink,
                                          fontSize: 11,
                                        ),
                                        decoration: _fieldDecoration(
                                          label: 'Email',
                                          hasError:
                                              _emailError != null ||
                                              _loginError != null,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      height: 12,
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          _emailError ?? '',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Color(0xFFB84C4C),
                                            fontSize: 11,
                                            height: 1,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                height: 72,
                                child: Column(
                                  children: [
                                    SizedBox(
                                      height: 48,
                                      child: TextFormField(
                                        controller: _passwordController,
                                        onChanged: (_) {
                                          setState(() {
                                            _passwordError = null;
                                            _loginError = null;
                                            if (_passwordController
                                                .text
                                                .isEmpty) {
                                              _isPasswordVisible = false;
                                            }
                                          });
                                        },
                                        obscureText: !_isPasswordVisible,
                                        textAlignVertical:
                                            TextAlignVertical.center,
                                        style: const TextStyle(
                                          color: AppPalette.ink,
                                          fontSize: 11,
                                        ),
                                        decoration:
                                            _fieldDecoration(
                                              label: 'Password',
                                              hasError:
                                                  _passwordError != null ||
                                                  _loginError != null,
                                            ).copyWith(
                                              suffixIconConstraints:
                                                  const BoxConstraints.tightFor(
                                                    width: 36,
                                                    height: 48,
                                                  ),
                                              suffixIcon:
                                                  _passwordController
                                                      .text
                                                      .isEmpty
                                                  ? null
                                                  : IconButton(
                                                      onPressed: () => setState(
                                                        () => _isPasswordVisible =
                                                            !_isPasswordVisible,
                                                      ),
                                                      icon: Icon(
                                                        _isPasswordVisible
                                                            ? Icons
                                                                  .visibility_off_outlined
                                                            : Icons
                                                                  .visibility_outlined,
                                                      ),
                                                      color: AppPalette.ink,
                                                      iconSize: 16,
                                                      padding: EdgeInsets.zero,
                                                      constraints:
                                                          const BoxConstraints.tightFor(
                                                            width: 36,
                                                            height: 36,
                                                          ),
                                                      tooltip:
                                                          _isPasswordVisible
                                                          ? 'Hide password'
                                                          : 'Show password',
                                                    ),
                                            ),
                                      ),
                                    ),
                                    SizedBox(
                                      height: 24,
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          _passwordError ?? _loginError ?? '',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Color(0xFFB84C4C),
                                            fontSize: 11,
                                            height: 1,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 4),
                              SizedBox(
                                height: 24,
                                child: Row(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(left: 4),
                                      child: Semantics(
                                        checked: _rememberMe,
                                        label: 'Remember me',
                                        child: GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () => setState(
                                            () => _rememberMe = !_rememberMe,
                                          ),
                                          child: SizedBox(
                                            width: 15,
                                            height: 15,
                                            child: DecoratedBox(
                                              decoration: BoxDecoration(
                                                color: _rememberMe
                                                    ? AppPalette.burgundy
                                                    : Colors.white,
                                                border: Border.all(
                                                  color: AppPalette.ink,
                                                  width: 0.8,
                                                ),
                                              ),
                                              child: _rememberMe
                                                  ? const Icon(
                                                      Icons.check,
                                                      size: 10,
                                                      color: Colors.white,
                                                    )
                                                  : null,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    const Text(
                                      'Remember me',
                                      style: TextStyle(
                                        color: AppPalette.ink,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 0),
                              SizedBox(
                                height: 37,
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _isSubmitting ? null : _submit,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppPalette.burgundy,
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.zero,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(11),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: _isSubmitting
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text(
                                          'Log in',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 5),
                              TextButton(
                                onPressed: () {},
                                style: TextButton.styleFrom(
                                  foregroundColor: AppPalette.ink,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  minimumSize: const Size(160, 32),
                                  tapTargetSize: MaterialTapTargetSize.padded,
                                ),
                                child: const Text(
                                  'Forgot your password?',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Container(height: 3, color: AppPalette.burgundy),
              ],
            );
          },
        ),
      ),
    );
  }
}
