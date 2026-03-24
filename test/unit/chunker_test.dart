import 'package:flutter_test/flutter_test.dart';
import 'package:clear_health/core/services/chunker.dart';

void main() {
  group('chunkMarkdown', () {
    test('returns empty list for empty markdown', () {
      expect(chunkMarkdown(''), isEmpty);
      expect(chunkMarkdown('   '), isEmpty);
    });

    test('splits long markdown into overlapping chunks', () {
      final words = List.generate(900, (i) => 'word$i').join(' ');
      final chunks = chunkMarkdown(words, chunkSize: 400, overlap: 50);

      expect(chunks.length, greaterThan(2));
      expect(chunks.first, contains('word0'));
      expect(chunks[1], contains('word350')); // overlap window check
    });

    test('keeps markdown tables in row-grouped chunks with headers', () {
      final rows = List.generate(
        23,
        (i) => '| Test $i | ${90 + i} | mg/dL | 70-99 | Normal |',
      ).join('\n');
      final markdown =
          '''
| Test | Result | Unit | Range | Status |
| --- | --- | --- | --- | --- |
$rows
''';

      final chunks = chunkMarkdown(markdown, chunkSize: 120, overlap: 20);
      expect(chunks.length, 3);
      expect(
        chunks.first,
        contains('| Test | Result | Unit | Range | Status |'),
      );
      expect(
        chunks.first,
        contains('| Test 0 | 90 | mg/dL | 70-99 | Normal |'),
      );
      expect(
        chunks.last,
        contains('| Test 22 | 112 | mg/dL | 70-99 | Normal |'),
      );
    });

    test('normalizes PHI patterns before chunking', () {
      final markdown = '''
Patient Name: John Doe
DOB: 1992-01-01
Contact: john.doe@example.com / +1 555 123 4567

Glucose is stable and within range.
''';
      final chunks = chunkMarkdown(markdown, chunkSize: 80, overlap: 10);
      final merged = chunks.join('\n');

      expect(merged, isNot(contains('John Doe')));
      expect(merged, isNot(contains('1992-01-01')));
      expect(merged, contains('[REDACTED_EMAIL]'));
      expect(merged, contains('[REDACTED_PHONE]'));
      expect(merged, contains('Glucose is stable'));
    });

    test('deduplicates repeated blocks', () {
      final paragraph = List.generate(80, (i) => 'value$i').join(' ');
      final markdown = '$paragraph\n\n$paragraph';
      final chunks = chunkMarkdown(markdown, chunkSize: 120, overlap: 20);

      expect(chunks.length, 1);
    });
  });
}
