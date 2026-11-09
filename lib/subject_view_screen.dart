import 'dart:convert';
import 'dart:typed_data';

import 'package:docx_to_text/docx_to_text.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:url_launcher/url_launcher.dart';
import 'cloudinary_service.dart';
import 'home_screen.dart';
import 'firestore_service.dart';
import 'classwork_screen.dart';
import 'student_classwork_screen.dart';
import 'task_details_screen.dart';
import 'saved_draft_page.dart';
import 'draft_store.dart';
import 'app_theme.dart';
import 'post_date_formatter.dart';
import 'task_due_date.dart';
import 'announcement_comments.dart';
import 'task_pdf_viewer.dart';

const _instructionFileExtensions = ['pdf', 'xls', 'xlsx', 'csv'];

bool _isHttpUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

bool _isGoogleSheetsUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host == 'docs.google.com' &&
      uri.path.startsWith('/spreadsheets/');
}

Widget _validationMessage(String message) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFFF5D7D7),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFFB3261E)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline, size: 16, color: Color(0xFFB3261E)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: Color(0xFF7A1B16), fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

typedef _AssignableStudent = ({String email, String name});

class _InlineStudentPicker extends StatefulWidget {
  final Subject subject;
  final List<String> selectedEmails;
  final List<String> selectedNames;
  final bool assignToAll;
  final ValueChanged<_AssignableStudent> onStudentSelected;
  final ValueChanged<String> onStudentRemoved;
  final ValueChanged<bool> onAssignToAllChanged;

  const _InlineStudentPicker({
    required this.subject,
    required this.selectedEmails,
    required this.selectedNames,
    required this.assignToAll,
    required this.onStudentSelected,
    required this.onStudentRemoved,
    required this.onAssignToAllChanged,
  });

  @override
  State<_InlineStudentPicker> createState() => _InlineStudentPickerState();
}

class _InlineStudentPickerState extends State<_InlineStudentPicker> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.studentsStream(),
      builder: (context, snapshot) {
        final students = (snapshot.data?.docs ?? const [])
            .where(
              (doc) => Subject.isStudentEnrolled(doc.data(), widget.subject),
            )
            .map((doc) {
              final data = doc.data();
              return (
                email: data['email']?.toString().trim() ?? '',
                name: data['name']?.toString().trim() ?? 'Student',
              );
            })
            .where((student) => student.email.isNotEmpty)
            .toList();
        return _buildPicker(students);
      },
    );
  }

  Widget _buildPicker(List<_AssignableStudent> students) {
    final query = _searchController.text.trim().toLowerCase();
    final selectedEmails = widget.selectedEmails
        .map((email) => email.toLowerCase())
        .toSet();
    final matches = query.isEmpty
        ? const <_AssignableStudent>[]
        : students
              .where(
                (student) =>
                    student.name.toLowerCase().contains(query) ||
                    student.email.toLowerCase().contains(query),
              )
              .take(6)
              .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppPalette.cream,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppPalette.muted.withValues(alpha: 0.35)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x16000000),
                blurRadius: 3,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.search, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: widget.assignToAll
                        ? 'Assign to...'
                        : 'Search students...',
                    filled: true,
                    fillColor: AppPalette.cream,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              Checkbox(
                value: widget.assignToAll,
                visualDensity: VisualDensity.compact,
                onChanged: (value) =>
                    widget.onAssignToAllChanged(value ?? false),
              ),
              InkWell(
                onTap: () => widget.onAssignToAllChanged(!widget.assignToAll),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Assign to all', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
        ),
        if (query.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 8),
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              color: AppPalette.cream,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppPalette.muted.withValues(alpha: 0.3),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x26000000),
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: matches.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('No students found.'),
                  )
                : ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    children: matches.map((student) {
                      final isSelected = selectedEmails.contains(
                        student.email.toLowerCase(),
                      );
                      return ListTile(
                        dense: true,
                        title: Text(student.name),
                        subtitle: Text(student.email),
                        trailing: isSelected
                            ? const Icon(
                                Icons.check_circle,
                                color: AppPalette.burgundy,
                              )
                            : null,
                        onTap: () => widget.onStudentSelected(student),
                      );
                    }).toList(),
                  ),
          ),
        if (widget.selectedEmails.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: List.generate(widget.selectedEmails.length, (index) {
              final name = index < widget.selectedNames.length
                  ? widget.selectedNames[index]
                  : widget.selectedEmails[index];
              return InputChip(
                label: Text(name),
                onDeleted: () =>
                    widget.onStudentRemoved(widget.selectedEmails[index]),
              );
            }),
          ),
        ],
      ],
    );
  }
}

class SubjectPeopleTab extends StatefulWidget {
  final Subject subject;
  final UserRole role;
  final String instructorName;
  final String instructorEmail;

  const SubjectPeopleTab({
    super.key,
    required this.subject,
    required this.role,
    required this.instructorName,
    required this.instructorEmail,
  });

  @override
  State<SubjectPeopleTab> createState() => _SubjectPeopleTabState();
}

class _SubjectPeopleTabState extends State<SubjectPeopleTab> {
  final TextEditingController _searchController = TextEditingController();
  Stream<QuerySnapshot<Map<String, dynamic>>>? _studentsStream;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveInstructorEmail = widget.instructorEmail.trim().isNotEmpty
        ? widget.instructorEmail
        : widget.subject.instructorEmail;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _studentsStream ??= FirestoreService.studentsStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Unable to load enrolled students.'));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final students =
            (snapshot.data?.docs ?? const [])
                .where(
                  (doc) =>
                      Subject.isStudentEnrolled(doc.data(), widget.subject),
                )
                .toList()
              ..sort(
                (a, b) => ((a.data()['name'] as String?) ?? 'Student')
                    .toLowerCase()
                    .compareTo(
                      ((b.data()['name'] as String?) ?? 'Student')
                          .toLowerCase(),
                    ),
              );
        final query = _searchController.text.trim().toLowerCase();
        final filteredStudents = query.isEmpty
            ? students
            : students.where((student) {
                final data = student.data();
                final name = (data['name'] as String? ?? 'Student')
                    .toLowerCase();
                final email = (data['email'] as String? ?? '').toLowerCase();
                return name.contains(query) || email.contains(query);
              }).toList();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                filled: true,
                fillColor: AppPalette.cream,
                hintText: 'Search students by name or email',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.clear),
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            _sectionTitle(
              icon: Icons.school_outlined,
              title: 'Instructor',
              subtitle: 'Subject instructor',
            ),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: effectiveInstructorEmail.trim().isEmpty
                  ? null
                  : FirestoreService.userProfileStream(
                      collection: 'instructor_accounts',
                      email: effectiveInstructorEmail,
                    ),
              builder: (context, instructorSnapshot) {
                final instructorData =
                    instructorSnapshot.data?.docs.isNotEmpty == true
                    ? instructorSnapshot.data!.docs.first.data()
                    : null;
                final instructorImage =
                    instructorData?['profileImageUrl']?.toString() ??
                    instructorData?['photoUrl']?.toString();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 64,
                        vertical: 4,
                      ),
                      child: Divider(height: 1),
                    ),
                    _personTile(
                      icon: Icons.person_outline,
                      name: widget.instructorName.trim().isEmpty
                          ? (instructorData?['name']?.toString() ??
                                'Instructor')
                          : widget.instructorName,
                      email: effectiveInstructorEmail,
                      profileImageUrl: instructorImage,
                    ),
                  ],
                );
              },
            ),
            const Divider(height: 32),
            _sectionTitle(
              icon: Icons.groups_outlined,
              title: 'Enrolled students',
              subtitle: query.isEmpty
                  ? '${students.length} student(s)'
                  : '${filteredStudents.length} of ${students.length} student(s)',
            ),
            if (students.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('No students are enrolled in this subject.'),
                ),
              )
            else if (filteredStudents.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No students match your search.')),
              )
            else
              ...filteredStudents.asMap().entries.expand((entry) {
                final student = entry.value;
                final data = student.data();
                final name = data['name'] as String? ?? 'Student';
                return <Widget>[
                  if (entry.key == 0)
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 64,
                        vertical: 4,
                      ),
                      child: Divider(height: 1),
                    ),
                  _personTile(
                    icon: Icons.person_outline,
                    name: name,
                    email: data['email'] as String? ?? '',
                    initials: name,
                    profileImageUrl:
                        data['profileImageUrl']?.toString() ??
                        data['photoUrl']?.toString(),
                    onTap: widget.role == UserRole.instructor
                        ? () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => StudentProgressScreen(
                                subject: widget.subject,
                                studentName: name,
                                studentEmail: data['email'] as String? ?? '',
                              ),
                            ),
                          )
                        : null,
                  ),
                  if (entry.key < filteredStudents.length - 1)
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 64,
                        vertical: 4,
                      ),
                      child: Divider(height: 1),
                    ),
                ];
              }),
          ],
        );
      },
    );
  }

  Widget _sectionTitle({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: const Color(0xFFF8DCE0),
        foregroundColor: AppPalette.burgundyDark,
        child: Icon(icon),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
    );
  }

  Widget _personTile({
    required IconData icon,
    required String name,
    required String email,
    String? initials,
    String? profileImageUrl,
    VoidCallback? onTap,
  }) {
    final trimmedName = name.trim();
    final imageUrl = profileImageUrl?.trim();
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 16),
      onTap: onTap,
      trailing: onTap == null
          ? null
          : const Icon(Icons.chevron_right, color: Colors.black54),
      leading: CircleAvatar(
        backgroundImage: imageUrl != null && imageUrl.isNotEmpty
            ? NetworkImage(imageUrl)
            : null,
        backgroundColor: const Color(0xFFF8DCE0),
        foregroundColor: AppPalette.burgundyDark,
        child: imageUrl != null && imageUrl.isNotEmpty
            ? null
            : initials == null
            ? Icon(icon)
            : Text(trimmedName.isEmpty ? '?' : trimmedName[0].toUpperCase()),
      ),
      title: Text(trimmedName.isEmpty ? 'Student' : trimmedName),
      subtitle: Text(email.trim().isEmpty ? 'No email available' : email),
    );
  }
}

class StudentProgressScreen extends StatelessWidget {
  final Subject subject;
  final String studentName;
  final String studentEmail;

  const StudentProgressScreen({
    super.key,
    required this.subject,
    required this.studentName,
    required this.studentEmail,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.userProfileStream(
        collection: 'students',
        email: studentEmail,
      ),
      builder: (context, profileSnapshot) {
        final student = profileSnapshot.data?.docs.isNotEmpty == true
            ? profileSnapshot.data!.docs.first.data()
            : const <String, dynamic>{};
        final currentStudentName =
            (student['name'] as String?)?.trim().isNotEmpty == true
            ? (student['name'] as String).trim()
            : studentName;
        final profileImageUrl =
            (student['profileImageUrl'] as String?)?.trim().isNotEmpty == true
            ? (student['profileImageUrl'] as String).trim()
            : (student['photoUrl'] as String?)?.trim();
        final gradeLevel =
            student['gradeLevel'] ?? student['yearLevel'] ?? student['grade'];
        final section = student['section'] ?? student['classSection'];
        final phone = student['phoneNumber'] ?? student['phone'];
        final profileDetails = [
          studentEmail,
          if (gradeLevel is String && gradeLevel.trim().isNotEmpty)
            gradeLevel.trim(),
          if (section is String && section.trim().isNotEmpty)
            'Section ${section.trim()}',
          if (phone is String && phone.trim().isNotEmpty) phone.trim(),
          if (student['gender'] is String &&
              (student['gender'] as String).trim().isNotEmpty)
            (student['gender'] as String).trim(),
        ].where((value) => value.isNotEmpty).join(' · ');

        return Scaffold(
          backgroundColor: AppPalette.background,
          appBar: AppBar(
            title: Text(currentStudentName),
            backgroundColor: AppPalette.burgundyDark,
            foregroundColor: Colors.white,
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              await Future.wait([
                FirestoreService.refreshUserProfile(
                  collection: 'students',
                  email: studentEmail,
                ),
                FirestoreService.refreshSubjectContent(
                  subjectId: subject.id,
                  role: 'student',
                  email: studentEmail,
                  authUid: FirebaseAuth.instance.currentUser?.uid ?? '',
                ),
              ]);
            },
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirestoreService.subjectPostsStream(subject.id),
              builder: (context, snapshot) {
                final tasks = (snapshot.data?.docs ?? const [])
                    .where((doc) => doc.data()['type'] == 'Task')
                    .toList();
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(
                        height: 240,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ],
                  );
                }

                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(12),
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      leading: CircleAvatar(
                        backgroundImage:
                            profileImageUrl != null &&
                                profileImageUrl.isNotEmpty
                            ? NetworkImage(profileImageUrl)
                            : null,
                        child:
                            profileImageUrl == null || profileImageUrl.isEmpty
                            ? Text(
                                currentStudentName.trim().isEmpty
                                    ? '?'
                                    : currentStudentName
                                          .trim()[0]
                                          .toUpperCase(),
                              )
                            : null,
                      ),
                      title: Text(
                        currentStudentName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(profileDetails),
                    ),
                    const Divider(),
                    if (tasks.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text('No tasks have been assigned yet.'),
                        ),
                      )
                    else
                      ...tasks.map((task) => _taskProgressCard(task)),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _taskProgressCard(QueryDocumentSnapshot<Map<String, dynamic>> task) {
    final data = task.data();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.studentSubmissionStream(
        subjectId: subject.id,
        taskId: task.id,
        studentEmail: studentEmail,
      ),
      builder: (context, snapshot) {
        final submission = snapshot.data?.data();
        final isPublished = submission?['reviewStatus'] == 'published';
        final score = isPublished && submission != null
            ? submission['score']
            : null;
        final maxScore = isPublished && submission != null
            ? submission['maxScore']
            : null;
        final status = score != null
            ? 'Graded'
            : submission != null && submission['status'] == 'Submitted'
            ? 'Submitted · awaiting review'
            : 'Not submitted';

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          color: AppPalette.cream,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        data['title'] as String? ?? 'Untitled task',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    if (score is num)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE3F3E5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          maxScore is num
                              ? '${_formatScore(score)}/${_formatScore(maxScore)}'
                              : _formatScore(score),
                          style: TextStyle(
                            color: Colors.green.shade800,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Due: ${formatTaskDueDate(data['dueDate'] ?? data['due'])}',
                  style: const TextStyle(color: Colors.black54),
                ),
                Text(
                  status,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: score != null ? Colors.green.shade800 : null,
                  ),
                ),
                if (isPublished &&
                    submission != null &&
                    (submission['feedback'] as String? ?? '')
                        .trim()
                        .isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Instructor feedback',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(submission['feedback'] as String),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatScore(Object? value) {
    if (value is! num) return '-';
    return value % 1 == 0 ? value.toInt().toString() : value.toString();
  }
}

DateTime? _taskDateFromValue(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

Future<Map<String, dynamic>> _readRubricDocument(
  Uint8List bytes,
  String fileName,
) async {
  final extension = fileName.split('.').last.toLowerCase();
  if (extension == 'csv') {
    return _readRubricCsv(utf8.decode(bytes, allowMalformed: true));
  }

  final String text;
  if (extension == 'pdf') {
    final document = PdfDocument(inputBytes: bytes);
    try {
      text = PdfTextExtractor(document).extractText();
    } finally {
      document.dispose();
    }
  } else if (extension == 'docx') {
    text = docxToText(bytes);
  } else if (extension == 'txt') {
    text = utf8.decode(bytes, allowMalformed: true);
  } else {
    throw const FormatException(
      'Legacy .doc files are not supported. Save the file as .docx or .pdf.',
    );
  }

  final lines = text
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (lines.isEmpty) {
    throw const FormatException('The rubric document does not contain text.');
  }

  String? valueAfter(String label) {
    final line = lines.firstWhere(
      (line) => line.toLowerCase().startsWith('${label.toLowerCase()}:'),
      orElse: () => '',
    );
    return line.isEmpty ? null : line.substring(label.length + 1).trim();
  }

  final type = valueAfter('Type');
  if (type != 'Holistic' && type != 'Analytic') {
    throw const FormatException(
      'Add "Type: Holistic" or "Type: Analytic" to the document.',
    );
  }
  final title = valueAfter('Title') ?? '';
  final criteria = <Map<String, dynamic>>[];
  if (type == 'Holistic') {
    for (final line in lines) {
      final match = RegExp(
        r'^(\d+(?:\.\d+)?)\s*[\-|:]\s*(.+)$',
      ).firstMatch(line);
      if (match != null) {
        criteria.add({
          'points': match.group(1)!,
          'description': match.group(2)!.trim(),
        });
      }
    }
  } else {
    for (var index = 0; index < lines.length; index++) {
      final match = RegExp(
        r'^Criterion\s*:\s*(.+)$',
        caseSensitive: false,
      ).firstMatch(lines[index]);
      if (match == null) continue;
      final levels = <String>[];
      for (
        var next = index + 1;
        next < lines.length &&
            !lines[next].toLowerCase().startsWith('criterion:');
        next++
      ) {
        final level = RegExp(
          r'^(?:Level\s*\d+\s*:\s*)(.+)$',
          caseSensitive: false,
        ).firstMatch(lines[next]);
        if (level != null) levels.add(level.group(1)!.trim());
      }
      criteria.add({'title': match.group(1)!.trim(), 'levels': levels});
    }
  }
  if (criteria.isEmpty) {
    throw const FormatException(
      'No rubric criteria found. Use points-description lines for Holistic '
      'or Criterion:/Level 1: lines for Analytic.',
    );
  }
  return {'title': title, 'type': type, 'criteria': criteria};
}

Future<Map<String, dynamic>> _readRubricCsv(String text) async {
  final rows = <List<String>>[];
  var row = <String>[];
  var field = StringBuffer();
  var inQuotes = false;

  for (var index = 0; index < text.length; index++) {
    final character = text[index];
    if (inQuotes) {
      if (character == '"') {
        if (index + 1 < text.length && text[index + 1] == '"') {
          field.write('"');
          index++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(character);
      }
    } else if (character == '"' && field.isEmpty) {
      inQuotes = true;
    } else if (character == ',') {
      row.add(field.toString().trim());
      field = StringBuffer();
    } else if (character == '\n' || character == '\r') {
      if (character == '\r' &&
          index + 1 < text.length &&
          text[index + 1] == '\n') {
        index++;
      }
      row.add(field.toString().trim());
      rows.add(row);
      row = <String>[];
      field = StringBuffer();
    } else {
      field.write(character);
    }
  }
  if (inQuotes) {
    throw const FormatException('The CSV contains an unclosed quoted field.');
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString().trim());
    rows.add(row);
  }

  if (rows.isEmpty) {
    throw const FormatException('The CSV file is empty.');
  }

  final headers = rows.first.asMap().map((index, value) {
    final normalized = value
        .replaceFirst('\uFEFF', '')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
    return MapEntry(normalized, index);
  });
  int? headerIndex(List<String> aliases) {
    for (final alias in aliases) {
      final index = headers[alias];
      if (index != null) return index;
    }
    return null;
  }

  String cell(List<String> values, int? index) {
    if (index == null || index >= values.length) return '';
    return values[index].trim();
  }

  final typeIndex = headerIndex(const ['type', 'rubrictype']);
  final titleIndex = headerIndex(const ['title', 'rubrictitle']);
  final pointsIndex = headerIndex(const ['points', 'point', 'score']);
  final descriptionIndex = headerIndex(const ['description', 'descriptions']);
  final criterionIndex = headerIndex(const ['criterion', 'criteria']);
  final scoreIndex = headerIndex(const ['score', 'criterionscore', 'weight']);
  final levelColumns = <({int number, int index})>[];
  for (final entry in headers.entries) {
    final match =
        RegExp(r'^level(\d+)$').firstMatch(entry.key) ??
        RegExp(r'^(\d+)$').firstMatch(entry.key);
    if (match != null) {
      final number = int.tryParse(match.group(1)!);
      if (number != null && number >= 1) {
        levelColumns.add((number: number, index: entry.value));
      }
    }
  }
  levelColumns.sort((first, second) => first.number.compareTo(second.number));
  if (levelColumns.length > 5 ||
      levelColumns.asMap().entries.any(
        (entry) => entry.value.number != entry.key + 1,
      )) {
    throw const FormatException(
      'Analytic CSV levels must be consecutive columns from Level 1 to Level 5.',
    );
  }

  final isHolistic = pointsIndex != null && descriptionIndex != null;
  final isAnalytic = criterionIndex != null && levelColumns.isNotEmpty;
  if (isHolistic == isAnalytic) {
    throw const FormatException(
      'Use holistic columns Points and Description, or analytic columns '
      'Criterion and Level 1, Level 2, and so on.',
    );
  }

  final criteria = <Map<String, dynamic>>[];
  var rubricTitle = '';
  var rubricType = '';
  for (var rowIndex = 1; rowIndex < rows.length; rowIndex++) {
    final values = rows[rowIndex];
    if (values.every((value) => value.trim().isEmpty)) continue;
    final rowType = cell(values, typeIndex);
    if (rowType.isNotEmpty) {
      final normalizedType = rowType.toLowerCase();
      final parsedType = normalizedType.startsWith('h')
          ? 'Holistic'
          : normalizedType.startsWith('a')
          ? 'Analytic'
          : '';
      if (parsedType.isEmpty) {
        throw FormatException('Unknown rubric type "$rowType".');
      }
      if (rubricType.isNotEmpty && rubricType != parsedType) {
        throw const FormatException(
          'Use the same rubric type for every CSV row.',
        );
      }
      rubricType = parsedType;
    }
    final rowTitle = cell(values, titleIndex);
    if (rubricTitle.isEmpty && rowTitle.isNotEmpty) rubricTitle = rowTitle;

    if (isHolistic) {
      final rawPoints = cell(values, pointsIndex);
      final description = cell(values, descriptionIndex);
      if (rawPoints.isEmpty && description.isEmpty) continue;
      final numericPoints = RegExp(
        r'[+-]?(?:\d+(?:\.\d*)?|\.\d+)',
      ).firstMatch(rawPoints);
      if (numericPoints == null) {
        throw FormatException(
          'CSV row ${rowIndex + 1} must include numeric points.',
        );
      }
      final points = numericPoints.group(0)!;
      criteria.add({'points': points, 'description': description});
    } else {
      final title = cell(values, criterionIndex);
      final levels = levelColumns
          .map((column) => cell(values, column.index))
          .toList();
      final score = cell(values, scoreIndex);
      if (title.isEmpty &&
          levels.every((level) => level.isEmpty) &&
          score.isEmpty) {
        continue;
      }
      criteria.add({
        'title': title,
        'levels': levels,
        if (score.isNotEmpty) 'score': score,
      });
    }
  }

  final inferredType = isAnalytic ? 'Analytic' : 'Holistic';
  if (rubricType.isNotEmpty && rubricType != inferredType) {
    throw const FormatException(
      'The Type column does not match the rubric columns.',
    );
  }
  if (criteria.isEmpty) {
    throw const FormatException('No rubric rows were found in the CSV.');
  }
  return {
    'title': rubricTitle,
    'type': inferredType,
    'criteria': criteria,
    if (isAnalytic) 'levelCount': levelColumns.length,
  };
}

String _formatTaskDueDateTime(DateTime dateTime) {
  final date = '${dateTime.month}/${dateTime.day}/${dateTime.year}';
  final hour = dateTime.hour == 0
      ? 12
      : dateTime.hour > 12
      ? dateTime.hour - 12
      : dateTime.hour;
  final minute = dateTime.minute.toString().padLeft(2, '0');
  final period = dateTime.hour >= 12 ? 'PM' : 'AM';
  return '$date at $hour:$minute $period';
}

class SubjectViewScreen extends StatelessWidget {
  final Subject subject;
  final UserRole role;
  final String instructorName;
  final String instructorEmail;
  final String studentName;
  final String studentEmail;
  final String? profileImageUrl;

  const SubjectViewScreen({
    super.key,
    required this.subject,
    required this.role,
    this.instructorName = '',
    this.instructorEmail = '',
    this.studentName = '',
    this.studentEmail = '',
    this.profileImageUrl,
  });

  static const Color burgundy = AppPalette.burgundy;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Builder(
        builder: (context) => Scaffold(
          backgroundColor: AppPalette.background,
          body: SafeArea(
            child: Column(
              children: [
                _buildTopBar(context),
                _buildBannerWithTabs(context),
                Expanded(
                  child: TabBarView(
                    children: [
                      ClassroomTab(
                        subject: subject,
                        role: role,
                        instructorName: instructorName,
                        instructorEmail: instructorEmail,
                        studentName: studentName,
                        studentEmail: studentEmail,
                        profileImageUrl: profileImageUrl,
                      ),
                      role == UserRole.instructor
                          ? ClassworksScreen(
                              subject: subject,
                              role: role,
                              profileImageUrl: profileImageUrl,
                            )
                          : StudentClassworkScreen(
                              subject: subject,
                              studentName: studentName,
                              studentEmail: studentEmail,
                              profileImageUrl: profileImageUrl,
                            ),
                      SubjectPeopleTab(
                        subject: subject,
                        role: role,
                        instructorName: instructorName,
                        instructorEmail: instructorEmail,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: DashboardBottomNavigation(
            role: role,
            homeIsActive: false,
            userName: role == UserRole.instructor
                ? instructorName
                : studentName,
            userEmail: role == UserRole.instructor
                ? instructorEmail
                : studentEmail,
            profileImageUrl: profileImageUrl,
          ),
        ),
      ),
    );
  }

  static Future<({bool saved, Map<String, dynamic> rubric})?>
  _showCreateRubricDialog(
    BuildContext context, {
    required Subject subject,
    required String taskTitle,
    required String taskBody,
    required String instructorName,
    required String instructorEmail,
    required UserRole role,
    String? profileImageUrl,
    required bool allowUpload,
    required bool closeAfterDeadline,
    List<String> targetStudentEmails = const [],
    List<String> targetStudentNames = const [],
    String? attachmentName,
    String? attachmentUrl,
    int? draftIndex,
    Map<String, dynamic>? initialRubric,
    String? postId,
    DateTime? dueDate,
  }) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    var latestRubric = Map<String, dynamic>.from(initialRubric ?? const {});
    final hasPdfAttachment =
        attachmentName?.trim().toLowerCase().endsWith('.pdf') == true &&
        (attachmentUrl?.trim().isNotEmpty ?? false);
    final titleController = TextEditingController(
      text: initialRubric?['title'] as String? ?? '',
    );
    final standardsController = TextEditingController(
      text: initialRubric?['curriculumStandards'] is Map
          ? (initialRubric!['curriculumStandards'] as Map).values
                .expand((value) => value is List ? value : [value])
                .join(', ')
          : '',
    );
    final rawCriteria = initialRubric?['criteria'];
    final initialCriteria = rawCriteria is List
        ? rawCriteria.whereType<Map>().map(Map<String, dynamic>.from).toList()
        : <Map<String, dynamic>>[];
    final inferredLevelCount = initialCriteria.fold<int>(0, (
      maximum,
      criterion,
    ) {
      final levels = criterion['levels'];
      final count = levels is List ? levels.length : 0;
      return count > maximum ? count : maximum;
    });
    final savedLevelCount = initialRubric?['levelCount'];
    var levelCount =
        ((savedLevelCount is num
                    ? savedLevelCount.toInt()
                    : inferredLevelCount > 0
                    ? inferredLevelCount
                    : 4)
                .clamp(1, 5))
            .toInt();
    final selectedRubricType = initialRubric?['type'];
    String selectedType = selectedRubricType == 'Analytic'
        ? 'Analytic'
        : 'Holistic';
    String? validationError;
    bool isPosting = false;
    bool isLoadingRubricTemplate = false;
    final isCompact = MediaQuery.sizeOf(context).width < 600;

    TextEditingController controllerFrom(dynamic value) =>
        TextEditingController(text: value?.toString() ?? '');

    final rows = initialCriteria
        .where(
          (criterion) =>
              criterion.containsKey('points') ||
              criterion.containsKey('description'),
        )
        .map(
          (criterion) => <String, TextEditingController>{
            'points': controllerFrom(criterion['points']),
            'desc': controllerFrom(criterion['description']),
          },
        )
        .toList();
    if (rows.isEmpty) {
      rows.addAll(
        List.generate(
          5,
          (_) => {
            'points': TextEditingController(),
            'desc': TextEditingController(),
          },
        ),
      );
    }

    final analyticRows = initialCriteria
        .where((criterion) => criterion['levels'] is List)
        .map((criterion) {
          final levels = criterion['levels'] as List;
          return <String, dynamic>{
            'title': controllerFrom(criterion['title']),
            'score': controllerFrom(criterion['score']),
            'levels': List.generate(
              levelCount,
              (index) =>
                  controllerFrom(index < levels.length ? levels[index] : ''),
            ),
          };
        })
        .toList();
    if (analyticRows.isEmpty) {
      analyticRows.addAll(
        List.generate(
          4,
          (index) => <String, dynamic>{
            'title': TextEditingController(text: 'Criterion ${index + 1}'),
            'score': TextEditingController(),
            'levels': List.generate(levelCount, (_) => TextEditingController()),
          },
        ),
      );
    }

    final rubricRoute = MaterialPageRoute<bool>(
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            void applyImportedRubric(Map<String, dynamic> imported) {
              final importedCriteria = imported['criteria'] as List;
              for (final row in rows) {
                for (final controller in row.values) {
                  controller.dispose();
                }
              }
              for (final row in analyticRows) {
                (row['title'] as TextEditingController).dispose();
                (row['score'] as TextEditingController).dispose();
                for (final controller
                    in row['levels'] as List<TextEditingController>) {
                  controller.dispose();
                }
              }
              rows.clear();
              analyticRows.clear();
              selectedType = imported['type'] as String;
              titleController.text = imported['title']?.toString() ?? '';
              final standards = imported['curriculumStandards'];
              standardsController.text = standards is Map
                  ? standards.values
                        .expand((value) => value is List ? value : [value])
                        .join(', ')
                  : '';
              if (selectedType == 'Holistic') {
                rows.addAll(
                  importedCriteria.map<Map<String, TextEditingController>>((
                    criterion,
                  ) {
                    final item = Map<String, dynamic>.from(criterion as Map);
                    return {
                      'points': controllerFrom(item['points']),
                      'desc': controllerFrom(item['description']),
                    };
                  }),
                );
              } else {
                final importedLevels = importedCriteria
                    .map((criterion) => (criterion as Map)['levels'] as List)
                    .map((levels) => levels.length)
                    .fold<int>(
                      1,
                      (maximum, levelCountValue) =>
                          levelCountValue > maximum ? levelCountValue : maximum,
                    );
                levelCount = importedLevels.clamp(1, 5).toInt();
                analyticRows.addAll(
                  importedCriteria.map<Map<String, dynamic>>((criterion) {
                    final item = Map<String, dynamic>.from(criterion as Map);
                    final levels = item['levels'] as List;
                    return {
                      'title': controllerFrom(item['title']),
                      'score': controllerFrom(item['score']),
                      'levels': List.generate(
                        levelCount,
                        (index) => controllerFrom(
                          index < levels.length ? levels[index] : '',
                        ),
                      ),
                    };
                  }),
                );
              }
              setState(() => validationError = null);
            }

            Future<void> importPortalRubric() async {
              if (isLoadingRubricTemplate) return;
              setState(() {
                isLoadingRubricTemplate = true;
                validationError = null;
              });
              try {
                final snapshot = await FirebaseFirestore.instance
                    .collection('rubric_templates')
                    .get();
                final templates =
                    snapshot.docs.where((doc) {
                      final data = doc.data();
                      return data['archived'] != true &&
                          data['csvChunkCount'] is num &&
                          (data['csvChunkCount'] as num) > 0;
                    }).toList()..sort((first, second) {
                      final firstDate = first.data()['createdAt'];
                      final secondDate = second.data()['createdAt'];
                      if (firstDate is Timestamp && secondDate is Timestamp) {
                        return secondDate.compareTo(firstDate);
                      }
                      return 0;
                    });
                if (!context.mounted) return;
                if (templates.isEmpty) {
                  setState(
                    () => validationError =
                        'No rubric CSV templates are available from the admin portal.',
                  );
                  return;
                }

                final selectedTemplateId = await showDialog<String>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('Choose a portal rubric template'),
                    content: SizedBox(
                      width: 420,
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final template in templates)
                              ListTile(
                                leading: const Icon(Icons.description),
                                title: Text(
                                  template.data()['fileName']?.toString() ??
                                      template.data()['title']?.toString() ??
                                      'Rubric template.csv',
                                ),
                                subtitle: Text(
                                  template.data()['createdBy']?.toString() ??
                                      'Admin portal',
                                ),
                                onTap: () =>
                                    Navigator.pop(dialogContext, template.id),
                              ),
                          ],
                        ),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                );
                if (selectedTemplateId == null || !context.mounted) return;

                final templateRef = FirebaseFirestore.instance
                    .collection('rubric_templates')
                    .doc(selectedTemplateId);
                final template = await templateRef.get();
                final templateData = template.data();
                if (templateData == null ||
                    templateData['archived'] == true ||
                    templateData['csvChunkCount'] is! num) {
                  throw const FormatException(
                    'The selected portal rubric template is no longer available.',
                  );
                }
                final expectedChunks = (templateData['csvChunkCount'] as num)
                    .toInt();
                final chunks = await templateRef
                    .collection('csv_chunks')
                    .orderBy('index')
                    .get();
                if (chunks.docs.length != expectedChunks) {
                  throw const FormatException(
                    'The portal CSV template is incomplete. Ask the administrator to upload it again.',
                  );
                }
                final csv = chunks.docs
                    .map((chunk) => chunk.data()['content'] as String? ?? '')
                    .join();
                final imported = await _readRubricCsv(csv);
                if (!context.mounted) return;
                applyImportedRubric(imported);
              } on FormatException catch (error) {
                if (context.mounted) {
                  setState(
                    () => validationError =
                        'Invalid portal rubric CSV: ${error.message}',
                  );
                }
              } catch (error) {
                if (context.mounted) {
                  setState(
                    () => validationError =
                        'Could not load a rubric from the admin portal: $error',
                  );
                }
              } finally {
                if (context.mounted) {
                  setState(() => isLoadingRubricTemplate = false);
                }
              }
            }

            void addRow() {
              setState(() {
                if (selectedType == 'Holistic') {
                  rows.add({
                    'points': TextEditingController(),
                    'desc': TextEditingController(),
                  });
                } else {
                  analyticRows.add({
                    'title': TextEditingController(),
                    'score': TextEditingController(),
                    'levels': List.generate(
                      levelCount,
                      (_) => TextEditingController(),
                    ),
                  });
                }
              });
            }

            void removeRow() {
              final activeRows = selectedType == 'Holistic'
                  ? rows
                  : analyticRows;
              if (activeRows.length <= 1) return;
              setState(() {
                final last = activeRows.removeLast();
                if (selectedType == 'Holistic') {
                  for (var controller
                      in (last as Map<String, TextEditingController>).values) {
                    controller.dispose();
                  }
                } else {
                  (last['title'] as TextEditingController).dispose();
                  (last['score'] as TextEditingController).dispose();
                  for (final controller
                      in last['levels'] as List<TextEditingController>) {
                    controller.dispose();
                  }
                }
              });
            }

            void addLevel() {
              if (levelCount >= 5) return;
              setState(() {
                levelCount++;
                for (final row in analyticRows) {
                  (row['levels'] as List<TextEditingController>).add(
                    TextEditingController(),
                  );
                }
              });
            }

            void removeLevel() {
              if (levelCount <= 1) return;
              setState(() {
                levelCount--;
                for (final row in analyticRows) {
                  (row['levels'] as List<TextEditingController>)
                      .removeLast()
                      .dispose();
                }
              });
            }

            Widget rubricInputCell(
              TextEditingController controller, {
              bool multiline = false,
              bool numeric = false,
            }) {
              return TextField(
                controller: controller,
                minLines: multiline && isCompact ? 2 : 1,
                maxLines: multiline ? null : 1,
                keyboardType: multiline
                    ? TextInputType.multiline
                    : numeric
                    ? const TextInputType.numberWithOptions(decimal: true)
                    : TextInputType.text,
                textAlignVertical: multiline
                    ? TextAlignVertical.top
                    : TextAlignVertical.center,
                onChanged: (_) {
                  if (validationError != null) {
                    setState(() => validationError = null);
                  }
                },
                decoration: InputDecoration(
                  isDense: true,
                  filled: false,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 9,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                ),
              );
            }

            Widget responsiveRubricTable(Table table) {
              if (!isCompact) return table;
              final availableWidth = MediaQuery.sizeOf(context).width - 32;
              return SizedBox(width: availableWidth, child: table);
            }

            Widget holisticRubricTable() {
              return responsiveRubricTable(
                Table(
                  border: TableBorder.symmetric(
                    outside: const BorderSide(
                      color: Color(0xFF8F7C5F),
                      width: 1.2,
                    ),
                    inside: BorderSide(
                      color: const Color(0xFF8F7C5F).withValues(alpha: 0.65),
                      width: 0.8,
                    ),
                  ),
                  columnWidths: {
                    0: const IntrinsicColumnWidth(flex: 1),
                    1: const FlexColumnWidth(3),
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
                    ...rows.map(
                      (row) => TableRow(
                        decoration: const BoxDecoration(
                          color: Color(0xFFE6D6B8),
                        ),
                        children: [
                          rubricInputCell(row['points']!, numeric: true),
                          rubricInputCell(row['desc']!, multiline: true),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }

            Widget analyticRubricTable() {
              return responsiveRubricTable(
                Table(
                  border: TableBorder.symmetric(
                    outside: const BorderSide(
                      color: Color(0xFF8F7C5F),
                      width: 1.2,
                    ),
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
                          child: Text(
                            'Criterion',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        for (var index = 0; index < levelCount; index++)
                          Padding(
                            padding: const EdgeInsets.all(6),
                            child: Text(
                              '${index + 1}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        const Padding(
                          padding: EdgeInsets.all(6),
                          child: Text(
                            'Score',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    ...analyticRows.map((row) {
                      final levels =
                          row['levels'] as List<TextEditingController>;
                      return TableRow(
                        decoration: const BoxDecoration(
                          color: Color(0xFFE6D6B8),
                        ),
                        children: [
                          rubricInputCell(
                            row['title'] as TextEditingController,
                          ),
                          for (final controller in levels)
                            rubricInputCell(controller, multiline: true),
                          rubricInputCell(
                            row['score'] as TextEditingController,
                            numeric: true,
                          ),
                        ],
                      );
                    }),
                  ],
                ),
              );
            }

            List<Map<String, dynamic>> analyticCriteria() {
              return analyticRows
                  .asMap()
                  .entries
                  .map((entry) {
                    final index = entry.key;
                    final row = entry.value;
                    return <String, dynamic>{
                      'title': (row['title'] as TextEditingController).text
                          .trim(),
                      'score': (row['score'] as TextEditingController).text
                          .trim(),
                      'levels': (row['levels'] as List<TextEditingController>)
                          .map((controller) => controller.text.trim())
                          .toList(),
                      '_defaultTitle': 'Criterion ${index + 1}',
                    };
                  })
                  .where((criterion) {
                    final title = criterion['title'] as String;
                    final levels = criterion['levels'] as List<String>;
                    return title != criterion['_defaultTitle'] ||
                        (criterion['score'] as String).isNotEmpty ||
                        levels.any((level) => level.isNotEmpty);
                  })
                  .map((criterion) {
                    criterion.remove('_defaultTitle');
                    return criterion;
                  })
                  .toList();
            }

            Map<String, dynamic> currentRubric() => {
              'title': titleController.text.trim(),
              'type': selectedType,
              if (standardsController.text.trim().isNotEmpty)
                'curriculumStandards': {
                  'criterion_1': standardsController.text
                      .split(',')
                      .map((value) => value.trim())
                      .where((value) => value.isNotEmpty)
                      .toList(),
                },
              if (selectedType == 'Analytic') 'levelCount': levelCount,
              'criteria': selectedType == 'Holistic'
                  ? rows
                        .map(
                          (row) => <String, dynamic>{
                            'points': row['points']!.text.trim(),
                            'description': row['desc']!.text.trim(),
                          },
                        )
                        .where(
                          (criterion) =>
                              criterion['points']!.isNotEmpty ||
                              criterion['description']!.isNotEmpty,
                        )
                        .toList()
                  : analyticCriteria(),
            };

            String? validateRubric(Map<String, dynamic> rubric) {
              final type = rubric['type'];
              if (type != 'Holistic' && type != 'Analytic') {
                return 'Choose either a Holistic or Analytic rubric.';
              }
              final criteria = rubric['criteria'];
              if (criteria is! List || criteria.isEmpty) {
                return 'Add at least one rubric criterion.';
              }
              for (final criterion in criteria) {
                if (criterion is! Map) {
                  return 'Each rubric criterion must be valid.';
                }
                if (type == 'Holistic') {
                  final points = criterion['points']?.toString().trim() ?? '';
                  final description =
                      criterion['description']?.toString().trim() ?? '';
                  if (points.isEmpty ||
                      double.tryParse(points) == null ||
                      description.isEmpty) {
                    return 'Holistic criteria need numeric points and descriptions.';
                  }
                } else {
                  final title = criterion['title']?.toString().trim() ?? '';
                  final levels = criterion['levels'];
                  final score = criterion['score']?.toString().trim() ?? '';
                  if (title.isEmpty ||
                      levels is! List ||
                      levels.isEmpty ||
                      levels.any((level) => level.toString().trim().isEmpty)) {
                    return 'Analytic criteria need a title and completed levels.';
                  }
                  if (score.isNotEmpty && double.tryParse(score) == null) {
                    return 'Analytic criterion scores must be numeric.';
                  }
                }
              }
              return null;
            }

            return PopScope<bool>(
              onPopInvokedWithResult: (didPop, result) {
                if (didPop) latestRubric = currentRubric();
              },
              child: Scaffold(
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
                            const Expanded(
                              child: VisionGradeWordmark(fontSize: 22),
                            ),
                            UserProfileAvatar(
                              role: role,
                              userEmail: instructorEmail,
                              profileImageUrl: profileImageUrl,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppPalette.burgundy,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(
                                width: 34,
                                height: 40,
                              ),
                              onPressed: () => Navigator.of(context).pop(),
                              icon: Image.asset(
                                'white_curved_back_arrow.png',
                                width: 18,
                                height: 18,
                                fit: BoxFit.contain,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Create rubrics',
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  const SizedBox(width: 48),
                                  const Expanded(
                                    child: Center(
                                      child: Text(
                                        'Create rubrics',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
                                    icon: Image.asset(
                                      'white_curved_back_arrow.png',
                                      width: 16,
                                      height: 16,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Text('Rubrics Title'),
                              const SizedBox(height: 6),
                              TextField(
                                controller: titleController,
                                decoration: const InputDecoration(
                                  hintText: 'title.....',
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: standardsController,
                                decoration: const InputDecoration(
                                  labelText:
                                      'Curriculum keywords or key phrases',
                                  hintText:
                                      'e.g. photosynthesis, evidence, conclusion',
                                  helperText:
                                      'Separate terms with commas. They are shown as matched or missing evidence.',
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(child: Container()),
                                  const SizedBox(width: 8),
                                  DropdownButton<String>(
                                    value: selectedType,
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'Analytic',
                                        child: Text('Analytic'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'Holistic',
                                        child: Text('Holistic'),
                                      ),
                                    ],
                                    onChanged: (v) => setState(
                                      () => selectedType = v ?? 'Holistic',
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                '$selectedType rubric',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              selectedType == 'Holistic'
                                  ? holisticRubricTable()
                                  : analyticRubricTable(),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  if (selectedType == 'Analytic') ...[
                                    TextButton.icon(
                                      onPressed: levelCount < 5
                                          ? addLevel
                                          : null,
                                      icon: const Icon(Icons.add),
                                      label: const Text('Add Level'),
                                    ),
                                    TextButton.icon(
                                      onPressed: levelCount > 1
                                          ? removeLevel
                                          : null,
                                      icon: const Icon(Icons.remove),
                                      label: const Text('Remove Level'),
                                    ),
                                  ],
                                  TextButton.icon(
                                    onPressed: addRow,
                                    icon: const Icon(Icons.add),
                                    label: const Text('Add Row'),
                                  ),
                                  TextButton.icon(
                                    onPressed: removeRow,
                                    icon: const Icon(Icons.delete),
                                    label: const Text('Remove Row'),
                                  ),
                                  ElevatedButton.icon(
                                    onPressed: () async {
                                      final result = await FilePicker.platform
                                          .pickFiles(
                                            withData: true,
                                            type: FileType.any,
                                          );
                                      if (result == null ||
                                          result.files.isEmpty) {
                                        return;
                                      }
                                      final file = result.files.single;
                                      final extension = file.name
                                          .split('.')
                                          .last
                                          .toLowerCase();
                                      if (!const {
                                        'csv',
                                        'pdf',
                                        'doc',
                                        'docx',
                                        'txt',
                                      }.contains(extension)) {
                                        setState(
                                          () => validationError =
                                              'Choose a CSV, PDF, DOCX, or TXT file.',
                                        );
                                        return;
                                      }
                                      if (file.bytes == null) {
                                        setState(
                                          () => validationError =
                                              'The selected file could not be read. Try saving it on your device first.',
                                        );
                                        return;
                                      }
                                      try {
                                        final imported =
                                            await _readRubricDocument(
                                              file.bytes!,
                                              file.name,
                                            );
                                        applyImportedRubric(imported);
                                      } on FormatException catch (error) {
                                        setState(
                                          () => validationError =
                                              'Invalid rubric file: ${error.message}',
                                        );
                                      } catch (error) {
                                        setState(
                                          () => validationError =
                                              'Could not load rubric file: $error',
                                        );
                                      }
                                    },
                                    icon: const Icon(Icons.upload_file),
                                    label: const Text('Upload CSV / Document'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.grey.shade400,
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: isLoadingRubricTemplate
                                        ? null
                                        : importPortalRubric,
                                    icon: isLoadingRubricTemplate
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.cloud_download),
                                    label: const Text('Load from Admin Portal'),
                                  ),
                                ],
                              ),
                              const Padding(
                                padding: EdgeInsets.only(top: 4, left: 4),
                                child: Text(
                                  'CSV columns: holistic uses Points and '
                                  'Description; analytic uses Criterion, '
                                  'Level 1-5, and optional Score. Type and '
                                  'Title columns are optional.',
                                  style: TextStyle(
                                    color: AppPalette.muted,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              if (validationError != null) ...[
                                const SizedBox(height: 8),
                                _validationMessage(validationError!),
                              ],
                              const SizedBox(height: 12),
                              Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: () {
                                      final updatedDraft = DraftItem(
                                        type: 'Task',
                                        title: taskTitle.trim().isEmpty
                                            ? 'Untitled task'
                                            : taskTitle.trim(),
                                        body: taskBody.trim(),
                                        subjectTitle: subject.title,
                                        createdAt: draftIndex == null
                                            ? DateTime.now()
                                            : DraftStore
                                                  .items[draftIndex]
                                                  .createdAt,
                                        rubric: currentRubric(),
                                        attachmentName: attachmentName,
                                        attachmentUrl: attachmentUrl,
                                      );
                                      if (draftIndex == null) {
                                        DraftStore.add(updatedDraft);
                                      } else {
                                        DraftStore.update(
                                          draftIndex,
                                          updatedDraft,
                                        );
                                      }
                                      Navigator.of(context).pop();
                                      scaffoldMessenger.showSnackBar(
                                        const SnackBar(
                                          content: Text('Task saved to drafts'),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.save),
                                    label: const Text('Save Draft'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF441B35),
                                      foregroundColor: const Color(0xFFE8D8C1),
                                    ),
                                  ),
                                  ElevatedButton(
                                    onPressed: isPosting
                                        ? null
                                        : () async {
                                            if (taskTitle.trim().isEmpty ||
                                                (taskBody.trim().isEmpty &&
                                                    !hasPdfAttachment &&
                                                    !_isHttpUrl(
                                                      attachmentUrl ?? '',
                                                    ))) {
                                              setState(
                                                () => validationError =
                                                    'Enter a task title and description, or attach a PDF or link.',
                                              );
                                              return;
                                            }
                                            if (dueDate != null &&
                                                !isTaskDeadlineValid(dueDate)) {
                                              setState(
                                                () => validationError =
                                                    'Choose a deadline later today or on a future date.',
                                              );
                                              return;
                                            }
                                            final rubric = currentRubric();
                                            final rubricError = validateRubric(
                                              rubric,
                                            );
                                            if (rubricError != null) {
                                              setState(
                                                () => validationError =
                                                    rubricError,
                                              );
                                              return;
                                            }
                                            final criteria =
                                                rubric['criteria']
                                                    as List<
                                                      Map<String, dynamic>
                                                    >;
                                            if (criteria.isEmpty) {
                                              setState(
                                                () => validationError =
                                                    selectedType == 'Analytic'
                                                    ? 'Complete at least one analytic criterion before posting.'
                                                    : 'Add at least one rubric criterion before posting.',
                                              );
                                              return;
                                            }
                                            if (selectedType == 'Analytic' &&
                                                criteria.any((criterion) {
                                                  final levels =
                                                      criterion['levels']
                                                          as List<String>;
                                                  return (criterion['title']
                                                              as String)
                                                          .isEmpty ||
                                                      levels.any(
                                                        (level) =>
                                                            level.isEmpty,
                                                      );
                                                })) {
                                              setState(
                                                () => validationError =
                                                    'Fill in the criterion title and every level description before posting.',
                                              );
                                              return;
                                            }
                                            setState(() {
                                              isPosting = true;
                                              validationError = null;
                                            });
                                            try {
                                              if (postId == null) {
                                                await FirestoreService.publishPost(
                                                  subjectId: subject.id,
                                                  subjectTitle: subject.title,
                                                  type: 'Task',
                                                  title: taskTitle.trim(),
                                                  body: taskBody.trim(),
                                                  posterName: instructorName,
                                                  posterEmail: instructorEmail,
                                                  allowUpload: allowUpload,
                                                  closeAfterDeadline:
                                                      closeAfterDeadline,
                                                  dueDate: dueDate
                                                      ?.toIso8601String(),
                                                  targetStudentEmails:
                                                      targetStudentEmails,
                                                  targetStudentNames:
                                                      targetStudentNames,
                                                  attachmentName:
                                                      attachmentName,
                                                  attachmentUrl: attachmentUrl,
                                                  rubric: rubric,
                                                );
                                              } else {
                                                await FirestoreService.updatePost(
                                                  subjectId: subject.id,
                                                  postId: postId,
                                                  title: taskTitle.trim(),
                                                  body: taskBody.trim(),
                                                  allowUpload: allowUpload,
                                                  closeAfterDeadline:
                                                      closeAfterDeadline,
                                                  dueDate: dueDate
                                                      ?.toIso8601String(),
                                                  targetStudentEmails:
                                                      targetStudentEmails,
                                                  targetStudentNames:
                                                      targetStudentNames,
                                                  attachmentName:
                                                      attachmentName,
                                                  attachmentUrl: attachmentUrl,
                                                  rubric: rubric,
                                                  updateTaskFields: true,
                                                );
                                              }
                                              if (!context.mounted) return;
                                              navigator.pop(true);
                                              scaffoldMessenger.showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    postId == null
                                                        ? 'Task posted'
                                                        : 'Task updated',
                                                  ),
                                                ),
                                              );
                                            } on FirebaseException catch (
                                              error
                                            ) {
                                              if (!context.mounted) return;
                                              setState(() {
                                                isPosting = false;
                                                validationError =
                                                    'Could not post task (${error.code}): ${error.message ?? 'Please try again.'}';
                                              });
                                            } catch (error) {
                                              if (!context.mounted) return;
                                              setState(() {
                                                isPosting = false;
                                                validationError =
                                                    'Could not post task: $error';
                                              });
                                            }
                                          },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppPalette.rose,
                                      foregroundColor: Colors.black,
                                    ),
                                    child: Text(
                                      isPosting ? 'Posting...' : 'Post Task',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                bottomNavigationBar: DashboardBottomNavigation(
                  role: role,
                  homeIsActive: false,
                  userName: instructorName,
                  userEmail: instructorEmail,
                  profileImageUrl: profileImageUrl,
                ),
              ),
            );
          },
        );
      },
    );
    final rubricSaved = await navigator.push<bool>(rubricRoute);
    await rubricRoute.completed;
    titleController.dispose();
    for (final row in rows) {
      for (final controller in row.values) {
        controller.dispose();
      }
    }
    for (final row in analyticRows) {
      (row['title'] as TextEditingController).dispose();
      (row['score'] as TextEditingController).dispose();
      for (final controller in row['levels'] as List<TextEditingController>) {
        controller.dispose();
      }
    }
    return (saved: rubricSaved ?? false, rubric: latestRubric);
  }

  Widget _buildTopBar(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      height: 54,
      child: Row(
        children: [
          const SizedBox(width: 8),
          Expanded(child: const VisionGradeWordmark(fontSize: 22)),
          UserProfileAvatar(
            role: role,
            userEmail: role == UserRole.instructor
                ? instructorEmail
                : studentEmail,
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
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
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
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subject.title,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subject.gradeLabel,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildSubjectTabs(context),
        ],
      ),
    );
  }

  Widget _buildSubjectTabs(BuildContext context) {
    final controller = DefaultTabController.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _subjectTab(
                    controller: controller,
                    index: 0,
                    label: 'Classroom',
                  ),
                  const SizedBox(width: 16),
                  _subjectTab(
                    controller: controller,
                    index: 1,
                    label: 'Classworks',
                  ),
                  const SizedBox(width: 16),
                  _subjectTab(
                    controller: controller,
                    index: 2,
                    label: 'People',
                    icon: Icons.people_outline,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _subjectTab({
    required TabController controller,
    required int index,
    required String label,
    IconData? icon,
  }) {
    final selected = controller.index == index;
    return GestureDetector(
      onTap: () => controller.animateTo(index),
      child: Container(
        width: 98,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppPalette.burgundyDark : AppPalette.cream,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                color: selected ? Colors.white : AppPalette.ink,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : AppPalette.ink,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Classroom tab UI, contains action pills, announcement and assignment cards.
class ClassroomTab extends StatelessWidget {
  final Subject subject;
  final UserRole role;
  final String instructorName;
  final String instructorEmail;
  final String studentName;
  final String studentEmail;
  final String? profileImageUrl;

  const ClassroomTab({
    super.key,
    required this.subject,
    required this.role,
    this.instructorName = 'Instructor',
    this.instructorEmail = '',
    this.studentName = '',
    this.studentEmail = '',
    this.profileImageUrl,
  });

  static const Color beige = AppPalette.cream;

  @override
  Widget build(BuildContext context) {
    final email = role == UserRole.instructor ? instructorEmail : studentEmail;
    return RefreshIndicator(
      onRefresh: () => FirestoreService.refreshSubjectContent(
        subjectId: subject.id,
        role: role == UserRole.instructor ? 'instructor' : 'student',
        email: email,
        authUid: FirebaseAuth.instance.currentUser?.uid ?? '',
      ),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(6, 12, 6, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (role == UserRole.instructor) ...[
              _buildActionPills(context),
              const SizedBox(height: 8),
            ],
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirestoreService.subjectPostsStream(subject.id),
              builder: (context, snapshot) {
                return StreamBuilder<
                  List<QueryDocumentSnapshot<Map<String, dynamic>>>
                >(
                  stream: FirestoreService.globalAnnouncementsStream(
                    email: email,
                    role: role == UserRole.instructor
                        ? 'instructor'
                        : 'student',
                    authUid: FirebaseAuth.instance.currentUser?.uid ?? '',
                  ),
                  builder: (context, globalSnapshot) {
                    if (snapshot.hasError || globalSnapshot.hasError) {
                      return const Padding(
                        padding: EdgeInsets.only(top: 24),
                        child: Center(
                          child: Text(
                            'Unable to load classroom announcements.',
                          ),
                        ),
                      );
                    }
                    final subjectPosts = (snapshot.data?.docs ?? const [])
                        .where((post) {
                          final data = post.data();
                          if (data['type'] == 'Announcement') {
                            return role == UserRole.instructor ||
                                isTaskVisibleToStudent(data, studentEmail);
                          }
                          if (data['type'] != 'Task') return false;
                          if (role == UserRole.instructor) return true;
                          return isTaskVisibleToStudent(data, studentEmail);
                        });
                    final posts = sortPostsNewestFirst([
                      ...subjectPosts,
                      ...(globalSnapshot.data ?? const []),
                    ]);

                    if (posts.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.only(top: 24),
                        child: Center(
                          child: Text('No posts have been published yet.'),
                        ),
                      );
                    }

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: posts.map((post) {
                        final isAnnouncement =
                            post.data()['type'] == 'Announcement';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: isAnnouncement
                              ? _buildAnnouncementCard(context, post)
                              : _buildTaskCard(context, post),
                        );
                      }).toList(),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionPills(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: _actionPill(
              label: 'Post Announcement',
              icon: Icons.edit,
              onTap: () => _showPostAnnouncementPage(context),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _actionPill(
              label: 'Add Task',
              icon: Icons.add_circle_outline,
              onTap: () => _showAddTaskPage(context),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _actionPill(
              label: 'Saved Drafts',
              icon: Icons.save_outlined,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (c) => SavedDraftPage(
                      role: role,
                      userName: '',
                      profileImageUrl: profileImageUrl,
                      onEdit: (editContext, draft, draftIndex) {
                        if (draft.type == 'Announcement') {
                          return _showPostAnnouncementPage(
                            editContext,
                            draft: draft,
                            draftIndex: draftIndex,
                          );
                        }
                        return _showAddTaskPage(
                          editContext,
                          draft: draft,
                          draftIndex: draftIndex,
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionPill({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF5A5A55),
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Color(0x30000000),
                blurRadius: 3,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 14, color: AppPalette.cream),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      color: AppPalette.cream,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showPostAnnouncementPage(
    BuildContext context, {
    DraftItem? draft,
    int? draftIndex,
  }) async {
    final titleController = TextEditingController(text: draft?.title ?? '');
    final bodyController = TextEditingController(text: draft?.body ?? '');
    String? attachmentName = draft?.attachmentName;
    String? attachmentUrl = draft?.attachmentUrl;
    bool uploadingAttachment = false;
    bool isPosting = false;
    String? validationError;

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => StatefulBuilder(
          builder: (context, setState) => Scaffold(
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
                        const Expanded(
                          child: VisionGradeWordmark(fontSize: 22),
                        ),
                        UserProfileAvatar(
                          role: role,
                          userEmail: instructorEmail,
                          profileImageUrl: profileImageUrl,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppPalette.burgundy,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 34,
                            height: 40,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                          icon: Image.asset(
                            'white_curved_back_arrow.png',
                            width: 18,
                            height: 18,
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Post Announcement',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: titleController,
                            onChanged: (_) {
                              if (validationError != null) {
                                setState(() => validationError = null);
                              }
                            },
                            decoration: const InputDecoration(
                              hintText: 'Announcement Title',
                              filled: true,
                              fillColor: AppPalette.cream,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.all(
                                  Radius.circular(14),
                                ),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: bodyController,
                            minLines: 7,
                            maxLines: 10,
                            onChanged: (_) {
                              if (validationError != null) {
                                setState(() => validationError = null);
                              }
                            },
                            decoration: const InputDecoration(
                              hintText: 'Write your announcement here......',
                              filled: true,
                              fillColor: AppPalette.cream,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.all(
                                  Radius.circular(14),
                                ),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: ElevatedButton.icon(
                              onPressed: uploadingAttachment
                                  ? null
                                  : () async {
                                      final result = await FilePicker.platform
                                          .pickFiles(
                                            withData: true,
                                            type: FileType.any,
                                          );
                                      if (result == null ||
                                          result.files.isEmpty) {
                                        return;
                                      }
                                      final file = result.files.single;
                                      final extension = file.name
                                          .split('.')
                                          .last
                                          .toLowerCase();
                                      if (!_instructionFileExtensions.contains(
                                        extension,
                                      )) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Choose a PDF, Excel, or CSV file.',
                                              ),
                                            ),
                                          );
                                        }
                                        return;
                                      }
                                      if (file.bytes == null) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'This file could not be read.',
                                              ),
                                            ),
                                          );
                                        }
                                        return;
                                      }
                                      setState(
                                        () => uploadingAttachment = true,
                                      );
                                      try {
                                        final safeName = file.name.replaceAll(
                                          RegExp(r'[/\\"]'),
                                          '_',
                                        );
                                        final storageRef = FirebaseStorage
                                            .instance
                                            .ref()
                                            .child(
                                              'announcements/${subject.id}/${DateTime.now().millisecondsSinceEpoch}_$safeName',
                                            );
                                        final contentType = switch (extension) {
                                          'pdf' => 'application/pdf',
                                          'xls' => 'application/vnd.ms-excel',
                                          'xlsx' =>
                                            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                                          'csv' => 'text/csv',
                                          _ => throw FormatException(
                                            'Unsupported attachment type: $extension',
                                          ),
                                        };
                                        final snapshot = await storageRef.putData(
                                          file.bytes!,
                                          SettableMetadata(
                                            contentType: contentType,
                                            contentDisposition:
                                                extension == 'pdf'
                                                ? 'inline; filename="$safeName"'
                                                : 'attachment; filename="$safeName"',
                                          ),
                                        );
                                        attachmentName = file.name;
                                        attachmentUrl = await snapshot.ref
                                            .getDownloadURL();
                                        if (context.mounted) {
                                          setState(() {});
                                        }
                                      } catch (error) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Upload failed: $error',
                                              ),
                                            ),
                                          );
                                        }
                                      } finally {
                                        if (context.mounted) {
                                          setState(
                                            () => uploadingAttachment = false,
                                          );
                                        }
                                      }
                                    },
                              icon: const Icon(Icons.attach_file, size: 15),
                              label: Text(
                                uploadingAttachment
                                    ? 'Uploading...'
                                    : attachmentName ?? 'Add attachment',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF8A887C),
                                foregroundColor: AppPalette.cream,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                minimumSize: const Size(0, 30),
                                shape: const StadiumBorder(),
                                textStyle: const TextStyle(fontSize: 10),
                              ),
                            ),
                          ),
                          if (validationError != null) ...[
                            const SizedBox(height: 8),
                            _validationMessage(validationError!),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: uploadingAttachment
                                      ? null
                                      : () async {
                                          final updatedDraft = DraftItem(
                                            type: 'Announcement',
                                            title:
                                                titleController.text
                                                    .trim()
                                                    .isEmpty
                                                ? 'Untitled announcement'
                                                : titleController.text.trim(),
                                            body: bodyController.text.trim(),
                                            subjectTitle: subject.title,
                                            createdAt:
                                                draft?.createdAt ??
                                                DateTime.now(),
                                            attachmentName: attachmentName,
                                            attachmentUrl: attachmentUrl,
                                          );
                                          if (draftIndex == null) {
                                            DraftStore.add(updatedDraft);
                                          } else {
                                            DraftStore.update(
                                              draftIndex,
                                              updatedDraft,
                                            );
                                          }
                                          if (!context.mounted) return;
                                          Navigator.of(context).pop();
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Announcement saved to drafts',
                                              ),
                                            ),
                                          );
                                        },
                                  icon: const Icon(Icons.save),
                                  label: const Text('Save Draft'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF441B35),
                                    foregroundColor: const Color(0xFFE8D8C1),
                                    shape: const StadiumBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: isPosting || uploadingAttachment
                                      ? null
                                      : () async {
                                          if (titleController.text
                                                  .trim()
                                                  .isEmpty ||
                                              bodyController.text
                                                  .trim()
                                                  .isEmpty) {
                                            setState(
                                              () => validationError =
                                                  'Enter an announcement title and message before posting.',
                                            );
                                            return;
                                          }
                                          if (uploadingAttachment) return;
                                          setState(() => isPosting = true);
                                          try {
                                            await FirestoreService.publishPost(
                                              subjectId: subject.id,
                                              subjectTitle: subject.title,
                                              type: 'Announcement',
                                              title: titleController.text
                                                  .trim(),
                                              body: bodyController.text.trim(),
                                              posterName: instructorName,
                                              posterEmail: instructorEmail,
                                              attachmentName: attachmentName,
                                              attachmentUrl: attachmentUrl,
                                            );
                                            if (!context.mounted) return;
                                            Navigator.of(context).pop();
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Announcement posted',
                                                ),
                                              ),
                                            );
                                          } catch (error) {
                                            if (!context.mounted) return;
                                            setState(() => isPosting = false);
                                            setState(
                                              () => validationError =
                                                  'Could not post announcement: $error',
                                            );
                                          }
                                        },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppPalette.rose,
                                    foregroundColor: Colors.black,
                                    shape: const StadiumBorder(),
                                  ),
                                  child: Text(
                                    isPosting ? 'Posting...' : 'Post Now',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            bottomNavigationBar: DashboardBottomNavigation(
              role: role,
              homeIsActive: false,
              userName: instructorName,
              userEmail: instructorEmail,
              profileImageUrl: profileImageUrl,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showAddTaskPage(
    BuildContext context, {
    DraftItem? draft,
    int? draftIndex,
    QueryDocumentSnapshot<Map<String, dynamic>>? taskPost,
  }) async {
    final taskData = taskPost?.data();
    final titleController = TextEditingController(
      text: draft?.title ?? taskData?['title'] as String? ?? '',
    );
    final bodyController = TextEditingController(
      text: draft?.body ?? taskData?['body'] as String? ?? '',
    );
    DateTime? dueDate = _taskDateFromValue(taskData?['dueDate']);
    bool allowUpload = taskData?['allowUpload'] as bool? ?? false;
    bool closeAfterDeadline =
        dueDate != null && (taskData?['closeAfterDeadline'] as bool? ?? true);
    final targetStudentEmails = <String>[
      ...((taskData?['targetStudentEmails'] as List?)?.whereType<String>() ??
          const <String>[]),
    ];
    final targetStudentNames = <String>[
      ...((taskData?['targetStudentNames'] as List?)?.whereType<String>() ??
          const <String>[]),
    ];
    final legacyEmail = taskData?['targetStudentEmail'] as String?;
    final legacyName = taskData?['targetStudentName'] as String?;
    if (targetStudentEmails.isEmpty && legacyEmail != null) {
      targetStudentEmails.add(legacyEmail);
      if (legacyName != null) targetStudentNames.add(legacyName);
    }
    bool assignToAll = targetStudentEmails.isEmpty;
    String? attachmentName =
        draft?.attachmentName ?? taskData?['attachmentName'] as String?;
    String? attachmentUrl =
        draft?.attachmentUrl ?? taskData?['attachmentUrl'] as String?;
    Map<String, dynamic>? pendingRubric =
        draft?.rubric ?? taskData?['rubric'] as Map<String, dynamic>?;
    bool uploadingAttachment = false;
    String? validationError;

    bool hasPdfAttachment() {
      final fileName = attachmentName?.trim().toLowerCase() ?? '';
      return fileName.endsWith('.pdf') &&
          (attachmentUrl?.trim().isNotEmpty ?? false);
    }

    final shouldCreateRubric = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setState) {
              final isCompact = MediaQuery.sizeOf(context).width < 600;
              final dueDateField = InkWell(
                onTap: () async {
                  final now = DateTime.now();
                  final pickedDate = await showDatePicker(
                    context: context,
                    initialDate:
                        dueDate != null &&
                            !dueDate!.isBefore(
                              DateTime(now.year, now.month, now.day),
                            )
                        ? dueDate!
                        : now,
                    firstDate: DateTime(now.year, now.month, now.day),
                    lastDate: DateTime(2100),
                  );
                  if (pickedDate == null || !context.mounted) return;
                  final pickedTime = await showTimePicker(
                    context: context,
                    initialTime: dueDate != null
                        ? TimeOfDay.fromDateTime(dueDate!)
                        : TimeOfDay.fromDateTime(
                            now.add(const Duration(hours: 1)),
                          ),
                  );
                  if (pickedTime == null) return;
                  final selected = DateTime(
                    pickedDate.year,
                    pickedDate.month,
                    pickedDate.day,
                    pickedTime.hour,
                    pickedTime.minute,
                  );
                  if (!isTaskDeadlineValid(selected)) {
                    setState(
                      () => validationError =
                          'Choose a deadline later today or on a future date.',
                    );
                    return;
                  }
                  setState(() {
                    dueDate = selected;
                    validationError = null;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAF8F5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppPalette.burgundy.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_month_outlined,
                        color: AppPalette.burgundy,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              dueDate != null
                                  ? _formatTaskDueDateTime(dueDate!.toLocal())
                                  : 'Set deadline',
                              style: const TextStyle(
                                color: AppPalette.ink,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (dueDate == null)
                              const Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Text(
                                  'Tap to choose a due date and time (optional)',
                                  style: TextStyle(
                                    color: AppPalette.muted,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (dueDate != null)
                        IconButton(
                          onPressed: () => setState(() {
                            dueDate = null;
                            closeAfterDeadline = false;
                            validationError = null;
                          }),
                          icon: const Icon(Icons.close),
                          tooltip: 'Remove due date',
                          visualDensity: VisualDensity.compact,
                        )
                      else
                        const Icon(
                          Icons.chevron_right,
                          color: AppPalette.muted,
                        ),
                    ],
                  ),
                ),
              );
              final uploadToggle = Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Allow Upload'),
                    Switch(
                      value: allowUpload,
                      onChanged: (value) => setState(() => allowUpload = value),
                    ),
                  ],
                ),
              );
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
                            const Expanded(
                              child: VisionGradeWordmark(fontSize: 22),
                            ),
                            UserProfileAvatar(
                              role: role,
                              userEmail: role == UserRole.instructor
                                  ? instructorEmail
                                  : studentEmail,
                              profileImageUrl: profileImageUrl,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppPalette.burgundy,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(
                                width: 34,
                                height: 40,
                              ),
                              onPressed: () => Navigator.of(context).pop(),
                              icon: Image.asset(
                                'white_curved_back_arrow.png',
                                width: 18,
                                height: 18,
                                fit: BoxFit.contain,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                taskPost == null ? 'Assign Task' : 'Edit Task',
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _InlineStudentPicker(
                                subject: subject,
                                selectedEmails: targetStudentEmails,
                                selectedNames: targetStudentNames,
                                assignToAll: assignToAll,
                                onStudentSelected: (student) => setState(() {
                                  if (targetStudentEmails.any(
                                    (email) =>
                                        email.toLowerCase() ==
                                        student.email.toLowerCase(),
                                  )) {
                                    return;
                                  }
                                  assignToAll = false;
                                  targetStudentEmails.add(student.email);
                                  targetStudentNames.add(student.name);
                                  validationError = null;
                                }),
                                onStudentRemoved: (email) => setState(() {
                                  final index = targetStudentEmails.indexWhere(
                                    (value) =>
                                        value.toLowerCase() ==
                                        email.toLowerCase(),
                                  );
                                  if (index >= 0) {
                                    targetStudentEmails.removeAt(index);
                                    if (index < targetStudentNames.length) {
                                      targetStudentNames.removeAt(index);
                                    }
                                  }
                                }),
                                onAssignToAllChanged: (value) => setState(() {
                                  assignToAll = value;
                                  if (value) {
                                    targetStudentEmails.clear();
                                    targetStudentNames.clear();
                                    validationError = null;
                                  }
                                }),
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: titleController,
                                onChanged: (_) {
                                  if (validationError != null) {
                                    setState(() => validationError = null);
                                  }
                                },
                                decoration: const InputDecoration(
                                  hintText: 'Task Title',
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (isCompact) ...[
                                dueDateField,
                                const SizedBox(height: 8),
                                uploadToggle,
                              ] else
                                Row(
                                  children: [
                                    Expanded(child: dueDateField),
                                    const SizedBox(width: 8),
                                    uploadToggle,
                                  ],
                                ),
                              const SizedBox(height: 8),
                              Container(
                                margin: const EdgeInsets.only(
                                  top: 8,
                                  bottom: 10,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF7EFE7),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: AppPalette.burgundy.withValues(
                                      alpha: 0.16,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.lock_clock_outlined,
                                      color: AppPalette.burgundy,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Text(
                                            'Deadline submissions',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: AppPalette.ink,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            closeAfterDeadline
                                                ? 'Late work is not accepted'
                                                : dueDate == null
                                                ? 'Set a deadline to enable this option'
                                                : 'Late work is accepted',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.black54,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Switch(
                                      value:
                                          dueDate != null && closeAfterDeadline,
                                      onChanged: dueDate == null
                                          ? null
                                          : (value) => setState(
                                              () => closeAfterDeadline = value,
                                            ),
                                      activeTrackColor: AppPalette.burgundy,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ],
                                ),
                              ),
                              TextField(
                                controller: bodyController,
                                minLines: 3,
                                maxLines: 5,
                                onChanged: (_) {
                                  if (validationError != null) {
                                    setState(() => validationError = null);
                                  }
                                },
                                decoration: const InputDecoration(
                                  hintText: 'Task Body',
                                ),
                              ),
                              if (hasPdfAttachment()) ...[
                                const SizedBox(height: 10),
                                Material(
                                  color: const Color(0xFFFAF8F5),
                                  borderRadius: BorderRadius.circular(14),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: () => openTaskAttachment(
                                      context,
                                      url: attachmentUrl!.trim(),
                                      name: attachmentName!,
                                    ),
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: const Color(0xFFD8CBC2),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.picture_as_pdf_outlined,
                                            color: AppPalette.burgundy,
                                            size: 28,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  attachmentName!,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: AppPalette.ink,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                const Text(
                                                  'Tap to review PDF',
                                                  style: TextStyle(
                                                    color: AppPalette.muted,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const Icon(
                                            Icons.open_in_new,
                                            color: AppPalette.muted,
                                            size: 20,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              if (validationError != null) ...[
                                const SizedBox(height: 8),
                                _validationMessage(validationError!),
                              ],
                              const SizedBox(height: 12),
                              Center(
                                child: Column(
                                  children: [
                                    SizedBox(
                                      height: 28,
                                      child: ElevatedButton.icon(
                                        onPressed: uploadingAttachment
                                            ? null
                                            : () async {
                                                final result = await FilePicker
                                                    .platform
                                                    .pickFiles(
                                                      withReadStream: kIsWeb,
                                                      type: FileType.custom,
                                                      allowedExtensions:
                                                          _instructionFileExtensions,
                                                    );
                                                if (result == null ||
                                                    result.files.isEmpty) {
                                                  return;
                                                }
                                                final file =
                                                    result.files.single;
                                                final filePath = kIsWeb
                                                    ? null
                                                    : file.path;
                                                final fileStream =
                                                    file.readStream;
                                                final extension = file.name
                                                    .split('.')
                                                    .last
                                                    .toLowerCase();
                                                if (!_instructionFileExtensions
                                                    .contains(extension)) {
                                                  if (context.mounted) {
                                                    ScaffoldMessenger.of(
                                                      context,
                                                    ).showSnackBar(
                                                      const SnackBar(
                                                        content: Text(
                                                          'Choose a PDF, Excel, or CSV file.',
                                                        ),
                                                      ),
                                                    );
                                                  }
                                                  return;
                                                }
                                                if (kIsWeb
                                                    ? fileStream == null
                                                    : filePath == null) {
                                                  if (context.mounted) {
                                                    ScaffoldMessenger.of(
                                                      context,
                                                    ).showSnackBar(
                                                      const SnackBar(
                                                        content: Text(
                                                          'This file could not be read.',
                                                        ),
                                                      ),
                                                    );
                                                  }
                                                  return;
                                                }
                                                setState(() {
                                                  uploadingAttachment = true;
                                                });
                                                try {
                                                  final safeName = file.name
                                                      .replaceAll(
                                                        RegExp(r'[/\\"]'),
                                                        '_',
                                                      );
                                                  final uploadedUrl = kIsWeb
                                                      ? await CloudinaryService.uploadStream(
                                                          stream: fileStream!,
                                                          length: file.size,
                                                          fileName: safeName,
                                                          resourceType:
                                                              extension == 'pdf'
                                                              ? 'raw'
                                                              : 'auto',
                                                        )
                                                      : await CloudinaryService.uploadFile(
                                                          path: filePath!,
                                                          fileName: safeName,
                                                          resourceType:
                                                              extension == 'pdf'
                                                              ? 'raw'
                                                              : 'auto',
                                                        );
                                                  attachmentName = file.name;
                                                  attachmentUrl = uploadedUrl;
                                                  if (extension == 'pdf') {
                                                    validationError = null;
                                                  }
                                                  if (context.mounted) {
                                                    setState(() {});
                                                    ScaffoldMessenger.of(
                                                      context,
                                                    ).showSnackBar(
                                                      SnackBar(
                                                        content: Text(
                                                          '${file.name} attached to task',
                                                        ),
                                                      ),
                                                    );
                                                  }
                                                } catch (error) {
                                                  if (context.mounted) {
                                                    ScaffoldMessenger.of(
                                                      context,
                                                    ).showSnackBar(
                                                      SnackBar(
                                                        content: Text(
                                                          'Upload failed: $error',
                                                        ),
                                                      ),
                                                    );
                                                  }
                                                } finally {
                                                  if (context.mounted) {
                                                    setState(() {
                                                      uploadingAttachment =
                                                          false;
                                                    });
                                                  }
                                                }
                                              },
                                        icon: const Icon(Icons.upload_file),
                                        label: Text(
                                          uploadingAttachment
                                              ? 'Uploading...'
                                              : attachmentName ??
                                                    'Upload instruction file',
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(
                                            0xFF8A887C,
                                          ),
                                          foregroundColor: const Color(
                                            0xFFE8D8C1,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                          ),
                                          shape: const StadiumBorder(),
                                        ),
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed: uploadingAttachment
                                          ? null
                                          : () async {
                                              final isExistingLink =
                                                  attachmentName ==
                                                      'Google Sheets instruction' ||
                                                  attachmentName ==
                                                      'Task instruction link';
                                              final linkController =
                                                  TextEditingController(
                                                    text: isExistingLink
                                                        ? attachmentUrl
                                                        : '',
                                                  );
                                              final link = await showDialog<String>(
                                                context: context,
                                                builder: (dialogContext) => AlertDialog(
                                                  title: const Text(
                                                    'Add task link',
                                                  ),
                                                  content: Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      const Text(
                                                        'Make sure students have permission to open this link.',
                                                      ),
                                                      const SizedBox(
                                                        height: 12,
                                                      ),
                                                      TextField(
                                                        controller:
                                                            linkController,
                                                        keyboardType:
                                                            TextInputType.url,
                                                        decoration:
                                                            const InputDecoration(
                                                              hintText:
                                                                  'https://example.com/instructions',
                                                            ),
                                                      ),
                                                    ],
                                                  ),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.of(
                                                            dialogContext,
                                                          ).pop(),
                                                      child: const Text(
                                                        'Cancel',
                                                      ),
                                                    ),
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.of(
                                                            dialogContext,
                                                          ).pop(
                                                            linkController.text
                                                                .trim(),
                                                          ),
                                                      child: const Text(
                                                        'Save link',
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                              linkController.dispose();
                                              if (link == null ||
                                                  !context.mounted) {
                                                return;
                                              }
                                              if (!_isHttpUrl(link)) {
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                      'Enter a valid HTTP or HTTPS link.',
                                                    ),
                                                  ),
                                                );
                                                return;
                                              }
                                              setState(() {
                                                attachmentName =
                                                    _isGoogleSheetsUrl(link)
                                                    ? 'Google Sheets instruction'
                                                    : 'Task instruction link';
                                                attachmentUrl = link;
                                              });
                                            },
                                      icon: const Icon(Icons.link_outlined),
                                      label: const Text('Add link'),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              Center(
                                child: SizedBox(
                                  width: 130,
                                  height: 34,
                                  child: ElevatedButton(
                                    onPressed: () async {
                                      if (titleController.text.trim().isEmpty ||
                                          (bodyController.text.trim().isEmpty &&
                                              !hasPdfAttachment() &&
                                              !_isHttpUrl(
                                                attachmentUrl ?? '',
                                              ))) {
                                        setState(
                                          () => validationError =
                                              'Enter a task title and description, or attach a PDF or link.',
                                        );
                                        return;
                                      }
                                      if (!assignToAll &&
                                          targetStudentEmails.isEmpty) {
                                        setState(
                                          () => validationError =
                                              'Select at least one student or choose Assign to all.',
                                        );
                                        return;
                                      }
                                      if (dueDate != null &&
                                          !isTaskDeadlineValid(dueDate!)) {
                                        setState(
                                          () => validationError =
                                              'Choose a deadline later today or on a future date.',
                                        );
                                        return;
                                      }
                                      final rubricResult =
                                          await SubjectViewScreen._showCreateRubricDialog(
                                            context,
                                            subject: subject,
                                            taskTitle: titleController.text,
                                            taskBody: bodyController.text,
                                            instructorName: instructorName,
                                            instructorEmail: instructorEmail,
                                            role: role,
                                            profileImageUrl: profileImageUrl,
                                            allowUpload: allowUpload,
                                            closeAfterDeadline:
                                                closeAfterDeadline,
                                            targetStudentEmails:
                                                targetStudentEmails,
                                            targetStudentNames:
                                                targetStudentNames,
                                            attachmentName: attachmentName,
                                            attachmentUrl: attachmentUrl,
                                            draftIndex: draftIndex,
                                            initialRubric: pendingRubric,
                                            postId: taskPost?.id,
                                            dueDate: dueDate,
                                          );
                                      if (rubricResult != null) {
                                        pendingRubric = rubricResult.rubric;
                                      }
                                      if (rubricResult?.saved == true &&
                                          context.mounted) {
                                        Navigator.of(context).pop(true);
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppPalette.rose,
                                      foregroundColor: Colors.black,
                                      padding: EdgeInsets.zero,
                                      shape: const StadiumBorder(),
                                    ),
                                    child: const Text('Next'),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                bottomNavigationBar: DashboardBottomNavigation(
                  role: role,
                  homeIsActive: false,
                  userName: role == UserRole.instructor
                      ? instructorName
                      : studentName,
                  userEmail: role == UserRole.instructor
                      ? instructorEmail
                      : studentEmail,
                  profileImageUrl: profileImageUrl,
                ),
              );
            },
          );
        },
      ),
    );
    if (shouldCreateRubric != true) return;
    if (!context.mounted) return;
  }

  Widget _buildAnnouncementCard(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> post,
  ) {
    final postedAnnouncement = post.data();
    final isGlobalAnnouncement =
        post.reference.parent.id == 'global_announcements';
    final authorName = role == UserRole.instructor
        ? instructorName
        : studentName;
    final authorEmail = role == UserRole.instructor
        ? instructorEmail
        : studentEmail;

    return Material(
      color: beige,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AnnouncementDetailsScreen(
              subjectId: subject.id,
              postId: post.id,
              announcement: postedAnnouncement,
              authorName: authorName,
              authorEmail: authorEmail,
              authorRole: role == UserRole.instructor ? 'Teacher' : 'Student',
              isGlobalAnnouncement: isGlobalAnnouncement,
            ),
          ),
        ),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: beige,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF9C948B)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  UserProfileAvatar(
                    role: UserRole.instructor,
                    userEmail:
                        postedAnnouncement['posterEmail']?.toString() ?? '',
                    profileImageUrl: null,
                    radius: 14,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      postedAnnouncement['posterName'] as String? ??
                          postedAnnouncement['author'] as String? ??
                          (isGlobalAnnouncement ? 'Admin' : instructorName),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (!isGlobalAnnouncement && role == UserRole.instructor)
                    IconButton(
                      tooltip: 'Edit announcement',
                      onPressed: () => _showEditPostDialog(context, post: post),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      visualDensity: VisualDensity.compact,
                    ),
                  if (!isGlobalAnnouncement && role == UserRole.instructor)
                    IconButton(
                      tooltip: 'Delete announcement',
                      onPressed: () => _confirmDeletePost(context, post: post),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      color: Colors.red,
                      visualDensity: VisualDensity.compact,
                    ),
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
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                postedAnnouncement['body'] as String? ?? '',
                style: const TextStyle(fontSize: 12, height: 1.15),
              ),
              if (postedAnnouncement['attachmentUrl'] is String &&
                  (postedAnnouncement['attachmentUrl'] as String)
                      .trim()
                      .isNotEmpty)
                TextButton.icon(
                  onPressed: () async {
                    final uri = Uri.tryParse(
                      postedAnnouncement['attachmentUrl'] as String,
                    );
                    if (uri == null || !await launchUrl(uri)) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Could not open the attachment.'),
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.attach_file, size: 16),
                  label: Text(
                    postedAnnouncement['attachmentName'] as String? ??
                        'Open attachment',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTaskCard(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>>? taskDoc,
  ) {
    final task = taskDoc?.data();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: beige,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF9C948B)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: taskDoc == null
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TaskDetailsScreen(
                          subject: subject,
                          role: role,
                          task: taskDoc,
                          studentName: studentName,
                          studentEmail: studentEmail,
                        ),
                      ),
                    ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: Colors.black,
                          child: Icon(
                            Icons.description_outlined,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                task?['title'] as String? ??
                                    'No tasks posted yet',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (role == UserRole.instructor && taskDoc != null) ...[
                          IconButton(
                            tooltip: 'Edit task',
                            onPressed: () =>
                                _showAddTaskPage(context, taskPost: taskDoc),
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            visualDensity: VisualDensity.compact,
                          ),
                          IconButton(
                            tooltip: 'Delete task',
                            onPressed: () =>
                                _confirmDeletePost(context, post: taskDoc),
                            icon: const Icon(Icons.delete_outline, size: 18),
                            color: Colors.red.shade700,
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                        if (taskDoc != null)
                          const Icon(
                            Icons.chevron_right,
                            color: Colors.black54,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditPostDialog(
    BuildContext context, {
    required QueryDocumentSnapshot<Map<String, dynamic>> post,
  }) async {
    final data = post.data();
    final titleController = TextEditingController(
      text: data['title'] as String? ?? '',
    );
    final bodyController = TextEditingController(
      text: data['body'] as String? ?? '',
    );
    String? validationError;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFFE5D4B8),
          title: Text(
            data['type'] == 'Task' ? 'Edit task' : 'Edit announcement',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  onChanged: (_) {
                    if (validationError != null) {
                      setDialogState(() => validationError = null);
                    }
                  },
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: bodyController,
                  minLines: 4,
                  maxLines: 8,
                  onChanged: (_) {
                    if (validationError != null) {
                      setDialogState(() => validationError = null);
                    }
                  },
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                if (validationError != null) ...[
                  const SizedBox(height: 8),
                  _validationMessage(validationError!),
                ],
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    formatPostedDate(data['postedAt']),
                    style: Theme.of(dialogContext).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppPalette.rose,
                foregroundColor: Colors.black,
              ),
              onPressed: () async {
                final title = titleController.text.trim();
                final body = bodyController.text.trim();
                if (title.isEmpty || body.isEmpty) {
                  setDialogState(
                    () => validationError =
                        'Enter both a title and description before saving.',
                  );
                  return;
                }
                await FirestoreService.updatePost(
                  subjectId: subject.id,
                  postId: post.id,
                  title: title,
                  body: body,
                );
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Post updated')));
              },
              child: const Text('Save changes'),
            ),
          ],
        ),
      ),
    );
    titleController.dispose();
    bodyController.dispose();
  }

  Future<void> _confirmDeletePost(
    BuildContext context, {
    required QueryDocumentSnapshot<Map<String, dynamic>> post,
  }) async {
    final data = post.data();
    final postType = data['type'] == 'Task' ? 'task' : 'announcement';
    var isDeleting = false;
    String? deleteError;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => PopScope(
          canPop: !isDeleting,
          child: AlertDialog(
            title: Text('Delete $postType?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This will permanently remove this $postType from the classroom.',
                ),
                if (isDeleting) ...[
                  const SizedBox(height: 16),
                  const Center(child: CircularProgressIndicator()),
                ],
                if (deleteError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    deleteError!,
                    style: TextStyle(color: Colors.red.shade700),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: isDeleting
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                ),
                onPressed: isDeleting
                    ? null
                    : () async {
                        setDialogState(() {
                          isDeleting = true;
                          deleteError = null;
                        });
                        try {
                          await FirestoreService.deletePost(
                            subjectId: subject.id,
                            postId: post.id,
                          );
                          if (!dialogContext.mounted) return;
                          Navigator.of(dialogContext).pop();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${postType[0].toUpperCase()}'
                                '${postType.substring(1)} deleted',
                              ),
                            ),
                          );
                        } on FirebaseException catch (error) {
                          if (!dialogContext.mounted) return;
                          setDialogState(() {
                            isDeleting = false;
                            deleteError =
                                'Delete failed: ${error.message ?? error.code}';
                          });
                        } catch (error, stackTrace) {
                          debugPrint(
                            'Failed to delete $postType: $error\n$stackTrace',
                          );
                          if (!dialogContext.mounted) return;
                          setDialogState(() {
                            isDeleting = false;
                            deleteError =
                                'Could not delete the $postType. Please try again.';
                          });
                        }
                      },
                child: isDeleting
                    ? const Text('Deleting...')
                    : const Text('Delete'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
