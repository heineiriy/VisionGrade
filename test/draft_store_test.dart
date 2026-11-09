import 'package:flutter_test/flutter_test.dart';
import 'package:visiongrade/draft_store.dart';

void main() {
  test('persists announcement recipients and attachment in a draft', () {
    final draft = DraftItem(
      type: 'Announcement',
      title: 'Field trip',
      body: 'Bring permission slips.',
      subjectTitle: 'Science',
      createdAt: DateTime(2026, 10, 31),
      targetStudentEmails: const ['student@example.com'],
      targetStudentNames: const ['Student'],
      attachmentName: 'permission.pdf',
      attachmentUrl: 'https://example.com/permission.pdf',
    );

    final restored = DraftItem.fromJson(draft.toJson());

    expect(restored.targetStudentEmails, ['student@example.com']);
    expect(restored.targetStudentNames, ['Student']);
    expect(restored.attachmentName, 'permission.pdf');
    expect(restored.attachmentUrl, 'https://example.com/permission.pdf');
  });
}
