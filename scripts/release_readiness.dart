import 'dart:io';

void main() {
  final root = Directory.current.path;
  final checks = <_Check>[
    _Check(
      name: 'Gemini proxy exists',
      ok: File(_join(root, 'supabase\\functions\\gemini-chat-proxy\\index.ts')).existsSync(),
      failHint: 'Create/deploy supabase/functions/gemini-chat-proxy/index.ts',
    ),
    _Check(
      name: 'Security self-test migration exists',
      ok: File(_join(root, 'supabase\\migrations\\005_security_self_test.sql')).existsSync(),
      failHint: 'Ensure 005_security_self_test.sql is present and applied.',
    ),
    _Check(
      name: 'Host security header reference present',
      ok: File(_join(root, 'web\\_headers')).existsSync(),
      failHint: 'Recreate web/_headers and configure equivalent headers on host/CDN.',
    ),
    _Check(
      name: 'Production AI proxy docs present',
      ok: _fileContains(
        _join(root, 'README.md'),
        'gemini-chat-proxy',
      ),
      failHint: 'Update README deployment notes to include gemini-chat-proxy.',
    ),
    _Check(
      name: '.env file sanitized (no obvious hardcoded live key prefixes)',
      ok: _isEnvSanitized(_join(root, '.env')),
      failHint: 'Remove hardcoded tokens from .env and keep only placeholders.',
    ),
  ];

  var failed = false;
  for (final c in checks) {
    if (c.ok) {
      stdout.writeln('[OK] ${c.name}');
    } else {
      failed = true;
      stderr.writeln('[FAIL] ${c.name}');
      stderr.writeln('       ${c.failHint}');
    }
  }

  if (failed) {
    exitCode = 1;
    stderr.writeln('\nRelease readiness checks failed.');
    return;
  }

  stdout.writeln('\nRelease readiness checks passed.');
}

class _Check {
  final String name;
  final bool ok;
  final String failHint;
  const _Check({
    required this.name,
    required this.ok,
    required this.failHint,
  });
}

String _join(String base, String path) {
  if (base.endsWith('\\') || base.endsWith('/')) return '$base$path';
  return '$base\\$path';
}

bool _fileContains(String path, String needle) {
  final file = File(path);
  if (!file.existsSync()) return false;
  return file.readAsStringSync().contains(needle);
}

bool _isEnvSanitized(String path) {
  final file = File(path);
  if (!file.existsSync()) return false;
  final text = file.readAsStringSync();
  final riskyPrefixes = <String>[
    'AIza',
    'xai-',
    'sk-',
    'eyJhbGci',
  ];
  for (final prefix in riskyPrefixes) {
    if (text.contains(prefix)) return false;
  }
  return true;
}
