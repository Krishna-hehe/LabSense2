List<String> chunkMarkdown(
  String markdown, {
  int chunkSize = 400,
  int overlap = 50,
}) {
  final chunks = <String>[];
  final normalizedMarkdown = _normalizeMarkdown(markdown);
  if (normalizedMarkdown.isEmpty) return [];

  final safeChunkSize = chunkSize < 50 ? 50 : chunkSize;
  final safeOverlap = overlap >= safeChunkSize ? safeChunkSize ~/ 2 : overlap;

  final blocks = normalizedMarkdown
      .split(RegExp(r'\n\s*\n'))
      .map((block) => block.trim())
      .where((block) => block.isNotEmpty)
      .toList(growable: false);

  for (final block in blocks) {
    final isTableBlock = block.contains('|') && block.contains('\n|');
    if (isTableBlock) {
      final lines = block
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList(growable: false);

      // Keep table headers aligned with row chunks for better retrieval precision.
      if (lines.length <= 2) {
        chunks.add(lines.join('\n'));
      } else {
        final tableHeader = '${lines[0]}\n${lines[1]}';
        final tableRows = lines.sublist(2);
        final rowChunkSize = 10;
        for (var i = 0; i < tableRows.length; i += rowChunkSize) {
          final end = (i + rowChunkSize < tableRows.length)
              ? i + rowChunkSize
              : tableRows.length;
          chunks.add('$tableHeader\n${tableRows.sublist(i, end).join('\n')}');
        }
      }
      continue;
    }

    final words = block.split(RegExp(r'\s+'));
    chunks.addAll(
      _chunkWords(words, chunkSize: safeChunkSize, overlap: safeOverlap),
    );
  }

  final deduped = <String>[];
  final seenFingerprints = <String>{};
  for (final chunk in chunks) {
    final cleaned = chunk.trim();
    if (cleaned.length <= 20) continue;
    final fingerprint = cleaned.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    if (seenFingerprints.add(fingerprint)) {
      deduped.add(cleaned);
    }
  }

  return deduped;
}

List<String> _chunkWords(
  List<String> words, {
  required int chunkSize,
  required int overlap,
}) {
  if (words.isEmpty) return [];
  final chunks = <String>[];
  final step = chunkSize - overlap;

  for (var i = 0; i < words.length; i += step) {
    final end = (i + chunkSize < words.length) ? i + chunkSize : words.length;
    chunks.add(words.sublist(i, end).join(' ').trim());
    if (end >= words.length) break;
  }

  return chunks;
}

String _normalizeMarkdown(String markdown) {
  var normalized = markdown.trim();
  if (normalized.isEmpty) return '';

  // PHI-safe normalization for common direct identifiers before embedding.
  normalized = normalized
      .replaceAll(
        RegExp(
          r'^\s*(patient|name|patient name|mrn|member id|id|dob|date of birth)\s*:\s*.+$',
          multiLine: true,
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(
        RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'),
        '[REDACTED_EMAIL]',
      )
      .replaceAll(
        RegExp(r'(?<!\d)(?:\+?\d[\d\-\s]{7,}\d)(?!\d)'),
        '[REDACTED_PHONE]',
      )
      .replaceAll(RegExp(r'\n{3,}'), '\n\n');

  return normalized.trim();
}
