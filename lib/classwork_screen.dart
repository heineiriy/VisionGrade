import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'app_theme.dart';
import 'home_screen.dart';
import 'firestore_service.dart';
import 'post_date_formatter.dart';
import 'task_due_date.dart';
import 'task_details_screen.dart';
import 'task_pdf_viewer.dart';

class ClassworksScreen extends StatefulWidget {
  final Subject subject;
  final UserRole role;
  final String studentName;
  final String studentEmail;
  final String? profileImageUrl;

  const ClassworksScreen({
    super.key,
    required this.subject,
    this.role = UserRole.instructor,
    this.studentName = '',
    this.studentEmail = '',
    this.profileImageUrl,
  });

  @override
  State<ClassworksScreen> createState() => _ClassworksScreenState();
}

class _ClassworksScreenState extends State<ClassworksScreen> {
  String selectedFilter = 'All';

  bool get _isInstructor => widget.role == UserRole.instructor;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.subjectPostsStream(widget.subject.id),
      builder: (context, snapshot) {
        final postedWorks = (snapshot.data?.docs ?? const [])
            .where((doc) => doc.data()['type'] == 'Task')
            .map(
              (doc) => <String, dynamic>{
                'task': doc,
                'title': doc.data()['title'] as String? ?? 'Untitled task',
                'body': doc.data()['body'] as String? ?? '',
                'attachmentName': doc.data()['attachmentName'] as String?,
                'attachmentUrl': doc.data()['attachmentUrl'] as String?,
                'posterName':
                    doc.data()['posterName'] as String? ?? 'Instructor',
                'postedAt': doc.data()['postedAt'],
                'dueDate': doc.data()['dueDate'] ?? doc.data()['due'],
                'due': formatTaskDueDate(
                  doc.data()['dueDate'] ?? doc.data()['due'],
                ),
                'status': taskDueStatus(
                  doc.data()['dueDate'] ?? doc.data()['due'],
                  closeAfterDeadline:
                      doc.data()['closeAfterDeadline'] as bool? ?? true,
                ),
                'allowUpload': doc.data()['allowUpload'] as bool? ?? false,
              },
            );
        final works = postedWorks.toList()
          ..sort(
            (first, second) =>
                compareTaskDueDates(first['dueDate'], second['dueDate']),
          );
        final filtered = works.where((work) {
          if (selectedFilter == 'All') return true;
          if (_isInstructor) {
            return switch (selectedFilter) {
              'Allows uploads' => work['allowUpload'] == true,
              'No uploads' => work['allowUpload'] != true,
              'Closed' => work['status'] == 'Closed',
              _ => true,
            };
          }
          if (selectedFilter == 'Due Date') {
            return work['status'] != 'Closed' &&
                isTaskDueWithinDays(work['dueDate']);
          }
          final statusFilter = selectedFilter;
          return (work['status'] as String).toLowerCase().contains(
            statusFilter.toLowerCase(),
          );
        }).toList();

        return RefreshIndicator(
          onRefresh: () => FirestoreService.refreshSubjectContent(
            subjectId: widget.subject.id,
            role: _isInstructor ? 'instructor' : 'student',
            email: _isInstructor
                ? FirebaseAuth.instance.currentUser?.email ?? ''
                : widget.studentEmail,
            authUid: FirebaseAuth.instance.currentUser?.uid ?? '',
          ),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _buildFilterChips(),
                const SizedBox(height: 8),
                if (filtered.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 48),
                    child: Text('No tasks have been posted yet.'),
                  )
                else
                  Column(
                    children: filtered.map(_buildFilteredClasswork).toList(),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilterChips() {
    final filters = _isInstructor
        ? ['All', 'Allows uploads', 'No uploads', 'Closed']
        : ['All', 'Due Date', 'Missing', 'Closed'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((f) {
          final selected = f == selectedFilter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(f),
              selected: selected,
              onSelected: (_) => setState(() => selectedFilter = f),
              selectedColor: AppPalette.burgundy,
              backgroundColor: AppPalette.cream,
              labelStyle: TextStyle(
                color: selected ? Colors.white : AppPalette.ink,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildFilteredClasswork(Map<String, dynamic> work) {
    if (!_isInstructor) return _buildClassworkCard(work);

    final task = work['task'] as QueryDocumentSnapshot<Map<String, dynamic>>;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.submissionsStream(
        subjectId: widget.subject.id,
        taskId: task.id,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Could not load submissions for "${work['title']}": '
              '${snapshot.error}',
              style: const TextStyle(color: Colors.redAccent),
            ),
          );
        }

        if (!snapshot.hasData) {
          return _buildClassworkCard({...work, 'isLoadingSubmissions': true});
        }

        final submissions = snapshot.data!.docs.where((submission) {
          final status = submission.data()['status'];
          return status == 'Submitted' || status == 'Graded';
        }).toList();
        final reviewedCount = submissions.where(_isReviewed).length;
        return _buildClassworkCard({
          ...work,
          'submissionCount': submissions.length,
          'reviewedCount': reviewedCount,
          'pendingReviewCount': submissions.length - reviewedCount,
        });
      },
    );
  }

  bool _isReviewed(QueryDocumentSnapshot<Map<String, dynamic>> submission) {
    final data = submission.data();
    return data['reviewStatus'] == 'published' ||
        data['status'] == 'Graded' ||
        data['score'] != null;
  }

  Widget _buildClassworkCard(Map<String, dynamic> w) {
    if (_isInstructor) {
      return _buildInstructorClassworkCard(w);
    }

    return GestureDetector(
      onTap: () => _openTask(w),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppPalette.cream,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6),
          ],
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    w['title'],
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: w['status'] == 'Closed'
                        ? Colors.redAccent
                        : Colors.grey.shade700,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    w['status'],
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Due: ${w['due']}',
              style: const TextStyle(color: Colors.black54),
            ),
            if (w['attachmentUrl'] is String) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => openTaskAttachment(
                    context,
                    url: w['attachmentUrl'] as String,
                    name: w['attachmentName'] as String? ?? 'Task instructions',
                  ),
                  icon: const Icon(Icons.attach_file, size: 16),
                  label: Text(
                    w['attachmentName'] as String? ?? 'Task instructions',
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Posted by ${w['posterName']}',
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 4),
            Text(
              formatPostedDate(w['postedAt']),
              style: const TextStyle(color: Colors.black54, fontSize: 11),
            ),
            const SizedBox(height: 10),
            if (w['status'] == 'Closed')
              const Text(
                'This assignment is closed. Submissions are no longer accepted.',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            const Row(
              children: [
                Expanded(
                  child: Text(
                    'Tap to view task and student submissions',
                    style: TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.black54),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructorClassworkCard(Map<String, dynamic> work) {
    final isClosed = work['status'] == 'Closed';
    final hasSubmissionData = work['submissionCount'] is int;
    final submissionCount = work['submissionCount'] as int? ?? 0;
    final pendingReviewCount = work['pendingReviewCount'] as int? ?? 0;
    final reviewedCount = work['reviewedCount'] as int? ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE9E2DC)),
        boxShadow: [
          BoxShadow(
            color: AppPalette.burgundyDark.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openTask(work),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7ECEC),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.assignment_outlined,
                        color: AppPalette.burgundy,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          work['title'] as String? ?? 'Untitled task',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppPalette.ink,
                            fontSize: 15,
                            height: 1.25,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildInstructorStatusBadge(
                      isClosed ? 'Closed' : 'Open',
                      isClosed: isClosed,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 14,
                  runSpacing: 8,
                  children: [
                    _buildInstructorDetail(
                      icon: Icons.calendar_today_outlined,
                      text: 'Due ${work['due']}',
                    ),
                    _buildInstructorDetail(
                      icon: work['allowUpload'] == true
                          ? Icons.upload_file_outlined
                          : Icons.block_outlined,
                      text: work['allowUpload'] == true
                          ? 'Uploads allowed'
                          : 'No uploads',
                    ),
                  ],
                ),
                if (work['attachmentUrl'] is String) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => openTaskAttachment(
                      context,
                      url: work['attachmentUrl'] as String,
                      name:
                          work['attachmentName'] as String? ??
                          'Task instructions',
                    ),
                    icon: const Icon(Icons.attach_file, size: 17),
                    label: Flexible(
                      child: Text(
                        work['attachmentName'] as String? ??
                            'Task instructions',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppPalette.burgundy,
                      side: const BorderSide(color: Color(0xFFE9D9D9)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAF8F5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: work['isLoadingSubmissions'] == true
                      ? const Row(
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 9),
                            Text(
                              'Loading submissions...',
                              style: TextStyle(
                                color: AppPalette.muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        )
                      : hasSubmissionData && submissionCount == 0
                      ? const Text(
                          'No student submissions yet',
                          style: TextStyle(
                            color: AppPalette.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      : Row(
                          children: [
                            _buildSubmissionMetric(
                              '$submissionCount',
                              'Submitted',
                              flex: 1,
                            ),
                            _buildSubmissionMetric(
                              '$pendingReviewCount',
                              'To review',
                              flex: 1,
                            ),
                            _buildSubmissionMetric(
                              '$reviewedCount',
                              'Reviewed',
                              flex: 1,
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Posted ${formatPostedDate(work['postedAt'])}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppPalette.muted,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'View submissions',
                      style: TextStyle(
                        color: AppPalette.burgundy,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: AppPalette.burgundy,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInstructorStatusBadge(String label, {required bool isClosed}) {
    final foreground = isClosed
        ? const Color(0xFF9B353D)
        : const Color(0xFF39734A);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: isClosed ? const Color(0xFFFCEDEE) : const Color(0xFFEAF5ED),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildInstructorDetail({
    required IconData icon,
    required String text,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: AppPalette.muted),
        const SizedBox(width: 5),
        Text(
          text,
          style: const TextStyle(color: AppPalette.muted, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildSubmissionMetric(
    String value,
    String label, {
    required int flex,
  }) {
    return Expanded(
      flex: flex,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: AppPalette.ink,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppPalette.muted, fontSize: 10),
          ),
        ],
      ),
    );
  }

  void _openTask(Map<String, dynamic> work) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TaskDetailsScreen(
          subject: widget.subject,
          role: widget.role,
          task: work['task'] as QueryDocumentSnapshot<Map<String, dynamic>>,
          studentName: widget.studentName,
          studentEmail: widget.studentEmail,
          profileImageUrl: widget.profileImageUrl,
        ),
      ),
    );
  }
}
