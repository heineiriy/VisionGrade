import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'app_theme.dart';
import 'camera_scanner.dart';
import 'cloudinary_service.dart';
import 'home_screen.dart';
import 'firestore_service.dart';
import 'post_date_formatter.dart';
import 'task_due_date.dart';
import 'task_details_screen.dart';
import 'submission_image_review.dart';
import 'task_pdf_viewer.dart';

class StudentClassworkScreen extends StatefulWidget {
  final Subject subject;
  final String studentName;
  final String studentEmail;
  final String? profileImageUrl;

  const StudentClassworkScreen({
    super.key,
    required this.subject,
    required this.studentName,
    required this.studentEmail,
    this.profileImageUrl,
  });

  @override
  State<StudentClassworkScreen> createState() => _StudentClassworkScreenState();
}

class _StudentClassworkScreenState extends State<StudentClassworkScreen> {
  String selectedFilter = 'All';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.subjectPostsStream(widget.subject.id),
      builder: (context, snapshot) {
        final works = (snapshot.data?.docs ?? const [])
            .where((doc) {
              final data = doc.data();
              if (data['type'] != 'Task') return false;
              return isTaskVisibleToStudent(data, widget.studentEmail);
            })
            .map(
              (doc) => <String, dynamic>{
                'id': doc.id,
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
                'closeAfterDeadline':
                    doc.data()['closeAfterDeadline'] as bool? ?? true,
                'score': null,
                'maxScore': null,
                'feedback': null,
                'aiInsights': const <String>[],
                'reviewStatus': 'pending_review',
              },
            )
            .toList();
        works.sort(
          (first, second) =>
              compareTaskDueDates(first['dueDate'], second['dueDate']),
        );
        final filtered = works.where((work) {
          if (selectedFilter == 'All') {
            return true;
          }
          if (selectedFilter == 'Due Date') {
            return work['status'] != 'Closed' &&
                isTaskDueWithinDays(work['dueDate']);
          }
          if (selectedFilter == 'Missing') {
            return work['status'] == 'Missing' || _isPastDeadline(work);
          }
          final statusFilter = selectedFilter;
          return (work['status'] as String).toLowerCase().contains(
            statusFilter.toLowerCase(),
          );
        }).toList();

        return RefreshIndicator(
          onRefresh: () => FirestoreService.refreshSubjectContent(
            subjectId: widget.subject.id,
            role: 'student',
            email: widget.studentEmail,
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
                  _buildEmptyState(works.isEmpty)
                else
                  ...filtered.map((work) {
                    if (widget.studentEmail.trim().isEmpty) {
                      final studentWork = {
                        ...work,
                        'status': _studentStatus(work, hasSubmission: false),
                        'isSubmissionClosed': work['status'] == 'Closed',
                      };
                      return _matchesSelectedFilter(studentWork)
                          ? _buildClassworkCard(studentWork)
                          : const SizedBox.shrink();
                    }
                    return StreamBuilder<
                      DocumentSnapshot<Map<String, dynamic>>
                    >(
                      stream: FirestoreService.studentSubmissionStream(
                        subjectId: widget.subject.id,
                        taskId: work['id'] as String,
                        studentEmail: widget.studentEmail,
                      ),
                      builder: (context, submissionSnapshot) {
                        if (submissionSnapshot.hasError) {
                          return _buildClassworkCard({
                            ...work,
                            'submissionError': submissionSnapshot.error,
                            'isSubmissionClosed': work['status'] == 'Closed',
                          });
                        }
                        final submission =
                            submissionSnapshot.data?.data() ??
                            const <String, dynamic>{};
                        final hasSubmission =
                            submission['status'] == 'Submitted' ||
                            submission['status'] == 'Graded';
                        final isPublished =
                            submission['reviewStatus'] == 'published';
                        final isGraded =
                            submission['status'] == 'Graded' ||
                            submission['score'] != null ||
                            isPublished;
                        final studentWork = {
                          ...work,
                          'status': _studentStatus(
                            work,
                            hasSubmission: hasSubmission,
                          ),
                          'isSubmissionClosed': work['status'] == 'Closed',
                          'submissionStatus': submission['status'],
                          'isGraded': isGraded,
                          'submissionImages': submissionImageUrls(submission),
                          'draftSubmissionImages': submissionImageDraftUrls(
                            submission,
                          ),
                          'reviewStatus': submission['reviewStatus'],
                          'score': isPublished ? submission['score'] : null,
                          'maxScore': isPublished
                              ? submission['maxScore']
                              : null,
                          'feedback': submission['feedback'],
                          'aiInsights': isPublished
                              ? submission['aiInsights']
                              : const <String>[],
                        };
                        if (!_matchesSelectedFilter(studentWork)) {
                          return const SizedBox.shrink();
                        }
                        return _buildClassworkCard(studentWork);
                      },
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _isPastDeadline(Map<String, dynamic> work) {
    final dueDate = taskDueDate(work['dueDate']);
    return dueDate != null && !isTaskDeadlineValid(dueDate);
  }

  String _studentStatus(
    Map<String, dynamic> work, {
    required bool hasSubmission,
  }) {
    if (!hasSubmission &&
        (work['status'] == 'Closed' || _isPastDeadline(work))) {
      return 'Missing';
    }
    return work['status'] as String? ?? 'Active';
  }

  bool _matchesSelectedFilter(Map<String, dynamic> work) {
    if (selectedFilter == 'All') return true;
    if (selectedFilter == 'Due Date') {
      return work['status'] != 'Closed' && isTaskDueWithinDays(work['dueDate']);
    }
    return work['status'] == selectedFilter;
  }

  Widget _buildEmptyState(bool hasNoAssignments) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF8F5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFECE5DC)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.assignment_outlined,
            color: AppPalette.burgundy,
            size: 32,
          ),
          const SizedBox(height: 12),
          Text(
            hasNoAssignments
                ? 'No classwork yet'
                : 'No assignments in this view',
            style: const TextStyle(
              color: AppPalette.ink,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hasNoAssignments
                ? 'Your instructor’s assignments will appear here.'
                : 'Try choosing a different filter.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppPalette.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    final filters = ['All', 'Due Date', 'Missing', 'Closed'];
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

  Widget _buildClassworkCard(Map<String, dynamic> w) {
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TaskDetailsScreen(
            subject: widget.subject,
            role: UserRole.student,
            task: w['task'] as QueryDocumentSnapshot<Map<String, dynamic>>,
            studentName: widget.studentName,
            studentEmail: widget.studentEmail,
            profileImageUrl: widget.profileImageUrl,
          ),
        ),
      ),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFFFBF8F3),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE9E0D6)),
          boxShadow: [
            BoxShadow(
              color: AppPalette.burgundyDark.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 5),
            ),
          ],
        ),
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
                    color: const Color(0xFFF0E6E0),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.assignment_outlined,
                    color: AppPalette.burgundy,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      w['title'] as String? ?? 'Untitled assignment',
                      style: const TextStyle(
                        color: AppPalette.ink,
                        fontSize: 16,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _buildStatusBadge(w['status'] as String? ?? 'Open'),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.calendar_today_outlined,
                    size: 15,
                    color: AppPalette.burgundy,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Due ${w['due']}',
                      style: const TextStyle(
                        color: AppPalette.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  _buildSubmissionBadge(w),
                ],
              ),
            ),
            if ((w['body'] as String? ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                w['body'] as String,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF5F5753),
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ],
            if (w['attachmentUrl'] is String) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: AppPalette.burgundy,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: () => openTaskAttachment(
                    context,
                    url: w['attachmentUrl'] as String,
                    name: w['attachmentName'] as String? ?? 'Task instructions',
                  ),
                  icon: const Icon(Icons.attach_file, size: 17),
                  label: Text(
                    w['attachmentName'] as String? ?? 'Task instructions',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  w['score'] == null
                      ? Icons.hourglass_empty_rounded
                      : Icons.grade_outlined,
                  size: 17,
                  color: AppPalette.muted,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    w['score'] == null
                        ? w['submissionStatus'] == 'Submitted'
                              ? 'Submitted · awaiting review'
                              : w['draftSubmissionImages'] is List &&
                                    (w['draftSubmissionImages'] as List)
                                        .isNotEmpty
                              ? 'Photos saved · not submitted'
                              : 'Not graded yet'
                        : 'Score: ${_formatScore(w['score'])}/${_formatScore(w['maxScore'])}',
                    style: const TextStyle(
                      color: AppPalette.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (w['submissionImages'] is List &&
                (w['submissionImages'] as List).isNotEmpty) ...[
              const SizedBox(height: 12),
              buildSubmittedImageGallery(
                context,
                (w['submissionImages'] as List).whereType<String>().toList(),
                onRemove:
                    w['submissionStatus'] == 'Submitted' ||
                        w['submissionStatus'] == 'Graded'
                    ? null
                    : (imageUrl) => FirestoreService.removeSubmittedImage(
                        subjectId: widget.subject.id,
                        taskId: w['id'] as String,
                        studentEmail: widget.studentEmail,
                        imageUrl: imageUrl,
                      ),
              ),
            ],
            if (w['draftSubmissionImages'] is List &&
                (w['draftSubmissionImages'] as List).isNotEmpty) ...[
              const SizedBox(height: 12),
              buildSubmittedImageGallery(
                context,
                (w['draftSubmissionImages'] as List)
                    .whereType<String>()
                    .toList(),
                title: 'Uploaded photos',
                onRemove: (imageUrl) =>
                    FirestoreService.removeSubmissionImageDraft(
                      subjectId: widget.subject.id,
                      taskId: w['id'] as String,
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
                  onPressed:
                      w['isSubmissionClosed'] == true ||
                          w['status'] == 'Closed' ||
                          w['submissionStatus'] == 'Submitted' ||
                          w['submissionStatus'] == 'Graded'
                      ? null
                      : () => _submitSavedImages(
                          w['id'] as String,
                          (w['draftSubmissionImages'] as List).length,
                        ),
                  icon: const Icon(Icons.send_outlined),
                  label: const Text('Submit'),
                ),
              ),
            ],
            if (w['reviewStatus'] == 'published' &&
                w['aiInsights'] is Iterable &&
                (w['aiInsights'] as Iterable)
                    .whereType<String>()
                    .isNotEmpty) ...[
              const SizedBox(height: 10),
              _buildFeedbackSection(
                title: 'Assessment suggestions',
                content: (w['aiInsights'] as Iterable)
                    .whereType<String>()
                    .where((insight) => insight.trim().isNotEmpty)
                    .join('\n'),
                icon: Icons.lightbulb_outline,
              ),
            ],
            if (w['feedback'] is String &&
                (w['feedback'] as String).trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildFeedbackSection(
                title: "Instructor's Feedbacks",
                content: w['feedback'] as String,
                icon: Icons.chat_bubble_outline,
              ),
            ],
            if (w['submissionError'] != null) ...[
              const SizedBox(height: 10),
              Text(
                'Could not load your submission: ${w['submissionError']}',
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ],
            const SizedBox(height: 14),
            if (w['submissionStatus'] == 'Submitted' &&
                w['isGraded'] != true &&
                w['reviewStatus'] != 'published') ...[
              Center(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppPalette.burgundy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => _unsubmitWork(w['id'] as String),
                  icon: const Icon(Icons.undo, size: 18),
                  label: const Text('Unsubmit work'),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (w['isSubmissionClosed'] != true && w['status'] != 'Closed')
              if (w['allowUpload'] == true)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppPalette.burgundy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed:
                        w['submissionError'] != null ||
                            w['submissionStatus'] == 'Submitted' ||
                            w['submissionStatus'] == 'Graded'
                        ? null
                        : () => _chooseSubmissionImages(w),
                    icon: const Icon(Icons.upload_file_outlined, size: 19),
                    label: Text(
                      w['submissionStatus'] == 'Submitted' ||
                              w['submissionStatus'] == 'Graded'
                          ? 'Work submitted'
                          : 'Upload photos',
                    ),
                  ),
                )
              else
                _buildSubmissionNotice(
                  icon: Icons.description_outlined,
                  text: 'Hand in your paper for scanning.',
                  color: AppPalette.muted,
                ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.person_outline,
                  size: 15,
                  color: AppPalette.muted,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'Posted by ${w['posterName']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppPalette.muted,
                      fontSize: 11,
                    ),
                  ),
                ),
                Text(
                  formatPostedDate(w['postedAt']),
                  style: const TextStyle(color: AppPalette.muted, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    final isClosed = status == 'Closed';
    final isMissing = status == 'Missing';
    final color = isClosed || isMissing
        ? const Color(0xFFF8E6E5)
        : const Color(0xFFE6F2E9);
    final foreground = isClosed || isMissing
        ? const Color(0xFF9B3D42)
        : const Color(0xFF34764B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildSubmissionBadge(Map<String, dynamic> work) {
    final submitted = work['submissionStatus'] == 'Submitted';
    final color = submitted ? const Color(0xFFE6F2E9) : const Color(0xFFF1ECE7);
    final foreground = submitted ? const Color(0xFF34764B) : AppPalette.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        submitted ? 'Submitted' : 'Not submitted',
        style: TextStyle(
          color: foreground,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildFeedbackSection({
    required String title,
    required String content,
    required IconData icon,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppPalette.burgundy),
              const SizedBox(width: 7),
              Text(
                title,
                style: const TextStyle(
                  color: AppPalette.ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            content,
            style: const TextStyle(
              color: Color(0xFF5F5753),
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmissionNotice({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _chooseSubmissionImages(Map<String, dynamic> work) async {
    if (work['status'] == 'Closed') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This assignment is closed. Submissions are no longer accepted.',
            ),
          ),
        );
      }
      return;
    }
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: const Color(0xFF292929),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _submissionChoice(
                context: sheetContext,
                icon: Icons.camera_alt_outlined,
                label: 'Camera',
                value: ImageSource.camera,
              ),
              _submissionChoice(
                context: sheetContext,
                icon: Icons.image_outlined,
                label: 'Upload photo',
                value: ImageSource.gallery,
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || source == null) return;

    List<XFile>? images;
    if (source == ImageSource.camera) {
      images = await HardcopyScanner.capture(context);
    } else {
      images = await ImagePicker().pickMultiImage(imageQuality: 90);
    }
    if (!mounted || images == null || images.isEmpty) return;
    final selectedImages = images;
    final dueDate = taskDueDate(work['dueDate']);
    final closeAfterDeadline = work['closeAfterDeadline'] as bool? ?? true;
    if (closeAfterDeadline &&
        dueDate != null &&
        !dueDate.isAfter(DateTime.now())) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This assignment is closed. Submissions are no longer accepted.',
            ),
          ),
        );
      }
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    try {
      final reviewedImages = await showSubmissionImageReview(
        context,
        selectedImages,
      );
      if (!mounted || reviewedImages == null) return;

      messenger.showSnackBar(
        SnackBar(
          content: Text('Uploading ${reviewedImages.length} image(s)...'),
        ),
      );
      final urls = <String>[];
      for (var index = 0; index < reviewedImages.length; index++) {
        urls.add(
          await CloudinaryService.uploadBytes(
            bytes: reviewedImages[index].bytes,
            fileName:
                'submission_${widget.subject.id}_${work['id']}_${DateTime.now().millisecondsSinceEpoch}_$index.jpg',
            resourceType: 'image',
          ),
        );
      }
      await FirestoreService.saveSubmissionImageDraft(
        subjectId: widget.subject.id,
        taskId: work['id'] as String,
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
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Upload failed: ${error.message}')),
        );
      }
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Submission failed: $error')),
        );
      }
    }
  }

  Future<void> _submitSavedImages(String taskId, int imageCount) async {
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
        taskId: taskId,
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

  Future<void> _unsubmitWork(String taskId) async {
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
        taskId: taskId,
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

  Widget _submissionChoice({
    required BuildContext context,
    required IconData icon,
    required String label,
    required ImageSource value,
  }) {
    return InkWell(
      onTap: () => Navigator.of(context).pop(value),
      borderRadius: BorderRadius.circular(48),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white38),
              ),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }

  String _formatScore(Object? value) {
    if (value is! num) return '-';
    return value % 1 == 0 ? value.toInt().toString() : value.toString();
  }
}
