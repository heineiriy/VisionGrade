import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'app_theme.dart';
import 'instructor_homepage.dart';
import 'student_homepage.dart';
import 'settings_screen.dart';
import 'firestore_service.dart';
import 'cloudinary_service.dart';

enum UserRole { student, instructor }

class Subject {
  final String id;
  final String title;
  final String gradeLabel;
  final String instructorEmail;
  final String? thumbnailUrl;
  final List<String> avatarInitials;
  final int extraCount;

  Subject({
    this.id = '',
    required this.title,
    required this.gradeLabel,
    this.instructorEmail = '',
    this.thumbnailUrl,
    this.avatarInitials = const ['A', 'J', 'S'],
    this.extraCount = 64,
  });

  static bool isStudentEnrolled(Map<String, dynamic> student, Subject subject) {
    if (student['subjectId'] == subject.id) return true;
    for (final key in [
      'assignedSubjectIds',
      'subjectIds',
      'subjects',
      'enrolledSubjects',
    ]) {
      final values = student[key];
      if (values is List &&
          values.any(
            (value) => value == subject.id || value == subject.title,
          )) {
        return true;
      }
    }
    return false;
  }
}

class HomeScreen extends StatelessWidget {
  static const Color burgundy = AppPalette.burgundy;
  static const Color darkThumb = Color(0xFF1C1B17);

  final UserRole role;
  final String userName;
  final String userEmail;
  final String? profileImageUrl;
  final List<Subject> subjects;
  final String? emptyStateMessage;
  final void Function(Subject)? onSubjectTap;
  final Widget? floatingActionButton;
  final Future<void> Function()? onRefresh;

  const HomeScreen({
    super.key,
    required this.role,
    required this.userName,
    this.userEmail = '',
    this.profileImageUrl,
    this.subjects = const [],
    this.emptyStateMessage,
    this.onSubjectTap,
    this.floatingActionButton,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context),
            _buildWelcomeBanner(context),
            _buildSubjectsSection(context),
          ],
        ),
      ),
      bottomNavigationBar: DashboardBottomNavigation(
        role: role,
        userName: userName,
        userEmail: userEmail,
        profileImageUrl: profileImageUrl,
      ),
      floatingActionButton: floatingActionButton,
    );
  }

  static bool isStudentEnrolled(Map<String, dynamic> student, Subject subject) {
    if (student['subjectId'] == subject.id) return true;
    for (final key in ['subjectIds', 'subjects', 'enrolledSubjects']) {
      final values = student[key];
      if (values is List &&
          values.any(
            (value) => value == subject.id || value == subject.title,
          )) {
        return true;
      }
    }
    return false;
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          const Expanded(child: VisionGradeWordmark(fontSize: 22)),
          UserProfileAvatar(
            role: role,
            userEmail: userEmail,
            profileImageUrl: profileImageUrl,
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeBanner(BuildContext context) {
    final displayName = userName.isNotEmpty
        ? userName
        : (role == UserRole.student ? 'Student' : 'Instructor');

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 0),
      constraints: const BoxConstraints(minHeight: 82),
      decoration: BoxDecoration(
        color: burgundy,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              children: [
                const TextSpan(
                  text: 'Welcome, ',
                  style: TextStyle(color: Colors.white),
                ),
                TextSpan(
                  text: displayName,
                  style: const TextStyle(color: Color(0xFFF0C7C8)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Have a nice day!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectsSection(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Subjects',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppPalette.ink,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: RefreshIndicator(
                onRefresh: onRefresh ?? () async {},
                child: subjects.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: 280,
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                child: Text(
                                  emptyStateMessage ??
                                      (role == UserRole.student
                                          ? 'No subjects are available yet. Ask your instructor or administrator to check your grade, section, and subject assignments.'
                                          : 'No subjects yet.'),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: AppPalette.muted,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: subjects.length,
                        padding: const EdgeInsets.only(bottom: 20),
                        itemBuilder: (context, index) {
                          final subject = subjects[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _SubjectCard(
                              subject: subject,
                              canEditThumbnail: role == UserRole.instructor,
                              onTap: () => onSubjectTap?.call(subject),
                              onThumbnailChanged: () =>
                                  _uploadSubjectPhoto(context, subject),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _uploadSubjectPhoto(
    BuildContext context,
    Subject subject,
  ) async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 75,
        maxWidth: 1200,
        maxHeight: 1200,
      );
      if (file == null || !context.mounted) return;
      final imageBytes = await file.readAsBytes().timeout(
        const Duration(seconds: 20),
        onTimeout: () =>
            throw TimeoutException('Reading the selected picture timed out.'),
      );
      if (imageBytes.isEmpty) {
        throw StateError('The selected picture is empty.');
      }
      final thumbnailUrl = await CloudinaryService.uploadBytes(
        bytes: imageBytes,
        fileName:
            'subject_${subject.id}_${DateTime.now().millisecondsSinceEpoch}.jpg',
        timeout: const Duration(seconds: 60),
      );
      await FirestoreService.updateSubjectThumbnail(
        subjectId: subject.id,
        thumbnailUrl: thumbnailUrl,
      ).timeout(
        const Duration(seconds: 20),
        onTimeout: () =>
            throw TimeoutException('Saving the subject picture timed out.'),
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Subject photo updated')));
    } on CloudinaryUploadException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Photo upload failed: ${error.message}')),
        );
      }
    } on FirebaseException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save the photo (${error.code}).')),
        );
      }
    } on TimeoutException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message ?? 'Photo update timed out.')),
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Failed to update subject photo: $error\n$stackTrace');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update the subject photo.')),
        );
      }
    }
  }
}

class UserProfileAvatar extends StatelessWidget {
  final UserRole role;
  final String userEmail;
  final String? profileImageUrl;
  final double radius;

  const UserProfileAvatar({
    super.key,
    required this.role,
    required this.userEmail,
    required this.profileImageUrl,
    this.radius = 18,
  });

  @override
  Widget build(BuildContext context) {
    final collection = role == UserRole.instructor
        ? 'instructor_accounts'
        : 'students';
    final email = userEmail.trim();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: email.isEmpty
          ? null
          : FirestoreService.userProfileStream(
              collection: collection,
              email: email,
            ),
      builder: (context, snapshot) {
        final profile = snapshot.data?.docs.isNotEmpty == true
            ? snapshot.data!.docs.first.data()
            : null;
        final savedUrl = profile?['profileImageUrl']?.toString().trim();
        final alternateUrl = profile?['photoUrl']?.toString().trim();
        final imageUrl = savedUrl != null && savedUrl.isNotEmpty
            ? savedUrl
            : alternateUrl != null && alternateUrl.isNotEmpty
            ? alternateUrl
            : profileImageUrl;
        return CircleAvatar(
          key: ValueKey(imageUrl),
          radius: radius,
          backgroundImage: imageUrl != null && imageUrl.isNotEmpty
              ? NetworkImage(imageUrl)
              : null,
          backgroundColor: AppPalette.cream,
          child: imageUrl == null || imageUrl.isEmpty
              ? const Icon(Icons.person, color: AppPalette.burgundyDark)
              : null,
        );
      },
    );
  }
}

class DashboardBottomNavigation extends StatelessWidget {
  final UserRole role;
  final String userName;
  final String userEmail;
  final String? profileImageUrl;
  final bool homeIsActive;

  const DashboardBottomNavigation({
    super.key,
    required this.role,
    this.userName = '',
    this.userEmail = '',
    this.profileImageUrl,
    this.homeIsActive = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: const BoxDecoration(
        color: AppPalette.burgundy,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(10),
          topRight: Radius.circular(10),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              left: constraints.maxWidth * 0.25,
              child: _bottomNavButton(
                asset: 'home_icon.svg',
                isActive: homeIsActive,
                onPressed: () {
                  if (role == UserRole.instructor) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                        builder: (_) => InstructorHomePage(
                          instructorName: userName,
                          instructorEmail: userEmail,
                          profileImageUrl: profileImageUrl,
                        ),
                      ),
                      (route) => false,
                    );
                  } else {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                        builder: (_) => StudentHomePage(
                          studentName: userName,
                          studentEmail: userEmail,
                          profileImageUrl: profileImageUrl,
                        ),
                      ),
                      (route) => false,
                    );
                  }
                },
              ),
            ),
            Positioned(
              right: constraints.maxWidth * 0.25,
              child: _bottomNavButton(
                asset: 'settings_offpage.svg',
                isActive: false,
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SettingsScreen(
                        role: role,
                        userName: userName,
                        userEmail: userEmail,
                        profileImageUrl: profileImageUrl,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomNavButton({
    required String asset,
    required bool isActive,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 40,
      height: 40,
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: BoxConstraints.tightFor(width: 40, height: 40),
        onPressed: onPressed,
        icon: SvgPicture.asset(
          asset,
          width: 22,
          height: 22,
          colorFilter: ColorFilter.mode(
            isActive ? AppPalette.burgundyDark : Colors.white,
            BlendMode.srcIn,
          ),
        ),
      ),
    );
  }
}

class _SubjectCard extends StatefulWidget {
  final Subject subject;
  final VoidCallback? onTap;
  final bool canEditThumbnail;
  final Future<void> Function()? onThumbnailChanged;

  const _SubjectCard({
    required this.subject,
    this.onTap,
    this.canEditThumbnail = false,
    this.onThumbnailChanged,
  });

  @override
  State<_SubjectCard> createState() => _SubjectCardState();
}

class _SubjectCardState extends State<_SubjectCard> {
  bool _isChangingThumbnail = false;

  Future<void> _changeThumbnail() async {
    final onThumbnailChanged = widget.onThumbnailChanged;
    if (_isChangingThumbnail || onThumbnailChanged == null) return;
    setState(() => _isChangingThumbnail = true);
    try {
      await onThumbnailChanged();
    } finally {
      if (mounted) setState(() => _isChangingThumbnail = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.studentsStream(),
      builder: (context, snapshot) {
        final enrolled = (snapshot.data?.docs ?? const [])
            .where(
              (doc) => Subject.isStudentEnrolled(doc.data(), widget.subject),
            )
            .toList();
        final initials = enrolled
            .map((doc) => _initials(doc.data()['name'] as String? ?? 'Student'))
            .take(3)
            .toList();
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: widget.onTap,
            child: Container(
              decoration: BoxDecoration(
                color: AppPalette.subjectCard,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: EdgeInsets.zero,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(8),
                        ),
                        child: _buildSubjectThumbnail(),
                      ),
                      if (widget.canEditThumbnail)
                        Positioned(
                          right: 2,
                          bottom: 2,
                          child: InkResponse(
                            onTap: _isChangingThumbnail
                                ? null
                                : _changeThumbnail,
                            radius: 16,
                            child: CircleAvatar(
                              radius: 12,
                              backgroundColor: Colors.white,
                              child: _isChangingThumbnail
                                  ? const Padding(
                                      padding: EdgeInsets.all(5),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.camera_alt, size: 14),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.subject.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.subject.gradeLabel,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            _buildAvatarStack(
                              initials.isEmpty
                                  ? widget.subject.avatarInitials
                                  : initials,
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppPalette.burgundy,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '+${enrolled.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 9,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Center(
                      child: Material(
                        color: AppPalette.cream,
                        shape: const CircleBorder(),
                        child: InkWell(
                          onTap: widget.onTap,
                          customBorder: const CircleBorder(),
                          child: const SizedBox(
                            width: 22,
                            height: 22,
                            child: Center(
                              child: Icon(
                                Icons.arrow_forward,
                                color: AppPalette.subjectCard,
                                size: 16,
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
        );
      },
    );
  }

  Widget _buildSubjectThumbnail() {
    final rawUrl = widget.subject.thumbnailUrl?.trim();
    final uri = rawUrl == null || rawUrl.isEmpty ? null : Uri.tryParse(rawUrl);
    final isValidImageUrl =
        uri != null &&
        uri.hasScheme &&
        (uri.scheme == 'http' || uri.scheme == 'https');

    if (!isValidImageUrl) {
      return _buildThumbnailFallback();
    }

    return SizedBox(
      width: 104,
      height: 110,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildThumbnailFallback(),
          Image.network(
            uri.toString(),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                const SizedBox.shrink(),
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnailFallback() {
    return Container(
      width: 104,
      height: 110,
      color: const Color(0xFF322C29),
      child: const Icon(Icons.menu_book, color: Colors.white70),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  Widget _buildAvatarStack(List<String> initials) {
    const double size = 18;
    return SizedBox(
      width: size + (initials.length > 1 ? initials.length - 1 : 0) * 12,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: List.generate(initials.length, (i) {
          final left = i * 12.0;
          final bg = i == 0
              ? Colors.green.shade300
              : (i == 1 ? Colors.grey.shade800 : Colors.green.shade800);
          return Positioned(
            left: left,
            child: CircleAvatar(
              radius: size / 2,
              backgroundColor: bg,
              child: Text(
                initials[i],
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
