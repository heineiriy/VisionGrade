import 'package:flutter_test/flutter_test.dart';
import 'package:visiongrade/task_due_date.dart';

void main() {
  final today = DateTime(2026, 10, 27, 15);

  test('includes tasks due today and within the next three days', () {
    expect(isTaskDueWithinDays(DateTime(2026, 10, 27), today: today), isTrue);
    expect(isTaskDueWithinDays(DateTime(2026, 10, 30), today: today), isTrue);
  });

  test(
    'excludes tasks due after three days, overdue, or without a deadline',
    () {
      expect(
        isTaskDueWithinDays(DateTime(2026, 10, 31), today: today),
        isFalse,
      );
      expect(
        isTaskDueWithinDays(DateTime(2026, 10, 26), today: today),
        isFalse,
      );
      expect(isTaskDueWithinDays(null, today: today), isFalse);
    },
  );

  test('marks overdue tasks closed', () {
    expect(taskDueStatus(DateTime(2026, 10, 26), today: today), 'Closed');
  });

  test('keeps overdue tasks active when closing is disabled', () {
    expect(
      taskDueStatus(
        DateTime(2026, 10, 26),
        today: today,
        closeAfterDeadline: false,
      ),
      'Active',
    );
  });

  test('formats task deadlines with the date and time', () {
    expect(
      formatTaskDueDate(DateTime(2026, 10, 27, 15, 5)),
      '10/27/2026 at 3:05 PM',
    );
    expect(
      formatTaskDueDate(DateTime(2026, 10, 27, 0, 0)),
      '10/27/2026 at 12:00 AM',
    );
  });

  test('parses the formatted task deadline used in Firestore', () {
    expect(taskDueDate('10/27/2026 at 3:05 PM'), DateTime(2026, 10, 27, 15, 5));
    expect(taskDueDate('10/27/2026 at 12:00 AM'), DateTime(2026, 10, 27));
    expect(taskDueDate('13/27/2026 at 3:05 PM'), isNull);
  });

  test('allows a future deadline later on the same day', () {
    final now = DateTime(2026, 10, 27, 9, 0);
    expect(isTaskDeadlineValid(DateTime(2026, 10, 27, 17), now: now), isTrue);
    expect(
      isTaskDeadlineValid(DateTime(2026, 10, 27, 8, 59), now: now),
      isFalse,
    );
  });

  test('marks an overdue deadline as closed', () {
    final overdue = DateTime(2026, 10, 27, 2, 55);
    final now = DateTime(2026, 10, 27, 3, 7);
    expect(taskDueStatus(overdue, today: now), 'Closed');
  });
}
