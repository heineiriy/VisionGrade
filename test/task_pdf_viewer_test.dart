import 'package:flutter_test/flutter_test.dart';
import 'package:visiongrade/task_pdf_viewer.dart';

void main() {
  test('recognizes PDF attachments from their file name', () {
    expect(
      isPdfAttachment(
        url: 'https://example.com/download?id=123',
        name: 'Instructions.PDF',
      ),
      isTrue,
    );
  });

  test('recognizes PDF attachments from their URL path', () {
    expect(
      isPdfAttachment(
        url: 'https://example.com/files/instructions.pdf?token=abc',
        name: 'Task instructions',
      ),
      isTrue,
    );
  });

  test('does not classify other attachments as PDFs', () {
    expect(
      isPdfAttachment(
        url: 'https://example.com/files/instructions.docx',
        name: 'instructions.docx',
      ),
      isFalse,
    );
  });
}
