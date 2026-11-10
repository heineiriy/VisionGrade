import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import 'app_theme.dart';
import 'cloudinary_service.dart';
import 'firestore_service.dart';
import 'post_date_formatter.dart';
import 'task_due_date.dart';
import 'messaging_screen.dart';
import 'home_screen.dart';
import 'camera_scanner.dart';
import 'grading_service.dart';
import 'submission_image_review.dart';
import 'settings_screen.dart';
import 'task_pdf_viewer.dart';

class TaskDetailsScreen extends StatefulWidget {
  final Subject subject;
  final UserRole role;
  final DocumentSnapshot<Map<String, dynamic>> task;
  final String studentName;
  final String studentEmail;
  final String? profileImageUrl;
  const TaskDetailsScreen({
    super.key,
    required this.subject,
    required this.role,
    required this.task,
    this.studentName = '',
    this.studentEmail = '',
    this.profileImageUrl,
  });

  @override
  State<TaskDetailsScreen> createState() => _TaskDetailsScreenState();
}

class _TaskDetailsScreenState extends State<TaskDetailsScreen> {
  static const Color burgundy = AppPalette.burgundy;
  String? _scanningStudentEmail;
  Map<String, dynamic>? _taskData;

  Map<String, dynamic> get task => _taskData ?? widget.task.data() ?? const {};
  bool get allowsUpload => task['allowUpload'] as bool? ?? false;
  bool get submissionsClosed =>
      taskDueStatus(
        task['dueDate'] ?? task['due'],
        closeAfterDeadline: task['closeAfterDeadline'] as bool? ?? true,
      ) ==
      'Closed';

  bool _isSubmissionGraded(Map<String, dynamic>? submission) {
    return submission != null &&
        (submission['status'] == 'Graded' ||
            submission['reviewStatus'] == 'published' ||
            submission['score'] != null);
  }

  bool _hasScannedWork(Map<String, dynamic>? submission) {
    return submission != null &&
        (((submission['scanUrl'] as String?)?.trim().isNotEmpty ?? false) ||
            (submission['scanUrls'] is Iterable &&
                (submission['scanUrls'] as Iterable).whereType<String>().any(
                  (url) => url.trim().isNotEmpty,
                )));
  }

  String _studentReportStatus(Map<String, dynamic>? submission) {
    if (submission == null) {
      final dueDate = taskDueDate(task['dueDate'] ?? task['due']);
      return dueDate != null && !isTaskDeadlineValid(dueDate)
          ? 'Missing'
          : 'Pending';
    }
    if (_isSubmissionGraded(submission)) return 'Graded';
    if (!allowsUpload && _hasScannedWork(submission)) return 'To Review';
    return 'To Scan';
  }

  @override
  void initState() {
    super.initState();
    _taskData = widget.task.data();
  }

  Future<void> _refreshPage() async {
    final currentEmail = FirebaseAuth.instance.currentUser?.email ?? '';
    final refreshes = <Future<void>>[
      widget.task.reference.get(const GetOptions(source: Source.server)).then((
        snapshot,
      ) {
        if (!snapshot.exists) {
          throw StateError('This task is no longer available.');
        }
        if (mounted) {
          setState(() {
            _taskData = snapshot.data();
          });
        }
      }),
      FirestoreService.refreshSubjectContent(
        subjectId: widget.subject.id,
        role: widget.role == UserRole.instructor ? 'instructor' : 'student',
        email: widget.role == UserRole.instructor
            ? currentEmail
            : widget.studentEmail,
        authUid: FirebaseAuth.instance.currentUser?.uid ?? '',
      ),
    ];
    await Future.wait(refreshes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.background,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              height: 54,
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  const Expanded(child: VisionGradeWordmark(fontSize: 22)),
                  UserProfileAvatar(
                    role: widget.role,
                    userEmail: FirebaseAuth.instance.currentUser?.email ?? '',
                    profileImageUrl:
                        widget.profileImageUrl ??
                        FirebaseAuth.instance.currentUser?.photoURL,
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(6, 6, 6, 0),
              decoration: BoxDecoration(
                color: burgundy,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
              child: Row(
                children: [
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Image.asset(
                      'white_curved_back_arrow.png',
                      width: 18,
                      height: 18,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      task['title'] as String? ?? 'Assignment',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (widget.role == UserRole.student)
                    _buildStudentGradeBadge(),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refreshPage,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInstructionCard(),
                      const SizedBox(height: 18),
                      if (widget.role == UserRole.instructor)
                        _buildInstructorReport()
                      else
                        _buildStudentAction(),
                      if (widget.role == UserRole.student &&
                          (task['posterEmail'] as String? ?? '')
                              .trim()
                              .isNotEmpty) ...[
                        const Divider(height: 28),
                        Center(
                          child: OutlinedButton.icon(
                            onPressed: () => showPrivateMessageSheet(
                              context: context,
                              studentEmail: widget.studentEmail,
                              studentName: widget.studentName,
                              instructorEmail: task['posterEmail'] as String,
                              instructorName:
                                  task['posterName'] as String? ?? 'Instructor',
                              subjectTitle: widget.subject.title,
                              subjectId: widget.subject.id,
                              taskTitle:
                                  task['title'] as String? ?? 'Assignment',
                              taskId: widget.task.id,
                            ),
                            icon: const Icon(Icons.chat_bubble_outline),
                            label: const Text('Message instructor privately'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
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
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                left: constraints.maxWidth * 0.25,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 40,
                    height: 40,
                  ),
                  onPressed: () => Navigator.of(context).maybePop(),
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
              ),
              Positioned(
                right: constraints.maxWidth * 0.25,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 40,
                    height: 40,
                  ),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SettingsScreen(
                        role: widget.role,
                        userName: widget.studentName,
                        userEmail: widget.studentEmail,
                        profileImageUrl: widget.profileImageUrl,
                      ),
                    ),
                  ),
                  tooltip: 'Settings',
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInstructionCard() {
    final posterEmail = (task['posterEmail'] as String? ?? '').trim();
    final taskBody =
        (task['body'] as String? ??
                'Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco.')
            .replaceAll('\r\n', '\n')
            .replaceAll('\r', '\n')
            .split('\n')
            .map((line) => line.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
            .join('\n')
            .replaceAll(RegExp(r'\n{3,}'), '\n\n')
            .trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: AppPalette.cream,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserProfileAvatar(
                role: UserRole.instructor,
                userEmail: posterEmail.isNotEmpty
                    ? posterEmail
                    : widget.subject.instructorEmail,
                profileImageUrl:
                    posterEmail.isEmpty && widget.role == UserRole.instructor
                    ? widget.profileImageUrl
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      task['posterName'] as String? ?? 'Instructor',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                        color: AppPalette.ink,
                      ),
                    ),
                    Text(
                      'Due: ${formatTaskDueDate(task['dueDate'] ?? task['due'])}',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            formatPostedDate(task['postedAt']),
            style: GoogleFonts.inter(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          Text(
            taskBody,
            style: GoogleFonts.inter(
              fontSize: 14,
              height: 1.55,
              color: AppPalette.ink,
            ),
          ),
          if (task['attachmentUrl'] is String &&
              (task['attachmentUrl'] as String).trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => openTaskAttachment(
                  context,
                  url: task['attachmentUrl'] as String,
                  name:
                      task['attachmentName'] as String? ?? 'Task instructions',
                ),
                icon: const Icon(Icons.attach_file, size: 18),
                label: Text(
                  task['attachmentName'] as String? ?? 'Task instructions',
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Rubric',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
              fontSize: 17,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 10),
          _buildRubricTable(task['rubric']),
          /* Table(
            border: TableBorder.all(color: const Color(0xFF9B8B72)),
            columnWidths: const {
              0: FlexColumnWidth(0.26),
              1: FlexColumnWidth(0.74),
            },
            children: const [
              TableRow(
                decoration: BoxDecoration(color: Color(0xFFD5C4A0)),
                children: [
                  Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'Levels',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'Description',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              TableRow(
                children: [
                  Padding(padding: EdgeInsets.all(8), child: Text('4')),
                  Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('Exceeds expectations'),
                  ),
                ],
              ),
              TableRow(
                children: [
                  Padding(padding: EdgeInsets.all(8), child: Text('3')),
                  Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('Meets expectations'),
                  ),
                ],
              ),
              TableRow(
                children: [
                  Padding(padding: EdgeInsets.all(8), child: Text('2')),
                  Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('Progressing'),
                  ),
                ],
              ),
              TableRow(
                children: [
                  Padding(padding: EdgeInsets.all(8), child: Text('1')),
                  Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('Needs improvement'),
                  ),
                ],
              ),
            ],
          ), */
        ],
      ),
    );
  }

  Widget _buildRubricTable(dynamic rawRubric) {
    if (rawRubric is! Map) {
      return const Text('No rubric attached to this task.');
    }
    final rubric = Map<String, dynamic>.from(rawRubric);
    final rawCriteria = rubric['criteria'];
    final criteria = rawCriteria is List
        ? rawCriteria.whereType<Map>().map(Map<String, dynamic>.from).toList()
        : <Map<String, dynamic>>[];
    if (criteria.isEmpty) {
      return const Text('No rubric criteria have been added.');
    }

    final isAnalytic = rubric['type'] == 'Analytic';
    final inferredLevelCount = criteria.fold<int>(0, (maximum, criterion) {
      final levels = criterion['levels'];
      final count = levels is List ? levels.length : 0;
      return count > maximum ? count : maximum;
    });
    final savedLevelCount = rubric['levelCount'];
    final levelCount =
        ((savedLevelCount is num
                    ? savedLevelCount.toInt()
                    : inferredLevelCount > 0
                    ? inferredLevelCount
                    : 4)
                .clamp(1, 5))
            .toInt();
    final table = isAnalytic
        ? Table(
            border: TableBorder.symmetric(
              outside: const BorderSide(color: Color(0xFF8F7C5F), width: 1.2),
              inside: BorderSide(
                color: const Color(0xFF8F7C5F).withValues(alpha: 0.65),
                width: 0.8,
              ),
            ),
            columnWidths: {
              0: const FlexColumnWidth(1.5),
              for (var index = 1; index <= levelCount; index++)
                index: const FlexColumnWidth(1),
              levelCount + 1: const FlexColumnWidth(0.8),
            },
            children: [
              TableRow(
                decoration: const BoxDecoration(color: Color(0xFFC9B89B)),
                children: [
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox.shrink(),
                  ),
                  for (var index = 0; index < levelCount; index++)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'Score',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              ...criteria.map((criterion) {
                final levels = criterion['levels'] is List
                    ? criterion['levels'] as List
                    : const [];
                return TableRow(
                  decoration: const BoxDecoration(color: Color(0xFFE6D6B8)),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(criterion['title']?.toString() ?? ''),
                    ),
                    for (var index = 0; index < levelCount; index++)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          index < levels.length ? levels[index].toString() : '',
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(criterion['score']?.toString() ?? ''),
                    ),
                  ],
                );
              }),
            ],
          )
        : Table(
            border: TableBorder.symmetric(
              outside: const BorderSide(color: Color(0xFF8F7C5F), width: 1.2),
              inside: BorderSide(
                color: const Color(0xFF8F7C5F).withValues(alpha: 0.65),
                width: 0.8,
              ),
            ),
            columnWidths: const {
              0: IntrinsicColumnWidth(flex: 1),
              1: FlexColumnWidth(3),
            },
            children: [
              const TableRow(
                decoration: BoxDecoration(color: Color(0xFFC9B89B)),
                children: [
                  Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'Points',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'Description',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              ...criteria.map(
                (criterion) => TableRow(
                  decoration: const BoxDecoration(color: Color(0xFFE6D6B8)),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(criterion['points']?.toString() ?? ''),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(criterion['description']?.toString() ?? ''),
                    ),
                  ],
                ),
              ),
            ],
          );
    final title = rubric['title']?.toString().trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty) ...[
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
        ],
        table,
      ],
    );
  }

  bool _studentBelongsToSubject(Map<String, dynamic> student) {
    final rawAssigned =
        student['assignedSubjectIds'] ??
        student['subjectIds'] ??
        student['subjects'] ??
        student['enrolledSubjects'] ??
        <String>[];

    if (rawAssigned is! Iterable) return false;

    final values = rawAssigned
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();

    return values.any(
      (value) => value == widget.subject.id || value == widget.subject.title,
    );
  }

  Widget _buildInstructorReport() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.submissionsStream(
        subjectId: widget.subject.id,
        taskId: widget.task.id,
      ),
      builder: (context, submissionSnapshot) {
        final submissions =
            submissionSnapshot.data?.docs ??
            const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final submissionMap = <String, Map<String, dynamic>>{};
        for (final doc in submissions) {
          final data = doc.data();
          if (data['status'] != 'Submitted' &&
              data['status'] != 'Graded' &&
              data['reviewStatus'] != 'published' &&
              data['score'] == null) {
            continue;
          }
          final email = (data['studentEmail'] as String?)?.trim();
          if (email != null && email.isNotEmpty) {
            submissionMap[email.toLowerCase()] = data;
          }
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirestoreService.studentsStream(),
          builder: (context, studentSnapshot) {
            final students =
                (studentSnapshot.data?.docs ??
                        const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                    .where((doc) => _studentBelongsToSubject(doc.data()))
                    .toList();

            return Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Student Report',
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.black,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: students.isEmpty
                              ? null
                              : () => _exportPerformanceData(
                                  students: students,
                                  submissions: submissionMap,
                                ),
                          icon: const Icon(Icons.download_outlined, size: 18),
                          label: const Text('Export CSV'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFD7D0C7)),
                    ),
                    child: Table(
                      columnWidths: const {
                        0: FlexColumnWidth(2.1),
                        1: FlexColumnWidth(1.2),
                        2: FlexColumnWidth(0.9),
                        3: FlexColumnWidth(1),
                      },
                      children: [
                        TableRow(
                          decoration: const BoxDecoration(color: burgundy),
                          children: [
                            _tableHeaderCell('Student Name'),
                            _tableHeaderCell('Status'),
                            _tableHeaderCell('Grade'),
                            _tableHeaderCell('Action'),
                          ],
                        ),
                        ...students.map((studentDoc) {
                          final student = studentDoc.data();
                          final studentEmail =
                              (student['email'] as String?)?.trim() ?? '';
                          final name =
                              (student['name'] as String?) ?? 'Student';
                          final submission =
                              submissionMap[studentEmail.toLowerCase()];
                          final hasSubmission = submission != null;
                          final isGraded = _isSubmissionGraded(submission);
                          final hasScan = _hasScannedWork(submission);
                          final status = _studentReportStatus(submission);
                          final score = submission?['score'];
                          final maxScore = submission?['maxScore'];
                          final grade = isGraded && score != null
                              ? maxScore != null
                                    ? '$score / $maxScore'
                                    : score.toString()
                              : '-';
                          final action = allowsUpload && !hasSubmission
                              ? 'Awaiting'
                              : !hasSubmission
                              ? 'Scan'
                              : isGraded
                              ? 'Review'
                              : 'Grade';
                          return TableRow(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(10),
                                child: Text(
                                  name,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                child: Container(
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: status == 'Graded'
                                        ? const Color(0xFFE3F3E5)
                                        : status == 'To Scan'
                                        ? const Color(0xFFE9F0FF)
                                        : status == 'To Review'
                                        ? const Color(0xFFFFE8D6)
                                        : status == 'Pending'
                                        ? const Color(0xFFFFF3D6)
                                        : const Color(0xFFF0E7E2),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Text(
                                    status,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: status == 'Graded'
                                          ? const Color(0xFF3E7A4A)
                                          : status == 'To Scan'
                                          ? const Color(0xFF3558A8)
                                          : status == 'To Review'
                                          ? const Color(0xFF9A4D16)
                                          : status == 'Pending'
                                          ? const Color(0xFF8A6510)
                                          : const Color(0xFF7A2027),
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(10),
                                child: Text(
                                  grade,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(9),
                                child: SizedBox(
                                  height: 26,
                                  child: ElevatedButton(
                                    onPressed:
                                        studentEmail.isEmpty ||
                                            _scanningStudentEmail != null ||
                                            (allowsUpload && !hasSubmission)
                                        ? null
                                        : () {
                                            if (submission != null &&
                                                (isGraded || hasScan)) {
                                              _showReviewDialog(
                                                studentEmail,
                                                submission,
                                              );
                                            } else if (submission != null) {
                                              _showGradeDialog(
                                                studentEmail,
                                                submission,
                                              );
                                            } else {
                                              _scanHardcopy(
                                                studentName: name,
                                                studentEmail: studentEmail,
                                              );
                                            }
                                          },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: hasSubmission
                                          ? const Color(0xFF6A6A6A)
                                          : const Color(0xFF5C8F5F),
                                      padding: EdgeInsets.zero,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: Text(
                                      action,
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }),
                        if (students.isEmpty)
                          const TableRow(
                            children: [
                              Padding(
                                padding: EdgeInsets.all(14),
                                child: Text(
                                  'No students enrolled in this subject yet.',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                              SizedBox(),
                              SizedBox(),
                              SizedBox(),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _exportPerformanceData({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> students,
    required Map<String, Map<String, dynamic>> submissions,
  }) async {
    String csvCell(Object? value) {
      final text = value?.toString() ?? '';
      final safeText = RegExp(r'^[\t\r ]*[=+\-@]').hasMatch(text)
          ? "'$text"
          : text;
      return '"${safeText.replaceAll('"', '""')}"';
    }

    final rows = <List<Object?>>[
      [
        'Task',
        'Student name',
        'Student email',
        'Submission status',
        'Score',
        'Maximum score',
        'AI suggested score',
        'AI confidence',
        'Instructor feedback',
        'Assessment suggestions',
        'Submitted at',
        'Reviewed at',
      ],
      ...students.map((studentDoc) {
        final student = studentDoc.data();
        final email = (student['email'] as String?)?.trim() ?? '';
        final submission = submissions[email.toLowerCase()];
        final rawInsights = submission?['aiInsights'];
        final submittedAt = submission?['submittedAt'];
        final gradedAt = submission?['gradedAt'];
        final status = _studentReportStatus(submission);

        return <Object?>[
          task['title'] ?? 'Untitled task',
          student['name'] ?? 'Student',
          email,
          status,
          submission?['score'],
          submission?['maxScore'],
          submission?['aiScore'],
          submission?['aiConfidence'],
          submission?['feedback'],
          rawInsights is Iterable ? rawInsights.join('; ') : '',
          submittedAt is Timestamp
              ? submittedAt.toDate().toIso8601String()
              : submittedAt ?? '',
          gradedAt is Timestamp
              ? gradedAt.toDate().toIso8601String()
              : gradedAt ?? '',
        ];
      }),
    ];
    final content = rows.map((row) => row.map(csvCell).join(',')).join('\r\n');

    try {
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Export student performance',
        fileName: 'visiongrade_${widget.task.id}_performance.csv',
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        bytes: Uint8List.fromList(utf8.encode('\uFEFF$content')),
      );
      if (savedPath == null || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Student performance report exported.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not export the report: $error')),
      );
    }
  }

  Widget _tableHeaderCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 10,
        ),
      ),
    );
  }

  Future<void> _scanHardcopy({
    required String studentName,
    required String studentEmail,
  }) async {
    if (studentEmail.isEmpty || _scanningStudentEmail != null) return;
    setState(() => _scanningStudentEmail = studentEmail);

    try {
      final images = await HardcopyScanner.capture(context);
      if (images == null || images.isEmpty) return;
      final scanUrls = <String>[];
      final scanBytes = <Uint8List>[];
      for (var index = 0; index < images.length; index++) {
        final bytes = await images[index].readAsBytes();
        scanBytes.add(bytes);
        final extension = images[index].name.toLowerCase().endsWith('.png')
            ? 'png'
            : 'jpg';
        final fileName =
            '${studentEmail.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}_${DateTime.now().millisecondsSinceEpoch}_$index.$extension';
        scanUrls.add(
          await CloudinaryService.uploadBytes(
            bytes: bytes,
            fileName: 'scan_${widget.subject.id}_${widget.task.id}_$fileName',
          ),
        );
      }
      await FirestoreService.recordHardcopyScan(
        subjectId: widget.subject.id,
        taskId: widget.task.id,
        studentEmail: studentEmail,
        studentName: studentName,
        scanUrl: scanUrls.first,
        scanUrls: scanUrls,
      );
      final scanSubmission = <String, dynamic>{
        'studentName': studentName,
        'answer': 'Hardcopy scan ready for grading.',
        'scanUrl': scanUrls.first,
        'scanUrls': scanUrls,
      };
      try {
        final aiResult = await GradingService.gradeScans(
          images: scanBytes,
          task: task,
          expectedStudentName: studentName,
        );
        final rawInsights = aiResult['details'];
        final insights = rawInsights is Iterable
            ? rawInsights.whereType<Map>().map((detail) {
                final score = detail['predicted_score'];
                final maximum = detail['max_score'];
                final confidence = detail['confidence'];
                final rubricLevel = detail['rubric_level'];
                final title = detail['title'] ?? detail['question'];
                return '$title: AI suggests $score / $maximum'
                    '${rubricLevel is String ? ' ($rubricLevel)' : ''}'
                    '${confidence is num ? ' (${(confidence * 100).round()}% confidence)' : ''}.';
              }).toList()
            : <String>[];
        final reviewReasons = aiResult['review_reasons'];
        if (reviewReasons is Iterable) {
          insights.addAll(
            reviewReasons.whereType<String>().map(
              (reason) => 'Review required: $reason',
            ),
          );
        }
        final rawVisualAnalysis = aiResult['visual_analysis'];
        final visualAnalysis = rawVisualAnalysis is Map
            ? Map<String, dynamic>.from(rawVisualAnalysis)
            : <String, dynamic>{};
        visualAnalysis.remove('pages');
        final pagesAnalyzed = visualAnalysis['pages_analyzed'];
        final detectedPages = visualAnalysis['pages_with_detected_document'];
        if (pagesAnalyzed is num && detectedPages is num) {
          if (pagesAnalyzed > 0 && detectedPages <= 0) {
            insights.add(
              'No page outline was detected. Check that the scan contains the '
              'student answer sheet and verify the AI suggestion.',
            );
          } else {
            insights.add(
              'Page detection: ${detectedPages.toInt()} of '
              '${pagesAnalyzed.toInt()} pages. Visual measurements are '
              'screening indicators, not a grade.',
            );
          }
        }
        final rawVisualFeatures = visualAnalysis['features'];
        if (rawVisualFeatures is Map) {
          final features = Map<String, dynamic>.from(rawVisualFeatures);
          final contentRegions = features['content_regions'];
          final horizontalBalance = features['horizontal_balance'];
          final verticalBalance = features['vertical_balance'];
          if (contentRegions is num &&
              horizontalBalance is num &&
              verticalBalance is num) {
            insights.add(
              'Layout indicators: ${contentRegions.toInt()} content regions; '
              'left/right balance ${(horizontalBalance * 100).round()}%; '
              'top/bottom balance ${(verticalBalance * 100).round()}%. '
              'Review these against the task rubric.',
            );
          }
        }
        final aiScore = (aiResult['ai_score'] as num?)?.toDouble();
        final aiConfidence = (aiResult['ai_confidence'] as num?)?.toDouble();
        final matchedStandards =
            (aiResult['matched_curriculum_standards'] is List)
            ? (aiResult['matched_curriculum_standards'] as List)
                  .map((value) => value.toString())
                  .toList()
            : <String>[];
        final missingStandards =
            (aiResult['missing_curriculum_standards'] is List)
            ? (aiResult['missing_curriculum_standards'] as List)
                  .map((value) => value.toString())
                  .toList()
            : <String>[];
        final visualRecommendations =
            (aiResult['visual_recommendations'] is List)
            ? (aiResult['visual_recommendations'] as List)
                  .whereType<Map>()
                  .map(Map<String, dynamic>.from)
                  .toList()
            : <Map<String, dynamic>>[];
        final criterionResults = (aiResult['criterion_results'] is List)
            ? (aiResult['criterion_results'] as List)
                  .whereType<Map>()
                  .map(Map<String, dynamic>.from)
                  .toList()
            : <Map<String, dynamic>>[];
        final criterionScores = (aiResult['criterion_scores'] is List)
            ? (aiResult['criterion_scores'] as List)
                  .whereType<Map>()
                  .map(Map<String, dynamic>.from)
                  .toList()
            : <Map<String, dynamic>>[];
        final aiFeedback = (aiResult['feedback'] is List)
            ? (aiResult['feedback'] as List)
                  .whereType<String>()
                  .where((item) => item.trim().isNotEmpty)
                  .toList()
            : <String>[];
        final textFeatures = aiResult['text_features'] is Map
            ? Map<String, dynamic>.from(aiResult['text_features'] as Map)
            : <String, dynamic>{};
        insights.addAll(aiFeedback);
        if (matchedStandards.isNotEmpty) {
          insights.add(
            'Curriculum evidence found: ${matchedStandards.join(', ')}.',
          );
        }
        if (missingStandards.isNotEmpty) {
          insights.add(
            'Curriculum evidence to review: ${missingStandards.join(', ')}.',
          );
        }
        for (final recommendation in visualRecommendations) {
          insights.add(
            'Visual ${recommendation['title']}: recommended '
            '${recommendation['recommendedScore']}% '
            '(level ${recommendation['recommendedLevel']}/'
            '${recommendation['maxLevel']}); verify against the original scan.',
          );
        }
        final extractedText = aiResult['extracted_text'] as String? ?? '';
        final expectedAnswer = aiResult['expected_answer'] as String? ?? '';
        if (aiScore == null || aiConfidence == null || extractedText.isEmpty) {
          throw const GradingApiException(
            'The grading service did not return a complete result.',
          );
        }
        await FirestoreService.updateSubmissionAiGrading(
          subjectId: widget.subject.id,
          taskId: widget.task.id,
          studentEmail: studentEmail,
          aiScore: aiScore,
          aiConfidence: aiConfidence,
          extractedText: extractedText,
          aiInsights: insights,
          expectedAnswer: expectedAnswer,
          visualAnalysis: visualAnalysis,
          criterionResults: criterionResults,
          criterionScores: criterionScores,
          aiFeedback: aiFeedback,
          textFeatures: textFeatures,
          matchedStandards: matchedStandards,
          missingStandards: missingStandards,
        );
        scanSubmission.addAll({
          'aiScore': aiScore,
          'aiConfidence': aiConfidence,
          'extractedText': extractedText,
          'aiInsights': insights,
          'aiExpectedAnswer': expectedAnswer,
          'visualAnalysis': visualAnalysis,
          'aiCriterionResults': criterionResults,
          'aiCriterionScores': criterionScores,
          'aiFeedback': aiFeedback,
          'aiTextFeatures': textFeatures,
        });
      } on GradingApiException catch (error) {
        debugPrint('AI grading was unavailable: ${error.message}');
        scanSubmission['aiError'] = error.message;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Scan saved. ${error.message}')),
          );
        }
      } on FirebaseException catch (error) {
        debugPrint('Could not save the AI grading result: ${error.code}');
        scanSubmission['aiError'] =
            'The AI result could not be saved (${error.code}).';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Scan saved, but the AI result could not be saved (${error.code}).',
              ),
            ),
          );
        }
      }
      if (mounted) {
        setState(() {});
        await _showScanResultDialog(studentEmail, scanSubmission);
      }
    } on CloudinaryUploadException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan failed: ${error.message}')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Camera scan failed: $error')));
      }
    } finally {
      if (mounted) setState(() => _scanningStudentEmail = null);
    }
  }

  Future<void> _showScanResultDialog(
    String studentEmail,
    Map<String, dynamic> submission,
  ) async {
    final scanUrls = <String>[
      if (submission['scanUrls'] is Iterable)
        for (final url in submission['scanUrls'] as Iterable)
          if (url is String && url.trim().isNotEmpty) url.trim(),
      if (submission['scanUrls'] is! Iterable &&
          submission['scanUrl'] is String &&
          (submission['scanUrl'] as String).trim().isNotEmpty)
        (submission['scanUrl'] as String).trim(),
    ];
    var currentPage = 0;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 420,
              maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.92,
            ),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE7D7B8),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFB7A991)),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 12,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFB7A991)),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Column(
                  children: [
                    Container(
                      height: 38,
                      padding: const EdgeInsets.only(left: 20, right: 10),
                      decoration: BoxDecoration(
                        color: burgundy,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'AI Analysis',
                              style: GoogleFonts.inter(
                                color: const Color(0xFFFFF8ED),
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                            icon: const Icon(
                              Icons.close,
                              color: Color(0xFFFFF8ED),
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${submission['studentName'] ?? 'Student'} · '
                              '${task['title'] ?? 'Assignment'}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                color: const Color(0xFF302823),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Scanned Task Preview',
                              style: GoogleFonts.inter(
                                color: const Color(0xFF171411),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              height: 176,
                              width: double.infinity,
                              clipBehavior: Clip.antiAlias,
                              decoration: BoxDecoration(
                                color: const Color(0xFFC7A6A1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFF352722),
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 4,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: scanUrls.isEmpty
                                  ? const Center(
                                      child: Text('No scan preview available'),
                                    )
                                  : PageView.builder(
                                      itemCount: scanUrls.length,
                                      onPageChanged: (page) => setDialogState(
                                        () => currentPage = page,
                                      ),
                                      itemBuilder: (context, index) => GestureDetector(
                                        onTap: () => showFullScreenImageGallery(
                                          context,
                                          scanUrls,
                                          index,
                                        ),
                                        child: Image.network(
                                          scanUrls[index],
                                          fit: BoxFit.contain,
                                          loadingBuilder:
                                              (
                                                context,
                                                child,
                                                progress,
                                              ) => progress == null
                                              ? child
                                              : const Center(
                                                  child:
                                                      CircularProgressIndicator(),
                                                ),
                                          errorBuilder:
                                              (
                                                context,
                                                error,
                                                stack,
                                              ) => const Center(
                                                child: Text(
                                                  'Could not load scan preview.',
                                                ),
                                              ),
                                        ),
                                      ),
                                    ),
                            ),
                            if (scanUrls.length > 1) ...[
                              const SizedBox(height: 5),
                              Center(
                                child: Text(
                                  'Page ${currentPage + 1} of ${scanUrls.length}',
                                  style: const TextStyle(
                                    color: Color(0xFF57483D),
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00B83F),
                                    borderRadius: BorderRadius.circular(6),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black26,
                                        blurRadius: 3,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    submission['aiScore'] is num
                                        ? 'AI suggestion: '
                                              '${(submission['aiScore'] as num).toStringAsFixed(1)} / 100'
                                        : 'Score: Pending',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: () async {
                                    Navigator.pop(dialogContext);
                                    await _showGradeDialog(
                                      studentEmail,
                                      submission,
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: burgundy,
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size(0, 30),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 15,
                                    ),
                                    elevation: 2,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text(
                                    'Edit',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'AI INSIGHTS',
                              style: GoogleFonts.inter(
                                color: const Color(0xFF171411),
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 6),
                            if (submission['aiInsights'] is Iterable &&
                                (submission['aiInsights'] as Iterable)
                                    .whereType<String>()
                                    .isNotEmpty)
                              for (final insight
                                  in (submission['aiInsights'] as Iterable)
                                      .whereType<String>())
                                _buildInsightLine(insight)
                            else ...[
                              _buildInsightLine(
                                submission['aiError'] as String? ??
                                    'AI analysis is not available for this scan.',
                              ),
                              _buildInsightLine(
                                'Review the scanned pages and grade the work using your rubric.',
                              ),
                            ],
                            _buildRubricInterpretation(
                              submission['aiCriterionResults'],
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.save_outlined, size: 16),
                        label: const Text('Save'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: burgundy,
                          foregroundColor: const Color(0xFFF1D9AD),
                          minimumSize: const Size.fromHeight(38),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 3,
                          textStyle: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStudentGradeBadge() {
    if (widget.studentEmail.trim().isEmpty) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.studentSubmissionStream(
        subjectId: widget.subject.id,
        taskId: widget.task.id,
        studentEmail: widget.studentEmail,
      ),
      builder: (context, snapshot) {
        final submission = snapshot.data?.data();
        final score = submission?['score'];
        final maxScore = submission?['maxScore'];
        final isGraded =
            submission?['status'] == 'Graded' ||
            submission?['reviewStatus'] == 'published';
        if (!isGraded || score is! num) return const SizedBox.shrink();

        final gradeText = maxScore is num
            ? '${_formatGradeValue(score)}/${_formatGradeValue(maxScore)}'
            : _formatGradeValue(score);

        return Container(
          margin: const EdgeInsets.only(left: 8),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8ED),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            gradeText,
            style: GoogleFonts.inter(
              color: burgundy,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        );
      },
    );
  }

  String _formatGradeValue(num value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
  }

  List<Map<String, dynamic>> _publishedRubricScores(
    Map<String, dynamic> submission,
  ) {
    final rawScores = submission['aiCriterionScores'];
    final source = rawScores is Iterable && rawScores.isNotEmpty
        ? rawScores
        : submission['aiCriterionResults'] is Iterable
        ? submission['aiCriterionResults'] as Iterable
        : const <dynamic>[];
    return source.whereType<Map>().map(Map<String, dynamic>.from).where((
      result,
    ) {
      final title =
          result['criterion']?.toString().trim() ??
          result['title']?.toString().trim() ??
          '';
      final score =
          result['score'] ?? result['rubricScore'] ?? result['rubric_score'];
      final maximum =
          result['max_score'] ??
          result['rubricMaxScore'] ??
          result['rubric_max_score'];
      return title.isNotEmpty && score is num && maximum is num && maximum > 0;
    }).toList();
  }

  Widget _buildStudentGradeDetails(
    Map<String, dynamic> submission, {
    required bool showRubricBreakdown,
  }) {
    final feedback = (submission['feedback'] as String?)?.trim() ?? '';
    final rubricScores = showRubricBreakdown
        ? _publishedRubricScores(submission)
        : <Map<String, dynamic>>[];
    if (feedback.isEmpty && rubricScores.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppPalette.cream,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE1D5C7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (feedback.isNotEmpty) ...[
            Row(
              children: [
                const Icon(
                  Icons.chat_bubble_outline,
                  size: 17,
                  color: AppPalette.burgundy,
                ),
                const SizedBox(width: 8),
                Text(
                  "Instructor's Feedback",
                  style: GoogleFonts.inter(
                    color: AppPalette.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              feedback,
              style: const TextStyle(
                color: Color(0xFF57483D),
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ],
          if (rubricScores.isNotEmpty) ...[
            if (feedback.isNotEmpty) const SizedBox(height: 16),
            Row(
              children: [
                const Icon(
                  Icons.analytics_outlined,
                  size: 18,
                  color: AppPalette.burgundy,
                ),
                const SizedBox(width: 8),
                Text(
                  'Rubric Point Breakdown',
                  style: GoogleFonts.inter(
                    color: AppPalette.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'AI-assisted points by criterion. The instructor’s published grade above is final.',
              style: TextStyle(
                color: AppPalette.muted,
                fontSize: 11,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),
            for (final result in rubricScores) ...[
              _buildStudentRubricScoreRow(result),
              if (!identical(result, rubricScores.last))
                const SizedBox(height: 10),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildStudentRubricScoreRow(Map<String, dynamic> result) {
    final title =
        result['criterion']?.toString().trim() ??
        result['title']?.toString().trim() ??
        'Criterion';
    final score =
        result['score'] as num? ??
        result['rubricScore'] as num? ??
        result['rubric_score'] as num? ??
        0;
    final maximum =
        result['max_score'] as num? ??
        result['rubricMaxScore'] as num? ??
        result['rubric_max_score'] as num? ??
        0;
    final explanation = (result['explanation'] as String?)?.trim() ?? '';
    final progress = (score / maximum).clamp(0.0, 1.0).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: AppPalette.ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${_formatGradeValue(score)} / ${_formatGradeValue(maximum)} pts',
              style: const TextStyle(
                color: AppPalette.burgundyDark,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: Colors.white,
            color: AppPalette.burgundy,
          ),
        ),
        if (explanation.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            explanation,
            style: const TextStyle(
              color: AppPalette.muted,
              fontSize: 11,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _showReviewDialog(
    String studentEmail,
    Map<String, dynamic> submission,
  ) async {
    final scanUrls = <String>[
      if (submission['scanUrls'] is Iterable)
        for (final url in submission['scanUrls'] as Iterable)
          if (url is String && url.trim().isNotEmpty) url.trim(),
      if (submission['scanUrls'] is! Iterable &&
          submission['scanUrl'] is String &&
          (submission['scanUrl'] as String).trim().isNotEmpty)
        (submission['scanUrl'] as String).trim(),
    ];

    var currentPage = 0;
    final feedback = (submission['feedback'] as String?)?.trim() ?? '';
    final feedbackController = TextEditingController(text: feedback);
    var isSavingFeedback = false;
    var isReturningWork = false;
    var isConfirmingReturn = false;
    var feedbackSaveMessage = '';
    var feedbackSaveSucceeded = false;
    final canReturnWork =
        submission['status'] == 'Submitted' &&
        submission['score'] == null &&
        submission['reviewStatus'] != 'published';
    final insights = (submission['aiInsights'] is Iterable)
        ? (submission['aiInsights'] as Iterable)
              .whereType<String>()
              .where((insight) => insight.trim().isNotEmpty)
              .toList()
        : <String>[];
    final reviewedScore = submission['score'] ?? submission['aiScore'];
    final scoreLabel =
        submission['score'] == null && submission['aiScore'] != null
        ? 'AI score'
        : 'Score';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> saveFeedback() async {
            final updatedFeedback = feedbackController.text.trim();
            if (updatedFeedback.isEmpty) {
              setDialogState(() {
                feedbackSaveMessage = 'Enter feedback before sending.';
                feedbackSaveSucceeded = false;
              });
              return;
            }
            if (isSavingFeedback) return;

            setDialogState(() {
              isSavingFeedback = true;
              feedbackSaveMessage = '';
            });
            try {
              await FirestoreService.updateSubmissionFeedback(
                subjectId: widget.subject.id,
                taskId: widget.task.id,
                studentEmail: studentEmail,
                feedback: updatedFeedback,
              );
              if (!dialogContext.mounted) return;
              setDialogState(() {
                feedbackSaveMessage = 'Feedback saved for the student.';
                feedbackSaveSucceeded = true;
              });
            } on FirebaseException catch (error) {
              if (!dialogContext.mounted) return;
              setDialogState(() {
                feedbackSaveMessage =
                    'Could not save feedback (${error.code}).';
                feedbackSaveSucceeded = false;
              });
            } catch (error, stackTrace) {
              debugPrint('Failed to save review feedback: $error\n$stackTrace');
              if (!dialogContext.mounted) return;
              setDialogState(() {
                feedbackSaveMessage =
                    'Something went wrong while saving feedback.';
                feedbackSaveSucceeded = false;
              });
            } finally {
              if (dialogContext.mounted) {
                setDialogState(() => isSavingFeedback = false);
              }
            }
          }

          Future<void> returnWorkToStudent() async {
            if (isReturningWork) return;
            if (!isConfirmingReturn) {
              setDialogState(() => isConfirmingReturn = true);
              return;
            }

            final scaffoldMessenger = ScaffoldMessenger.of(context);
            setDialogState(() => isReturningWork = true);
            try {
              await FirestoreService.unsubmitSubmissionImageDraft(
                subjectId: widget.subject.id,
                taskId: widget.task.id,
                studentEmail: studentEmail,
              );
              if (!dialogContext.mounted) return;
              Navigator.of(dialogContext).pop();
              scaffoldMessenger.showSnackBar(
                const SnackBar(
                  content: Text('Work returned to the student for editing.'),
                ),
              );
            } catch (error) {
              if (!dialogContext.mounted) return;
              setDialogState(() {
                isReturningWork = false;
                isConfirmingReturn = false;
              });
              if (!scaffoldMessenger.mounted) return;
              scaffoldMessenger.showSnackBar(
                SnackBar(content: Text('Could not return work: $error')),
              );
            }
          }

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 16,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 360,
                maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.94,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 6),
                    child: Text(
                      'Review',
                      style: TextStyle(
                        color: Color(0xFF9B9B9B),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE9D9B9),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: const Color(0xFFB7A991)),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFB7A991)),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Column(
                          children: [
                            Container(
                              height: 36,
                              padding: const EdgeInsets.only(
                                left: 18,
                                right: 8,
                              ),
                              decoration: BoxDecoration(
                                color: burgundy,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'AI Analysis',
                                      style: GoogleFonts.inter(
                                        color: const Color(0xFFFFF8ED),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogContext),
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 26,
                                      minHeight: 26,
                                    ),
                                    icon: const Icon(
                                      Icons.close,
                                      color: Color(0xFFFFF8ED),
                                      size: 17,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  14,
                                  14,
                                  8,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${submission['studentName'] ?? 'Student'} · '
                                      '${task['title'] ?? 'Assignment'}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        color: const Color(0xFF57483D),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      'Scanned Task Preview',
                                      style: GoogleFonts.inter(
                                        color: const Color(0xFF171411),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      height: 168,
                                      width: double.infinity,
                                      clipBehavior: Clip.antiAlias,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFC9A9A4),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: const Color(0xFF352722),
                                        ),
                                        boxShadow: const [
                                          BoxShadow(
                                            color: Colors.black26,
                                            blurRadius: 4,
                                            offset: Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: scanUrls.isEmpty
                                          ? const Center(
                                              child: Text(
                                                'No scan preview available',
                                              ),
                                            )
                                          : PageView.builder(
                                              itemCount: scanUrls.length,
                                              onPageChanged: (page) =>
                                                  setDialogState(
                                                    () => currentPage = page,
                                                  ),
                                              itemBuilder: (context, index) =>
                                                  GestureDetector(
                                                    onTap: () =>
                                                        showFullScreenImageGallery(
                                                          context,
                                                          scanUrls,
                                                          index,
                                                        ),
                                                    child: Image.network(
                                                      scanUrls[index],
                                                      fit: BoxFit.contain,
                                                      loadingBuilder:
                                                          (
                                                            context,
                                                            child,
                                                            progress,
                                                          ) => progress == null
                                                          ? child
                                                          : const Center(
                                                              child:
                                                                  CircularProgressIndicator(),
                                                            ),
                                                      errorBuilder:
                                                          (
                                                            context,
                                                            error,
                                                            stack,
                                                          ) => const Center(
                                                            child: Text(
                                                              'Could not load scan preview.',
                                                            ),
                                                          ),
                                                    ),
                                                  ),
                                            ),
                                    ),
                                    if (scanUrls.length > 1) ...[
                                      const SizedBox(height: 5),
                                      Center(
                                        child: Text(
                                          'Page ${currentPage + 1} of ${scanUrls.length}',
                                          style: const TextStyle(
                                            color: Color(0xFF57483D),
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 11),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 11,
                                              vertical: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF00B83F),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              boxShadow: const [
                                                BoxShadow(
                                                  color: Colors.black26,
                                                  blurRadius: 3,
                                                  offset: Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: Text(
                                              '$scoreLabel: ${reviewedScore ?? '-'} / '
                                              '${submission['maxScore'] ?? 100}',
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 9),
                                        OutlinedButton.icon(
                                          onPressed: () async {
                                            Navigator.pop(dialogContext);
                                            await _showGradeDialog(
                                              studentEmail,
                                              submission,
                                            );
                                          },
                                          icon: const Icon(
                                            Icons.edit_outlined,
                                            size: 13,
                                          ),
                                          label: const Text('Edit'),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: burgundy,
                                            side: const BorderSide(
                                              color: burgundy,
                                            ),
                                            minimumSize: const Size(0, 30),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 11,
                                            ),
                                            tapTargetSize: MaterialTapTargetSize
                                                .shrinkWrap,
                                            textStyle: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 18),
                                    Text(
                                      'AI INSIGHTS',
                                      style: GoogleFonts.inter(
                                        color: const Color(0xFF171411),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    if (insights.isNotEmpty)
                                      for (final insight in insights)
                                        _buildInsightLine(insight)
                                    else ...[
                                      _buildInsightLine(
                                        'AI analysis is not available for this scan yet.',
                                      ),
                                      _buildInsightLine(
                                        'Review the page and enter the grade based on your rubric.',
                                      ),
                                    ],
                                    _buildRubricInterpretation(
                                      submission['aiCriterionResults'],
                                    ),
                                    if (canReturnWork) ...[
                                      const SizedBox(height: 10),
                                      if (isConfirmingReturn)
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFFF8ED),
                                            border: Border.all(
                                              color: const Color(0xFFD7C6A8),
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'Return scanned pages to the '
                                                'student’s drafts? They can '
                                                'remove or replace pages and '
                                                'submit again.',
                                                style: TextStyle(fontSize: 11),
                                              ),
                                              const SizedBox(height: 8),
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.end,
                                                children: [
                                                  TextButton(
                                                    onPressed: isReturningWork
                                                        ? null
                                                        : () => setDialogState(
                                                            () =>
                                                                isConfirmingReturn =
                                                                    false,
                                                          ),
                                                    child: const Text('Cancel'),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  FilledButton.icon(
                                                    onPressed: isReturningWork
                                                        ? null
                                                        : returnWorkToStudent,
                                                    icon: isReturningWork
                                                        ? const SizedBox(
                                                            width: 14,
                                                            height: 14,
                                                            child:
                                                                CircularProgressIndicator(
                                                                  strokeWidth:
                                                                      2,
                                                                ),
                                                          )
                                                        : const Icon(
                                                            Icons.undo,
                                                            size: 15,
                                                          ),
                                                    label: Text(
                                                      isReturningWork
                                                          ? 'Returning...'
                                                          : 'Return work',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        )
                                      else
                                        SizedBox(
                                          width: double.infinity,
                                          child: OutlinedButton.icon(
                                            onPressed: returnWorkToStudent,
                                            icon: const Icon(
                                              Icons.undo,
                                              size: 16,
                                            ),
                                            label: const Text(
                                              'Return to student for edits',
                                            ),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: burgundy,
                                              side: const BorderSide(
                                                color: burgundy,
                                              ),
                                              textStyle: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                    if (submission['answer'] is String &&
                                        submission['scanUrl'] == null) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        'Answer',
                                        style: GoogleFonts.inter(
                                          color: const Color(0xFF171411),
                                          fontWeight: FontWeight.w700,
                                          fontSize: 11,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        submission['answer'] as String,
                                        style: const TextStyle(
                                          color: Color(0xFF57483D),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: feedbackController,
                                    minLines: 1,
                                    maxLines: 2,
                                    textCapitalization:
                                        TextCapitalization.sentences,
                                    textInputAction: TextInputAction.send,
                                    onChanged: (_) {
                                      if (feedbackSaveMessage.isNotEmpty) {
                                        setDialogState(() {
                                          feedbackSaveMessage = '';
                                          feedbackSaveSucceeded = false;
                                        });
                                      }
                                    },
                                    onSubmitted: (_) => saveFeedback(),
                                    decoration: InputDecoration(
                                      hintText: 'Add feedback...',
                                      filled: true,
                                      fillColor: const Color(0xFFFFFCF7),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 13,
                                            vertical: 11,
                                          ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(20),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                  ),
                                ),
                                IconButton.filled(
                                  tooltip: 'Send feedback to student',
                                  icon: isSavingFeedback
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.send),
                                  onPressed: isSavingFeedback
                                      ? null
                                      : saveFeedback,
                                ),
                              ],
                            ),
                            if (feedbackSaveMessage.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  feedbackSaveMessage,
                                  style: TextStyle(
                                    color: feedbackSaveSucceeded
                                        ? const Color(0xFF287344)
                                        : Colors.red.shade700,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    feedbackController.dispose();
  }

  Future<Map<String, dynamic>> _gradeTextSubmissionWithAi(
    String studentEmail,
    Map<String, dynamic> submission,
  ) async {
    final answer = (submission['answer'] as String? ?? '').trim();
    if (submission['aiScore'] is num ||
        answer.isEmpty ||
        submission['scanUrl'] is String ||
        submission['scanUrls'] is Iterable) {
      return submission;
    }

    final progressDialog = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 18),
            Expanded(child: Text('AI is grading this submission...')),
          ],
        ),
      ),
    );

    try {
      final result = await GradingService.gradeText(
        studentText: answer,
        task: task,
      );
      final aiScore = (result['ai_score'] as num?)?.toDouble();
      final aiConfidence = (result['ai_confidence'] as num?)?.toDouble();
      final extractedText = result['extracted_text'] as String? ?? '';
      if (aiScore == null ||
          aiScore < 0 ||
          aiScore > 100 ||
          aiConfidence == null ||
          extractedText.trim().isEmpty) {
        throw const GradingApiException(
          'The grading service did not return a complete result.',
        );
      }

      List<Map<String, dynamic>> mapList(Object? value) => value is List
          ? value.whereType<Map>().map(Map<String, dynamic>.from).toList()
          : <Map<String, dynamic>>[];
      final criterionResults = mapList(result['criterion_results']);
      final criterionScores = mapList(result['criterion_scores']);
      final aiFeedback = result['feedback'] is List
          ? (result['feedback'] as List)
                .whereType<String>()
                .where((item) => item.trim().isNotEmpty)
                .toList()
          : <String>[];
      final textFeatures = result['text_features'] is Map
          ? Map<String, dynamic>.from(result['text_features'] as Map)
          : <String, dynamic>{};
      final matchedStandards = result['matched_curriculum_standards'] is List
          ? (result['matched_curriculum_standards'] as List)
                .map((item) => item.toString())
                .toList()
          : <String>[];
      final missingStandards = result['missing_curriculum_standards'] is List
          ? (result['missing_curriculum_standards'] as List)
                .map((item) => item.toString())
                .toList()
          : <String>[];
      final expectedAnswer = result['expected_answer'] as String? ?? '';
      final aiInsights = <String>[
        'AI suggested score: ${aiScore.toStringAsFixed(1)} / 100.',
        'Model confidence: ${(aiConfidence * 100).round()}%.',
        ...aiFeedback,
      ];
      final visualAnalysis = <String, dynamic>{};
      final gradedSubmission = <String, dynamic>{
        ...submission,
        'aiScore': aiScore,
        'aiConfidence': aiConfidence,
        'extractedText': extractedText,
        'aiInsights': aiInsights,
        'aiExpectedAnswer': expectedAnswer,
        'visualAnalysis': visualAnalysis,
        'aiCriterionResults': criterionResults,
        'aiCriterionScores': criterionScores,
        'aiFeedback': aiFeedback,
        'aiTextFeatures': textFeatures,
        'matchedCurriculumStandards': matchedStandards,
        'missingCurriculumStandards': missingStandards,
      };
      try {
        await FirestoreService.updateSubmissionAiGrading(
          subjectId: widget.subject.id,
          taskId: widget.task.id,
          studentEmail: studentEmail,
          aiScore: aiScore,
          aiConfidence: aiConfidence,
          extractedText: extractedText,
          aiInsights: aiInsights,
          expectedAnswer: expectedAnswer,
          visualAnalysis: visualAnalysis,
          criterionResults: criterionResults,
          criterionScores: criterionScores,
          aiFeedback: aiFeedback,
          textFeatures: textFeatures,
          matchedStandards: matchedStandards,
          missingStandards: missingStandards,
          requiresHumanReview: result['requires_human_review'] as bool? ?? true,
        );
      } on FirebaseException catch (error) {
        debugPrint('Could not save the AI grading result: ${error.code}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'AI graded the work, but its analysis could not be saved '
                '(${error.code}). The suggested score is available for this review.',
              ),
            ),
          );
        }
      }
      return gradedSubmission;
    } on GradingApiException catch (error) {
      debugPrint('AI grading was unavailable: ${error.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'AI grading is unavailable. You can still review the work '
              'manually. ${error.message}',
            ),
          ),
        );
      }
      return submission;
    } catch (error, stackTrace) {
      debugPrint('Could not complete AI grading: $error\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'AI grading could not be completed. You can still review the work manually.',
            ),
          ),
        );
      }
      return submission;
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      await progressDialog;
    }
  }

  Future<void> _showGradeDialog(
    String studentEmail,
    Map<String, dynamic> initialSubmission,
  ) async {
    final submission = await _gradeTextSubmissionWithAi(
      studentEmail,
      initialSubmission,
    );
    if (!mounted) return;
    final score = TextEditingController(
      text:
          submission['score']?.toString() ??
          submission['aiScore']?.toString() ??
          '',
    );
    final max = TextEditingController(
      text: submission['maxScore']?.toString() ?? '100',
    );
    final feedback = TextEditingController(
      text:
          submission['feedback'] as String? ??
          (submission['aiFeedback'] is Iterable
              ? (submission['aiFeedback'] as Iterable).whereType<String>().join(
                  '\n',
                )
              : ''),
    );
    final overrideReason = TextEditingController(
      text: submission['override_reason'] as String? ?? '',
    );
    final scanUrls = <String>[
      if (submission['scanUrls'] is Iterable)
        for (final url in submission['scanUrls'] as Iterable)
          if (url is String && url.trim().isNotEmpty) url.trim(),
      if (submission['scanUrls'] is! Iterable &&
          submission['scanUrl'] is String &&
          (submission['scanUrl'] as String).trim().isNotEmpty)
        (submission['scanUrl'] as String).trim(),
    ];
    final aiInsights = (submission['aiInsights'] is Iterable)
        ? (submission['aiInsights'] as Iterable)
              .whereType<String>()
              .where((insight) => insight.trim().isNotEmpty)
              .toList()
        : <String>[];
    var isEditing = true;
    var currentPage = 0;
    var saveError = '';
    Map<String, dynamic>? savedGrade;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => Dialog(
          backgroundColor: const Color(0xFFE7D7B8),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFB7A991)),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 440,
              maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.88,
            ),
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: burgundy,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.auto_awesome,
                        size: 18,
                        color: Color(0xFFF1D9AD),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          submission['aiScore'] is num
                              ? 'Review AI grade'
                              : 'Grade submission',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 30,
                          minHeight: 30,
                        ),
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${submission['studentName'] ?? 'Student'} · '
                          '${task['title'] ?? 'Assignment'}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            color: const Color(0xFF57483D),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 11),
                        Text(
                          scanUrls.isEmpty
                              ? 'Submitted response'
                              : 'Scanned task preview',
                          style: GoogleFonts.inter(
                            color: const Color(0xFF302823),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          height: 190,
                          width: double.infinity,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: const Color(0xFFD5B8B1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF7C6758)),
                          ),
                          child: scanUrls.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Text(
                                      (submission['answer'] as String? ?? '')
                                              .trim()
                                              .isEmpty
                                          ? 'No response preview available'
                                          : submission['answer'] as String,
                                      maxLines: 8,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFF57483D),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                )
                              : PageView.builder(
                                  itemCount: scanUrls.length,
                                  onPageChanged: (page) =>
                                      setDialogState(() => currentPage = page),
                                  itemBuilder: (context, index) => Image.network(
                                    scanUrls[index],
                                    fit: BoxFit.contain,
                                    loadingBuilder:
                                        (context, child, progress) =>
                                            progress == null
                                            ? child
                                            : const Center(
                                                child:
                                                    CircularProgressIndicator(),
                                              ),
                                    errorBuilder: (context, error, stack) =>
                                        const Center(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.broken_image_outlined,
                                                size: 34,
                                                color: Color(0xFF785E54),
                                              ),
                                              SizedBox(height: 6),
                                              Text(
                                                'Could not load scan preview',
                                              ),
                                            ],
                                          ),
                                        ),
                                  ),
                                ),
                        ),
                        if (scanUrls.length > 1) ...[
                          const SizedBox(height: 5),
                          Center(
                            child: Text(
                              'Page ${currentPage + 1} of ${scanUrls.length}',
                              style: const TextStyle(
                                color: Color(0xFF57483D),
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 9,
                                ),
                                decoration: BoxDecoration(
                                  color: submission['score'] != null
                                      ? const Color(0xFFE7F4E9)
                                      : const Color(0xFFE9E3D8),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  submission['score'] != null
                                      ? 'Score: ${submission['score']} / '
                                            '${submission['maxScore'] ?? 100}'
                                      : submission['aiScore'] != null
                                      ? 'AI suggestion: ${submission['aiScore']} / '
                                            '${submission['maxScore'] ?? 100}'
                                      : 'Score: Pending review',
                                  style: const TextStyle(
                                    color: Color(0xFF2C4530),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton.icon(
                              onPressed: () => setDialogState(() {
                                isEditing = !isEditing;
                                saveError = '';
                              }),
                              icon: Icon(
                                isEditing
                                    ? Icons.visibility_outlined
                                    : Icons.edit_outlined,
                                size: 15,
                              ),
                              label: Text(isEditing ? 'Preview' : 'Edit'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: burgundy,
                                side: const BorderSide(color: burgundy),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 11,
                                  vertical: 9,
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'AI INSIGHTS',
                          style: GoogleFonts.inter(
                            color: const Color(0xFF302823),
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (aiInsights.isNotEmpty)
                          for (final insight in aiInsights)
                            _buildInsightLine(insight)
                        else if (submission['aiScore'] != null) ...[
                          _buildInsightLine(
                            'Suggested score: ${submission['aiScore']} / '
                            '${submission['maxScore'] ?? 100}.',
                          ),
                          if (submission['aiConfidence'] != null)
                            _buildInsightLine(
                              'Model confidence: '
                              '${((submission['aiConfidence'] as num) * 100).round()}%.',
                            ),
                          _buildInsightLine(
                            'Review the work before publishing the grade.',
                          ),
                        ] else ...[
                          _buildInsightLine(
                            scanUrls.isEmpty
                                ? 'AI analysis is not available for this submission yet.'
                                : 'AI analysis is not available for this scan yet.',
                          ),
                          _buildInsightLine(
                            'Review the work and enter the grade based on your rubric.',
                          ),
                        ],
                        _buildRubricInterpretation(
                          submission['aiCriterionResults'],
                        ),
                        if (submission['extractedText'] is String &&
                            (submission['extractedText'] as String)
                                .trim()
                                .isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Extracted text',
                            style: GoogleFonts.inter(
                              color: const Color(0xFF302823),
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            submission['extractedText'] as String,
                            style: const TextStyle(
                              color: Color(0xFF57483D),
                              fontSize: 12,
                            ),
                          ),
                        ],
                        if (isEditing) ...[
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: score,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: InputDecoration(
                                    labelText: submission['aiScore'] is num
                                        ? 'AI score / teacher grade'
                                        : 'Score',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: max,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    labelText: 'Out of',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (submission['aiScore'] is num) ...[
                            const SizedBox(height: 10),
                            TextField(
                              controller: overrideReason,
                              minLines: 1,
                              maxLines: 2,
                              decoration: const InputDecoration(
                                labelText:
                                    'Reason for changing the AI score (optional)',
                                helperText:
                                    'You may add a note explaining your final grade.',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ],
                        ],
                        const SizedBox(height: 14),
                        TextField(
                          controller: feedback,
                          minLines: 1,
                          maxLines: 3,
                          decoration: InputDecoration(
                            hintText: 'Add feedback...',
                            filled: true,
                            fillColor: const Color(0xFFFFFCF7),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 13,
                              vertical: 11,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide.none,
                            ),
                            suffixIcon: const Icon(
                              Icons.send_outlined,
                              size: 17,
                              color: Color(0xFF7B7066),
                            ),
                          ),
                        ),
                        if (saveError.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            saveError,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () async {
                        final scoreValue = double.tryParse(score.text.trim());
                        final maxValue = double.tryParse(max.text.trim());
                        if (scoreValue == null ||
                            maxValue == null ||
                            maxValue <= 0 ||
                            scoreValue < 0 ||
                            scoreValue > maxValue) {
                          setDialogState(() {
                            saveError =
                                'Enter a valid score between 0 and the maximum score.';
                          });
                          return;
                        }
                        final aiScoreValue = (submission['aiScore'] as num?)
                            ?.toDouble();
                        final teacherFinalScore = scoreValue / maxValue * 100;
                        try {
                          await FirestoreService.gradeSubmission(
                            subjectId: widget.subject.id,
                            taskId: widget.task.id,
                            studentEmail: studentEmail,
                            score: scoreValue,
                            maxScore: maxValue,
                            feedback: feedback.text.trim(),
                            aiScore: aiScoreValue,
                            aiConfidence: (submission['aiConfidence'] as num?)
                                ?.toDouble(),
                            overrideReason: overrideReason.text.trim(),
                            aiTrainingExample:
                                submission['extractedText'] is String &&
                                    (submission['extractedText'] as String)
                                        .trim()
                                        .isNotEmpty &&
                                    submission['aiExpectedAnswer'] is String &&
                                    (submission['aiExpectedAnswer'] as String)
                                        .trim()
                                        .isNotEmpty
                                ? {
                                    'student_answer':
                                        (submission['extractedText'] as String)
                                            .trim(),
                                    'expected_answer':
                                        (submission['aiExpectedAnswer']
                                                as String)
                                            .trim(),
                                    'question_id': widget.task.id,
                                    'score': (scoreValue / maxValue * 5).clamp(
                                      0,
                                      5,
                                    ),
                                    'ocr_text':
                                        (submission['extractedText'] as String)
                                            .trim(),
                                    'rubric': task['rubric'],
                                    'ai_score': aiScoreValue,
                                    'teacher_final_score': teacherFinalScore,
                                    'difference': aiScoreValue == null
                                        ? null
                                        : (teacherFinalScore - aiScoreValue)
                                              .abs(),
                                    'ai_criterion_scores':
                                        submission['aiCriterionScores'] ??
                                        const [],
                                    'ai_feedback':
                                        submission['aiFeedback'] ?? const [],
                                    'feedback': feedback.text.trim(),
                                    'override_reason': overrideReason.text
                                        .trim(),
                                    'timestamp': FieldValue.serverTimestamp(),
                                    'teacher_corrected': true,
                                  }
                                : null,
                          );
                          savedGrade = {
                            ...submission,
                            'score': scoreValue,
                            'maxScore': maxValue,
                            'feedback': feedback.text.trim(),
                            'status': 'Graded',
                            'teacher_final_score': teacherFinalScore,
                            'override_reason': overrideReason.text.trim(),
                          };
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                        } on FirebaseException catch (error) {
                          if (!dialogContext.mounted) return;
                          setDialogState(() {
                            saveError =
                                'Could not save the grade (${error.code}). Please try again.';
                          });
                        } catch (error, stackTrace) {
                          debugPrint(
                            'Failed to save grade: $error\n$stackTrace',
                          );
                          if (!dialogContext.mounted) return;
                          setDialogState(() {
                            saveError =
                                'Something went wrong while saving the grade.';
                          });
                        }
                      },
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: const Text('Save grade'),
                      style: FilledButton.styleFrom(
                        backgroundColor: burgundy,
                        foregroundColor: const Color(0xFFFFF8ED),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        textStyle: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
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

    await Future<void>.delayed(const Duration(milliseconds: 300));
    score.dispose();
    max.dispose();
    feedback.dispose();
    overrideReason.dispose();
    if (savedGrade != null && mounted) {
      await _showReviewDialog(studentEmail, savedGrade!);
    }
  }

  Widget _buildRubricInterpretation(dynamic rawResults) {
    final results = rawResults is Iterable
        ? rawResults.whereType<Map>().map(Map<String, dynamic>.from).toList()
        : <Map<String, dynamic>>[];
    if (results.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'RUBRIC INTERPRETATION',
            style: GoogleFonts.inter(
              color: const Color(0xFF302823),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'AI-generated suggestions for instructor review.',
            style: TextStyle(color: Color(0xFF57483D), fontSize: 11),
          ),
          const SizedBox(height: 8),
          for (final result in results) _buildRubricCriterionCard(result),
        ],
      ),
    );
  }

  Widget _buildRubricCriterionCard(Map<String, dynamic> result) {
    final details = <MapEntry<String, String>>[];
    if (result['recommendedScore'] is num) {
      details.add(
        MapEntry(
          'Visual recommendation',
          '${(result['recommendedScore'] as num).toStringAsFixed(1)}% '
              '(level ${result['recommendedLevel'] ?? '-'} / '
              '${result['maxLevel'] ?? '-'})',
        ),
      );
    } else {
      final rubricLevel = result['rubricLevel'];
      details.add(
        MapEntry(
          'Suggested level',
          '${result['selectedLevel'] ?? result['predictedScore'] ?? '-'} / '
              '${result['maxScore'] ?? '-'}'
              '${rubricLevel is String && rubricLevel.trim().isNotEmpty ? ' · $rubricLevel' : ''}',
        ),
      );
    }

    if (result['rubricScore'] is num && result['rubricMaxScore'] is num) {
      details.add(
        MapEntry(
          'Rubric points',
          '${(result['rubricScore'] as num).toStringAsFixed(2)} / '
              '${(result['rubricMaxScore'] as num).toStringAsFixed(2)}',
        ),
      );
    }
    if (result['confidence'] is num) {
      details.add(
        MapEntry(
          'Confidence',
          '${((result['confidence'] as num) * 100).round()}%',
        ),
      );
    }

    final title = result['title']?.toString().trim();
    final evidence = result['evidence'];
    final explanation = result['explanation'];
    final reviewNote = result['reviewNote'];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFF8F7C5F).withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title?.isNotEmpty == true ? title! : 'Rubric criterion',
            style: const TextStyle(
              color: Color(0xFF302823),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Table(
            columnWidths: const {
              0: FixedColumnWidth(104),
              1: FlexColumnWidth(),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.top,
            border: TableBorder(
              horizontalInside: BorderSide(
                color: const Color(0xFF8F7C5F).withValues(alpha: 0.22),
              ),
            ),
            children: [
              for (final detail in details)
                TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Text(
                        detail.key,
                        style: const TextStyle(
                          color: Color(0xFF57483D),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Text(
                        detail.value,
                        style: const TextStyle(
                          color: Color(0xFF57483D),
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (evidence is String && evidence.trim().isNotEmpty)
            _buildRubricParagraph('Answer evidence', evidence),
          if (explanation is String && explanation.trim().isNotEmpty)
            _buildRubricParagraph('Interpretation', explanation),
          if (reviewNote is String && reviewNote.trim().isNotEmpty)
            _buildRubricParagraph(
              'Review note',
              reviewNote,
              color: const Color(0xFF7A2027),
            ),
        ],
      ),
    );
  }

  Widget _buildRubricParagraph(
    String label,
    String text, {
    Color color = const Color(0xFF57483D),
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            text.trim(),
            style: TextStyle(color: color, fontSize: 11, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightLine(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 5),
            child: Icon(Icons.circle, size: 6, color: Color(0xFF6D5548)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF57483D),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentAction() {
    final canSubmit = allowsUpload && !submissionsClosed;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.studentSubmissionStream(
        subjectId: widget.subject.id,
        taskId: widget.task.id,
        studentEmail: widget.studentEmail,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text('Could not load your submitted photos.'),
              const SizedBox(height: 8),
              Center(
                child: FilledButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: Text(
                    !allowsUpload
                        ? 'Submit hardcopy to instructor'
                        : submissionsClosed
                        ? 'Submissions closed'
                        : 'Upload photos',
                  ),
                ),
              ),
            ],
          );
        }

        final submission = snapshot.data?.data() ?? const <String, dynamic>{};
        final imageUrls = submissionImageUrls(submission);
        final draftImageUrls = submissionImageDraftUrls(submission);
        final isSubmitted =
            submission['status'] == 'Submitted' ||
            submission['status'] == 'Graded';
        final isGraded =
            submission['status'] == 'Graded' ||
            submission['score'] != null ||
            submission['reviewStatus'] == 'published';
        final canSubmitWork = canSubmit && !isSubmitted && snapshot.hasData;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (imageUrls.isNotEmpty)
              buildSubmittedImageGallery(
                context,
                imageUrls,
                onRemove: isSubmitted
                    ? null
                    : (imageUrl) => FirestoreService.removeSubmittedImage(
                        subjectId: widget.subject.id,
                        taskId: widget.task.id,
                        studentEmail: widget.studentEmail,
                        imageUrl: imageUrl,
                      ),
              ),
            if (draftImageUrls.isNotEmpty) ...[
              buildSubmittedImageGallery(
                context,
                draftImageUrls,
                title: 'Uploaded photos',
                onRemove: (imageUrl) =>
                    FirestoreService.removeSubmissionImageDraft(
                      subjectId: widget.subject.id,
                      taskId: widget.task.id,
                      studentEmail: widget.studentEmail,
                      imageUrl: imageUrl,
                    ),
              ),
              Center(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 12,
                    ),
                  ),
                  onPressed: canSubmitWork
                      ? () => _submitSavedImages(draftImageUrls.length)
                      : null,
                  icon: const Icon(Icons.send_outlined),
                  label: const Text('Submit'),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (submission['status'] == 'Submitted' &&
                !isGraded &&
                submission['reviewStatus'] != 'published') ...[
              const SizedBox(height: 8),
              Center(
                child: FilledButton.icon(
                  onPressed: _unsubmitWork,
                  icon: const Icon(Icons.undo, size: 18),
                  label: const Text('Unsubmit work'),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Center(
              child: FilledButton.icon(
                onPressed: canSubmitWork ? _showStudentSubmission : null,
                icon: const Icon(Icons.add_a_photo_outlined),
                label: Text(
                  isSubmitted
                      ? 'Work submitted'
                      : !allowsUpload
                      ? 'Submit hardcopy to instructor'
                      : submissionsClosed
                      ? 'Submissions closed'
                      : 'Upload photos',
                ),
              ),
            ),
            if ((submission['feedback'] as String?)?.trim().isNotEmpty ==
                    true ||
                (isGraded && submission['reviewStatus'] == 'published'))
              _buildStudentGradeDetails(
                submission,
                showRubricBreakdown:
                    isGraded && submission['reviewStatus'] == 'published',
              ),
          ],
        );
      },
    );
  }

  Future<void> _submitSavedImages(int imageCount) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Submit photos?'),
        content: Text(
          'You are about to submit $imageCount photo(s). Review the saved photos before continuing.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Go back'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    try {
      await FirestoreService.submitSubmissionImageDraft(
        subjectId: widget.subject.id,
        taskId: widget.task.id,
        studentEmail: widget.studentEmail,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photos submitted to your teacher')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not submit photos: $error')),
      );
    }
  }

  Future<void> _unsubmitWork() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Unsubmit this work?'),
        content: const Text(
          'Your submitted photos will return to drafts. You can edit them and submit again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep submitted'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Unsubmit'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    try {
      await FirestoreService.unsubmitSubmissionImageDraft(
        subjectId: widget.subject.id,
        taskId: widget.task.id,
        studentEmail: widget.studentEmail,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Work returned to drafts')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not unsubmit work: $error')),
      );
    }
  }

  Future<void> _showStudentSubmission() async {
    if (submissionsClosed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Submissions are closed for this task.')),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: const Color(0xFF292929),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStudentImageSourceChoice(
                context: sheetContext,
                icon: Icons.camera_alt_outlined,
                label: 'Camera',
                source: ImageSource.camera,
              ),
              _buildStudentImageSourceChoice(
                context: sheetContext,
                icon: Icons.image_outlined,
                label: 'Gallery',
                source: ImageSource.gallery,
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || source == null) return;

    final List<XFile> images;
    if (source == ImageSource.camera) {
      final image = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
      );
      images = image == null ? const <XFile>[] : [image];
    } else {
      images = await ImagePicker().pickMultiImage(imageQuality: 90);
    }
    if (!mounted || images.isEmpty) return;

    try {
      final reviewedImages = await showSubmissionImageReview(context, images);
      if (!mounted || reviewedImages == null) return;

      messenger.showSnackBar(
        SnackBar(
          content: Text('Uploading ${reviewedImages.length} photo(s)...'),
        ),
      );
      final urls = <String>[];
      for (var index = 0; index < reviewedImages.length; index++) {
        final image = reviewedImages[index];
        final isPng = image.file.name.toLowerCase().endsWith('.png');
        final fileName =
            'submission_${widget.subject.id}_${widget.task.id}_'
            '${DateTime.now().millisecondsSinceEpoch}_$index.'
            '${isPng ? 'png' : 'jpg'}';
        final url = kIsWeb || isPng
            ? await CloudinaryService.uploadBytes(
                bytes: image.bytes,
                fileName: fileName,
                resourceType: 'image',
              )
            : await CloudinaryService.uploadFile(
                path: image.file.path,
                fileName: fileName,
                resourceType: 'image',
              );
        urls.add(url);
      }

      await FirestoreService.saveSubmissionImageDraft(
        subjectId: widget.subject.id,
        taskId: widget.task.id,
        studentEmail: widget.studentEmail,
        studentName: widget.studentName,
        imageUrls: urls,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Photos saved. Review them before submitting.'),
        ),
      );
    } on CloudinaryUploadException catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Photo upload failed: ${error.message}')),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not submit photos: $error')),
      );
    }
  }

  Widget _buildStudentImageSourceChoice({
    required BuildContext context,
    required IconData icon,
    required String label,
    required ImageSource source,
  }) {
    return InkWell(
      onTap: () => Navigator.of(context).pop(source),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 30),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}
