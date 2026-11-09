import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'firestore_service.dart';
import 'home_screen.dart';
import 'post_date_formatter.dart';

class AnnouncementDetailsScreen extends StatefulWidget {
  final String subjectId;
  final String postId;
  final Map<String, dynamic> announcement;
  final String authorName;
  final String authorEmail;
  final String authorRole;
  final bool isGlobalAnnouncement;

  const AnnouncementDetailsScreen({
    super.key,
    required this.subjectId,
    required this.postId,
    required this.announcement,
    required this.authorName,
    required this.authorEmail,
    required this.authorRole,
    this.isGlobalAnnouncement = false,
  });

  @override
  State<AnnouncementDetailsScreen> createState() =>
      _AnnouncementDetailsScreenState();
}

class _AnnouncementDetailsScreenState extends State<AnnouncementDetailsScreen> {
  final _commentController = TextEditingController();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _commentsStream;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _commentsStream = FirestoreService.postCommentsStream(
      subjectId: widget.subjectId,
      postId: widget.postId,
      isGlobalAnnouncement: widget.isGlobalAnnouncement,
    );
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    try {
      await FirestoreService.addPostComment(
        subjectId: widget.subjectId,
        postId: widget.postId,
        authorName: widget.authorName,
        authorEmail: widget.authorEmail,
        authorRole: widget.authorRole,
        text: text,
        isGlobalAnnouncement: widget.isGlobalAnnouncement,
      );
      _commentController.clear();
    } on FirebaseException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add comment: ${error.message}')),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final announcement = widget.announcement;

    return Scaffold(
      appBar: AppBar(
        title: Text(announcement['title'] as String? ?? 'Announcement'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _commentsStream,
        builder: (context, snapshot) {
          final comments = [...?snapshot.data?.docs];
          comments.sort((a, b) {
            final aDate = _commentDate(a.data()['createdAt']);
            final bDate = _commentDate(b.data()['createdAt']);
            if (aDate == null && bDate == null) return a.id.compareTo(b.id);
            if (aDate == null) return -1;
            if (bDate == null) return 1;
            return aDate.compareTo(bDate);
          });

          return RefreshIndicator(
            onRefresh: () => FirestoreService.refreshPostComments(
              subjectId: widget.subjectId,
              postId: widget.postId,
              isGlobalAnnouncement: widget.isGlobalAnnouncement,
            ),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  announcement['posterName'] as String? ??
                      announcement['author'] as String? ??
                      'Instructor',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  formatPostedDate(announcement['postedAt']),
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
                const SizedBox(height: 16),
                Text(
                  announcement['title'] as String? ?? 'Announcement',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(announcement['body'] as String? ?? ''),
                const Divider(height: 32),
                Text(
                  'Class comments',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                if (snapshot.hasError)
                  _CommentsLoadError(error: snapshot.error)
                else if (snapshot.connectionState == ConnectionState.waiting)
                  const Center(child: CircularProgressIndicator())
                else if (comments.isEmpty)
                  const Text('No comments')
                else
                  ...comments.map(
                    (comment) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _CommentTile(data: comment.data()),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            12 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _commentController,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: 'Add class comment',
                    filled: true,
                    fillColor: AppPalette.cream,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _isSending ? null : _sendComment,
                color: AppPalette.burgundyDark,
                tooltip: 'Post class comment',
                icon: _isSending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AnnouncementCommentsButton extends StatelessWidget {
  final String subjectId;
  final String postId;
  final String authorName;
  final String authorEmail;
  final String authorRole;

  const AnnouncementCommentsButton({
    super.key,
    required this.subjectId,
    required this.postId,
    required this.authorName,
    required this.authorEmail,
    required this.authorRole,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AnnouncementCommentsScreen(
              subjectId: subjectId,
              postId: postId,
              authorName: authorName,
              authorEmail: authorEmail,
              authorRole: authorRole,
            ),
          ),
        ),
        icon: const Icon(Icons.comment_outlined, size: 18),
        label: const Text('Comments'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppPalette.burgundyDark,
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}

class AnnouncementCommentsScreen extends StatefulWidget {
  final String subjectId;
  final String postId;
  final String authorName;
  final String authorEmail;
  final String authorRole;

  const AnnouncementCommentsScreen({
    super.key,
    required this.subjectId,
    required this.postId,
    required this.authorName,
    required this.authorEmail,
    required this.authorRole,
  });

  @override
  State<AnnouncementCommentsScreen> createState() =>
      _AnnouncementCommentsScreenState();
}

class _AnnouncementCommentsScreenState
    extends State<AnnouncementCommentsScreen> {
  final _commentController = TextEditingController();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _commentsStream;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _commentsStream = FirestoreService.postCommentsStream(
      subjectId: widget.subjectId,
      postId: widget.postId,
    );
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    try {
      await FirestoreService.addPostComment(
        subjectId: widget.subjectId,
        postId: widget.postId,
        authorName: widget.authorName,
        authorEmail: widget.authorEmail,
        authorRole: widget.authorRole,
        text: text,
      );
      _commentController.clear();
    } on FirebaseException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add comment: ${error.message}')),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Class comments')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _commentsStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            final error = snapshot.error;
            final details = error is FirebaseException
                ? [error.code, ?error.message].join('\n')
                : error.toString();
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.cloud_off_outlined,
                      size: 36,
                      color: AppPalette.burgundy,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Unable to load comments',
                      style: TextStyle(fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      details,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              ),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final comments = [...?snapshot.data?.docs];
          comments.sort((a, b) {
            final aDate = _commentDate(a.data()['createdAt']);
            final bDate = _commentDate(b.data()['createdAt']);
            if (aDate == null && bDate == null) return a.id.compareTo(b.id);
            if (aDate == null) return -1;
            if (bDate == null) return 1;
            return aDate.compareTo(bDate);
          });

          if (comments.isEmpty) {
            return const Center(child: Text('Be the first to comment.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: comments.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              return _CommentTile(data: comments[index].data());
            },
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            12 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _commentController,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: 'Add class comment',
                    filled: true,
                    fillColor: AppPalette.cream,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _isSending ? null : _sendComment,
                color: AppPalette.burgundyDark,
                tooltip: 'Post class comment',
                icon: _isSending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

DateTime? _commentDate(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}

class _CommentTile extends StatelessWidget {
  final Map<String, dynamic> data;

  const _CommentTile({required this.data});

  @override
  Widget build(BuildContext context) {
    final name = data['authorName'] as String? ?? 'User';
    final role = data['authorRole'] as String? ?? '';
    final authorEmail = data['authorEmail']?.toString() ?? '';
    final authorRole = role.toLowerCase();
    final userRole =
        authorRole.contains('teacher') || authorRole.contains('instructor')
        ? UserRole.instructor
        : UserRole.student;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        UserProfileAvatar(
          role: userRole,
          userEmail: authorEmail,
          profileImageUrl: null,
          radius: 16,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppPalette.cream,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    role.isEmpty ? name : '$name · $role',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(data['text'] as String? ?? ''),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CommentsLoadError extends StatelessWidget {
  final Object? error;

  const _CommentsLoadError({required this.error});

  @override
  Widget build(BuildContext context) {
    final currentError = error;
    final details = currentError is FirebaseException
        ? [currentError.code, ?currentError.message].join('\n')
        : currentError?.toString() ?? 'Unknown error';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        'Unable to load comments.\n$details',
        style: const TextStyle(color: Colors.red),
      ),
    );
  }
}
