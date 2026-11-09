import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'app_theme.dart';
import 'home_screen.dart';
import 'classwork_screen.dart';
// removed unused import: instructor_homepage.dart
import 'student_homepage.dart';
import 'settings_screen.dart';
import 'firestore_service.dart';
import 'post_date_formatter.dart';
import 'announcement_comments.dart';
import 'task_details_screen.dart';

class StudentSubjectViewScreen extends StatelessWidget {
  final Subject subject;
  final String? profileImageUrl;

  const StudentSubjectViewScreen({
    super.key,
    required this.subject,
    this.profileImageUrl,
  });

  static const Color burgundy = AppPalette.burgundy;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppPalette.background,
        body: SafeArea(
          child: Column(
            children: [
              _buildTopBar(context),
              _buildBannerWithTabs(context),
              Expanded(
                child: TabBarView(
                  children: [
                    StudentClassroomTab(subject: subject),
                    ClassworksScreen(
                      subject: subject,
                      role: UserRole.student,
                      studentName:
                          FirebaseAuth.instance.currentUser?.displayName ??
                          'Student',
                      studentEmail:
                          FirebaseAuth.instance.currentUser?.email ?? '',
                      profileImageUrl: profileImageUrl,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: Container(
          height: 44,
          decoration: const BoxDecoration(
            color: AppPalette.burgundy,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(10),
              topRight: Radius.circular(10),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 40,
                  height: 40,
                ),
                onPressed: () {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const StudentHomePage()),
                    (route) => false,
                  );
                },
                tooltip: 'Home',
                icon: SvgPicture.asset(
                  'home_icon.svg',
                  width: 22,
                  height: 22,
                  colorFilter: const ColorFilter.mode(
                    Colors.white,
                    BlendMode.srcIn,
                  ),
                ),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 40,
                  height: 40,
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SettingsScreen(
                        role: UserRole.student,
                        userName: '',
                        profileImageUrl: profileImageUrl,
                      ),
                    ),
                  );
                },
                icon: SvgPicture.asset(
                  'settings_offpage.svg',
                  width: 22,
                  height: 22,
                  colorFilter: const ColorFilter.mode(
                    Colors.white,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const Expanded(child: VisionGradeWordmark(fontSize: 22)),
          UserProfileAvatar(
            role: UserRole.student,
            userEmail: FirebaseAuth.instance.currentUser?.email ?? '',
            profileImageUrl: profileImageUrl,
          ),
        ],
      ),
    );
  }

  Widget _buildBannerWithTabs(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(6, 6, 6, 0),
      decoration: BoxDecoration(
        color: burgundy,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 28,
                  height: 28,
                ),
                onPressed: () => Navigator.of(context).pop(),
                icon: Image.asset(
                  'white_curved_back_arrow.png',
                  width: 18,
                  height: 18,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subject.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subject.gradeLabel,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Container(
            decoration: BoxDecoration(
              color: AppPalette.cream,
              borderRadius: BorderRadius.circular(32),
            ),
            child: TabBar(
              indicator: BoxDecoration(
                color: AppPalette.burgundyDark,
                borderRadius: BorderRadius.all(Radius.circular(32)),
              ),
              labelColor: Colors.white,
              unselectedLabelColor: AppPalette.ink,
              dividerColor: Colors.transparent,
              labelStyle: const TextStyle(fontSize: 10),
              unselectedLabelStyle: const TextStyle(fontSize: 10),
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorPadding: const EdgeInsets.symmetric(
                horizontal: 3,
                vertical: 2,
              ),
              labelPadding: const EdgeInsets.symmetric(horizontal: 10),
              splashFactory: NoSplash.splashFactory,
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              tabs: const [
                Tab(height: 24, text: 'Classroom'),
                Tab(height: 24, text: 'Classworks'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class StudentClassroomTab extends StatelessWidget {
  final Subject subject;

  const StudentClassroomTab({super.key, required this.subject});

  static const Color beige = AppPalette.cream;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.subjectPostsStream(subject.id),
      builder: (context, snapshot) {
        final currentEmail = FirebaseAuth.instance.currentUser?.email ?? '';
        return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
          stream: FirestoreService.globalAnnouncementsStream(
            email: currentEmail,
            role: 'student',
            authUid: FirebaseAuth.instance.currentUser?.uid ?? '',
          ),
          builder: (context, globalSnapshot) {
            if (snapshot.hasError || globalSnapshot.hasError) {
              return const Center(
                child: Text('Unable to load classroom announcements.'),
              );
            }
            final posts = sortPostsNewestFirst([
              ...(snapshot.data?.docs ?? const []).where(
                (post) =>
                    post.data()['type'] == 'Announcement' ||
                    post.data()['type'] == 'Task',
              ),
              ...(globalSnapshot.data ?? const []),
            ]);

            return RefreshIndicator(
              onRefresh: () => FirestoreService.refreshSubjectContent(
                subjectId: subject.id,
                role: 'student',
                email: currentEmail,
                authUid: FirebaseAuth.instance.currentUser?.uid ?? '',
              ),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: posts.isEmpty
                      ? const [
                          Center(
                            child: Padding(
                              padding: EdgeInsets.only(top: 24),
                              child: Text('No posts have been published yet.'),
                            ),
                          ),
                        ]
                      : posts.map((post) {
                          final isAnnouncement =
                              post.data()['type'] == 'Announcement';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: isAnnouncement
                                ? _buildAnnouncementCard(context, post)
                                : _buildAssignmentCard(context, post),
                          );
                        }).toList(),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAnnouncementCard(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> post,
  ) {
    final postedAnnouncement = post.data();
    final isGlobalAnnouncement =
        post.reference.parent.id == 'global_announcements';
    final student = FirebaseAuth.instance.currentUser;

    return Material(
      color: beige,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AnnouncementDetailsScreen(
              subjectId: subject.id,
              postId: post.id,
              announcement: postedAnnouncement,
              authorName: student?.displayName ?? 'Student',
              authorEmail: student?.email ?? '',
              authorRole: 'Student',
              isGlobalAnnouncement: isGlobalAnnouncement,
            ),
          ),
        ),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 6,
              ),
            ],
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  UserProfileAvatar(
                    role: UserRole.instructor,
                    userEmail:
                        postedAnnouncement['posterEmail']?.toString() ?? '',
                    profileImageUrl: null,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    postedAnnouncement['posterName'] as String? ??
                        postedAnnouncement['author'] as String? ??
                        (isGlobalAnnouncement ? 'Admin' : 'Instructor'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  const Icon(Icons.chevron_right, color: Colors.black54),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                formatPostedDate(postedAnnouncement['postedAt']),
                style: const TextStyle(color: Colors.black54, fontSize: 11),
              ),
              const SizedBox(height: 8),
              Text(
                postedAnnouncement['title'] as String? ?? 'Announcement',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(postedAnnouncement['body'] as String? ?? ''),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAssignmentCard(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> post,
  ) {
    final postedTask = post.data();

    return Material(
      color: beige,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          final student = FirebaseAuth.instance.currentUser;
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TaskDetailsScreen(
                subject: subject,
                role: UserRole.student,
                task: post,
                studentName: student?.displayName ?? 'Student',
                studentEmail: student?.email ?? '',
              ),
            ),
          );
        },
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 6,
              ),
            ],
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.assignment_outlined, size: 28),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  postedTask['title'] as String? ?? 'Untitled task',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.black54),
            ],
          ),
        ),
      ),
    );
  }
}
