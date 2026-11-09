import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'firestore_service.dart';
import 'home_screen.dart';
import 'task_details_screen.dart';

Future<void> showPrivateMessageSheet({
  required BuildContext context,
  required String studentEmail,
  required String studentName,
  required String instructorEmail,
  required String instructorName,
  required String subjectTitle,
  required String subjectId,
  required String taskTitle,
  required String taskId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _PrivateMessageSheet(
      studentEmail: studentEmail,
      studentName: studentName,
      instructorEmail: instructorEmail,
      instructorName: instructorName,
      subjectTitle: subjectTitle,
      subjectId: subjectId,
      taskTitle: taskTitle,
      taskId: taskId,
    ),
  );
}

class _PrivateMessageSheet extends StatefulWidget {
  final String studentEmail;
  final String studentName;
  final String instructorEmail;
  final String instructorName;
  final String subjectTitle;
  final String subjectId;
  final String taskTitle;
  final String taskId;

  const _PrivateMessageSheet({
    required this.studentEmail,
    required this.studentName,
    required this.instructorEmail,
    required this.instructorName,
    required this.subjectTitle,
    required this.subjectId,
    required this.taskTitle,
    required this.taskId,
  });

  @override
  State<_PrivateMessageSheet> createState() => _PrivateMessageSheetState();
}

class _PrivateMessageSheetState extends State<_PrivateMessageSheet> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.78,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                UserProfileAvatar(
                  role: UserRole.instructor,
                  userEmail: widget.instructorEmail,
                  profileImageUrl: null,
                  radius: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Message ${widget.instructorName}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirestoreService.messagesStream(
                studentEmail: widget.studentEmail,
                instructorEmail: widget.instructorEmail,
              ),
              builder: (context, snapshot) {
                final messages = (snapshot.data?.docs ?? const [])
                    .where((message) {
                      final data = message.data();
                      return data['subjectId']?.toString() ==
                              widget.subjectId &&
                          data['taskId']?.toString() == widget.taskId;
                    })
                    .toList();
                if (messages.isEmpty) {
                  return const Center(
                    child: Text('Start a private conversation.'),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final data = messages[index].data();
                    final senderEmail =
                        data['senderEmail']?.toString().trim() ?? '';
                    final isMine =
                        senderEmail.toLowerCase() ==
                        widget.studentEmail.trim().toLowerCase();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment: isMine
                            ? MainAxisAlignment.end
                            : MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!isMine) ...[
                            UserProfileAvatar(
                              role: UserRole.instructor,
                              userEmail: widget.instructorEmail,
                              profileImageUrl: null,
                              radius: 16,
                            ),
                            const SizedBox(width: 8),
                          ],
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              constraints: const BoxConstraints(maxWidth: 320),
                              decoration: BoxDecoration(
                                color: isMine
                                    ? const Color(0xFFE8D8C1)
                                    : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _messageOrigin(data),
                                  Text(data['text']?.toString() ?? ''),
                                ],
                              ),
                            ),
                          ),
                          if (isMine) ...[
                            const SizedBox(width: 8),
                            UserProfileAvatar(
                              role: UserRole.student,
                              userEmail: widget.studentEmail,
                              profileImageUrl: null,
                              radius: 16,
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Write a private message',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await FirestoreService.sendMessage(
        studentEmail: widget.studentEmail,
        instructorEmail: widget.instructorEmail,
        senderEmail: widget.studentEmail,
        senderName: widget.studentName,
        text: text,
        subjectTitle: widget.subjectTitle,
        subjectId: widget.subjectId,
        taskTitle: widget.taskTitle,
        taskId: widget.taskId,
      );
      _controller.clear();
    } on FirebaseException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Message could not be sent (${error.code}).')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

Widget _messageOrigin(Map<String, dynamic> data) {
  final subjectTitle = data['subjectTitle']?.toString().trim() ?? '';
  final taskTitle = data['taskTitle']?.toString().trim() ?? '';
  final origin = [
    subjectTitle,
    taskTitle,
  ].where((value) => value.isNotEmpty).join(' · ');
  if (origin.isEmpty) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      'From: $origin',
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
    ),
  );
}

class MessagingScreen extends StatefulWidget {
  final String studentEmail;
  final String studentName;
  final String instructorEmail;
  final String instructorName;
  final String senderEmail;
  final String senderName;
  final String? subjectId;
  final String? subjectTitle;
  final String? taskId;
  final String? taskTitle;

  const MessagingScreen({
    super.key,
    required this.studentEmail,
    required this.studentName,
    required this.instructorEmail,
    required this.instructorName,
    required this.senderEmail,
    required this.senderName,
    this.subjectId,
    this.subjectTitle,
    this.taskId,
    this.taskTitle,
  });

  @override
  State<MessagingScreen> createState() => _MessagingScreenState();
}

class InstructorMessagesScreen extends StatelessWidget {
  final String instructorEmail;
  final String instructorName;

  const InstructorMessagesScreen({
    super.key,
    required this.instructorEmail,
    required this.instructorName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Student Messages')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirestoreService.instructorConversationsStream(instructorEmail),
        builder: (context, snapshot) {
          final conversations = snapshot.data?.docs ?? const [];
          if (conversations.isEmpty) {
            return RefreshIndicator(
              onRefresh: () => FirestoreService.refreshInstructorConversations(
                instructorEmail,
              ),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(
                    height: 240,
                    child: Center(child: Text('No student messages yet.')),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () => FirestoreService.refreshInstructorConversations(
              instructorEmail,
            ),
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: conversations.length,
              itemBuilder: (context, index) {
                final data = conversations[index].data();
                final studentEmail = data['studentEmail']?.toString() ?? '';
                final studentName =
                    data['studentName']?.toString() ?? studentEmail;
                final subjectTitle =
                    data['sourceSubjectTitle']?.toString().trim() ?? '';
                final taskTitle =
                    data['sourceTaskTitle']?.toString().trim() ?? '';
                final subjectId =
                    data['sourceSubjectId']?.toString().trim() ?? '';
                final taskId = data['sourceTaskId']?.toString().trim() ?? '';
                final origin = [
                  subjectTitle,
                  taskTitle,
                ].where((value) => value.isNotEmpty).join(' · ');
                final lastMessage = data['lastMessage']?.toString() ?? '';
                return ListTile(
                  leading: UserProfileAvatar(
                    role: UserRole.student,
                    userEmail: studentEmail,
                    profileImageUrl: null,
                  ),
                  title: Text(studentName),
                  subtitle: Text(
                    origin.isEmpty
                        ? lastMessage
                        : 'From: $origin\n$lastMessage',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MessagingScreen(
                        studentEmail: studentEmail,
                        studentName: studentName,
                        instructorEmail: instructorEmail,
                        instructorName: instructorName,
                        senderEmail: instructorEmail,
                        senderName: instructorName,
                        subjectId: subjectId,
                        subjectTitle: subjectTitle,
                        taskId: taskId,
                        taskTitle: taskTitle,
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
      bottomNavigationBar: DashboardBottomNavigation(
        role: UserRole.instructor,
        homeIsActive: false,
        userName: instructorName,
        userEmail: instructorEmail,
      ),
    );
  }
}

class _MessagingScreenState extends State<MessagingScreen> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.senderEmail == widget.instructorEmail
              ? 'Message ${widget.studentName}'
              : 'Message ${widget.instructorName}',
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirestoreService.messagesStream(
                studentEmail: widget.studentEmail,
                instructorEmail: widget.instructorEmail,
              ),
              builder: (context, snapshot) {
                final messages = snapshot.data?.docs ?? const [];
                if (messages.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: () => FirestoreService.refreshMessages(
                      studentEmail: widget.studentEmail,
                      instructorEmail: widget.instructorEmail,
                    ),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(
                          height: 240,
                          child: Center(
                            child: Text('Start a private conversation.'),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () => FirestoreService.refreshMessages(
                    studentEmail: widget.studentEmail,
                    instructorEmail: widget.instructorEmail,
                  ),
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final data = messages[index].data();
                      final senderEmail =
                          data['senderEmail']
                              ?.toString()
                              .trim()
                              .toLowerCase() ??
                          '';
                      final currentEmail = widget.senderEmail
                          .trim()
                          .toLowerCase();
                      final instructorEmail = widget.instructorEmail
                          .trim()
                          .toLowerCase();
                      final isMine = senderEmail == currentEmail;
                      final hasOriginIds =
                          (data['subjectId']?.toString().isNotEmpty ?? false) &&
                          (data['taskId']?.toString().isNotEmpty ?? false);
                      final hasOriginTitles =
                          (data['subjectTitle']?.toString().trim().isNotEmpty ??
                              false) &&
                          (data['taskTitle']?.toString().trim().isNotEmpty ??
                              false);
                      final canOpenOrigin =
                          currentEmail == instructorEmail &&
                          !isMine &&
                          (hasOriginIds || hasOriginTitles);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          mainAxisAlignment: isMine
                              ? MainAxisAlignment.end
                              : MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!isMine) ...[
                              UserProfileAvatar(
                                role: UserRole.student,
                                userEmail: widget.studentEmail,
                                profileImageUrl: null,
                                radius: 16,
                              ),
                              const SizedBox(width: 8),
                            ],
                            Flexible(
                              child: InkWell(
                                onTap: canOpenOrigin
                                    ? () => _openOrigin(data)
                                    : null,
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  constraints: const BoxConstraints(
                                    maxWidth: 320,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isMine
                                        ? const Color(0xFFE8D8C1)
                                        : Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _messageOrigin(data),
                                      Text(data['text']?.toString() ?? ''),
                                      if (canOpenOrigin) ...[
                                        const SizedBox(height: 4),
                                        const Text(
                                          'Tap to open task',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.black54,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            if (isMine) ...[
                              const SizedBox(width: 8),
                              UserProfileAvatar(
                                role: UserRole.instructor,
                                userEmail: widget.instructorEmail,
                                profileImageUrl: null,
                                radius: 16,
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Write a message',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: DashboardBottomNavigation(
        role: UserRole.instructor,
        homeIsActive: false,
        userName: widget.instructorName,
        userEmail: widget.instructorEmail,
      ),
    );
  }

  Future<void> _openOrigin(Map<String, dynamic> message) async {
    try {
      final subjectId = message['subjectId']?.toString().trim() ?? '';
      final subjectTitle = message['subjectTitle']?.toString().trim() ?? '';
      final taskId = message['taskId']?.toString().trim() ?? '';
      final taskTitle = message['taskTitle']?.toString().trim() ?? '';
      var subjectSnapshot = subjectId.isNotEmpty
          ? await FirestoreService.getSubject(subjectId)
          : null;
      if ((subjectSnapshot == null || !subjectSnapshot.exists) &&
          subjectTitle.isNotEmpty) {
        subjectSnapshot = await FirestoreService.findSubjectByTitle(
          subjectTitle,
        );
      }
      if (!mounted) return;
      if (subjectSnapshot == null || !subjectSnapshot.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The original subject could not be found.'),
          ),
        );
        return;
      }
      var resolvedTask = taskId.isNotEmpty
          ? await FirestoreService.getSubjectTask(
              subjectId: subjectSnapshot.id,
              taskId: taskId,
            )
          : null;
      if ((resolvedTask == null || !resolvedTask.exists) &&
          taskTitle.isNotEmpty) {
        resolvedTask = await FirestoreService.findSubjectTaskByTitle(
          subjectId: subjectSnapshot.id,
          taskTitle: taskTitle,
        );
      }
      if (!mounted) return;
      final taskSnapshot = resolvedTask;
      if (taskSnapshot == null || !taskSnapshot.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The original task could not be found.'),
          ),
        );
        return;
      }
      final subjectData = subjectSnapshot.data()!;
      final subject = Subject(
        id: subjectSnapshot.id,
        title: subjectData['name'] as String? ?? 'Subject',
        gradeLabel:
            subjectData['year'] as String? ??
            subjectData['yearLevel'] as String? ??
            '',
        instructorEmail:
            subjectData['instructorEmail'] as String? ?? widget.instructorEmail,
        thumbnailUrl: subjectData['thumbnailUrl'] as String?,
      );
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TaskDetailsScreen(
            subject: subject,
            role: UserRole.instructor,
            task: taskSnapshot,
          ),
        ),
      );
    } on FirebaseException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open the task (${error.code}).')),
        );
      }
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await FirestoreService.sendMessage(
        studentEmail: widget.studentEmail,
        instructorEmail: widget.instructorEmail,
        senderEmail: widget.senderEmail,
        senderName: widget.senderName,
        text: text,
        subjectId: widget.subjectId,
        subjectTitle: widget.subjectTitle,
        taskId: widget.taskId,
        taskTitle: widget.taskTitle,
      );
      _controller.clear();
    } on FirebaseException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Message could not be sent (${error.code}).')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
