import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? taskDueDate(Object? value) {
  return switch (value) {
    Timestamp timestamp => timestamp.toDate().toLocal(),
    DateTime dateTime => dateTime.toLocal(),
    String dateString => _parseTaskDateString(dateString),
    _ => null,
  };
}

DateTime? _parseTaskDateString(String value) {
  final parsedDate = DateTime.tryParse(value);
  if (parsedDate != null) return parsedDate.toLocal();

  final match = RegExp(
    r'^(\d{1,2})/(\d{1,2})/(\d{4}) at (\d{1,2}):(\d{2})\s*(AM|PM)$',
    caseSensitive: false,
  ).firstMatch(value.trim());
  if (match == null) return null;

  final month = int.parse(match.group(1)!);
  final day = int.parse(match.group(2)!);
  final year = int.parse(match.group(3)!);
  var hour = int.parse(match.group(4)!);
  final minute = int.parse(match.group(5)!);
  final period = match.group(6)!.toUpperCase();
  if (month < 1 ||
      month > 12 ||
      day < 1 ||
      hour < 1 ||
      hour > 12 ||
      minute > 59) {
    return null;
  }
  if (period == 'PM' && hour != 12) hour += 12;
  if (period == 'AM' && hour == 12) hour = 0;
  final date = DateTime(year, month, day, hour, minute);
  if (date.year != year || date.month != month || date.day != day) {
    return null;
  }
  return date;
}

bool isTaskDeadlineValid(DateTime deadline, {DateTime? now}) {
  return deadline.isAfter(now ?? DateTime.now());
}

String formatTaskDueDate(Object? value) {
  final date = taskDueDate(value);
  if (date == null) return 'No due date';
  final hour = date.hour == 0
      ? 12
      : date.hour > 12
      ? date.hour - 12
      : date.hour;
  final minute = date.minute.toString().padLeft(2, '0');
  final period = date.hour >= 12 ? 'PM' : 'AM';
  return '${date.month}/${date.day}/${date.year} at $hour:$minute $period';
}

String taskDueStatus(
  Object? value, {
  DateTime? today,
  bool closeAfterDeadline = true,
}) {
  final dueDate = taskDueDate(value);
  if (dueDate == null) return 'Active';

  final currentDate = today ?? DateTime.now();
  if (dueDate.isBefore(currentDate)) {
    return closeAfterDeadline ? 'Closed' : 'Active';
  }
  if (dueDate.isAfter(currentDate)) return 'Upcoming';
  return 'Active';
}

bool isTaskDueWithinDays(Object? value, {DateTime? today, int days = 3}) {
  if (days < 0) return false;

  final dueDate = taskDueDate(value);
  if (dueDate == null) return false;

  final currentDate = today ?? DateTime.now();
  final startOfToday = DateTime(
    currentDate.year,
    currentDate.month,
    currentDate.day,
  );
  final dueDay = DateTime(dueDate.year, dueDate.month, dueDate.day);
  final daysUntilDue = dueDay.difference(startOfToday).inDays;
  return daysUntilDue >= 0 && daysUntilDue <= days;
}

int compareTaskDueDates(Object? first, Object? second) {
  final firstDate = taskDueDate(first);
  final secondDate = taskDueDate(second);
  if (firstDate == null) return secondDate == null ? 0 : 1;
  if (secondDate == null) return -1;
  return firstDate.compareTo(secondDate);
}

List<String> taskTargetStudentEmails(Map<String, dynamic> data) {
  final emails = <String>[];
  final rawEmails = data['targetStudentEmails'];
  if (rawEmails is Iterable) {
    emails.addAll(rawEmails.map((value) => value.toString()));
  } else if (rawEmails is String) {
    emails.add(rawEmails);
  }
  final legacyEmail = data['targetStudentEmail'];
  if (legacyEmail is String) emails.add(legacyEmail);
  return emails
      .map((email) => email.trim().toLowerCase())
      .where((email) => email.isNotEmpty)
      .toSet()
      .toList();
}

bool isTaskVisibleToStudent(Map<String, dynamic> data, String email) {
  final targets = taskTargetStudentEmails(data);
  return targets.isEmpty || targets.contains(email.trim().toLowerCase());
}
