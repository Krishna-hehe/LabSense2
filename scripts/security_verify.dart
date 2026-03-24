import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final projectRoot = Directory.current.path;
  final envFile = File(_join(projectRoot, '.env'));
  if (!envFile.existsSync()) {
    stderr.writeln('Missing .env file at project root.');
    exitCode = 1;
    return;
  }

  final env = _parseEnv(envFile.readAsLinesSync());
  final supabaseUrl = env['SUPABASE_URL']?.trim() ?? '';
  final supabaseAnonKey = env['SUPABASE_ANON_KEY']?.trim() ?? '';

  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    stderr.writeln('SUPABASE_URL and SUPABASE_ANON_KEY must be set in .env.');
    exitCode = 1;
    return;
  }

  final client = HttpClient();
  try {
    final healthChecks = await Future.wait([
      _postJson(
        client,
        '$supabaseUrl/functions/v1/ingest-lab-report',
        supabaseAnonKey,
        body: const {},
        expectedStatus: {400, 401},
      ),
      _postJson(
        client,
        '$supabaseUrl/functions/v1/create-lab-upload-url',
        supabaseAnonKey,
        body: {'fileName': 'x.pdf', 'mimeType': 'application/pdf', 'fileSize': 1},
        expectedStatus: {401},
      ),
      _postJson(
        client,
        '$supabaseUrl/functions/v1/audit-log',
        supabaseAnonKey,
        body: {'action': 'security_self_test'},
        expectedStatus: {401},
      ),
    ]);

    var failed = false;
    for (final check in healthChecks) {
      stdout.writeln(check.message);
      if (!check.ok) failed = true;
    }

    if (failed) {
      stderr.writeln('One or more security verifications failed.');
      exitCode = 1;
      return;
    }

    stdout.writeln('Security verification checks completed.');
  } finally {
    client.close(force: true);
  }
}

class _CheckResult {
  final bool ok;
  final String message;
  _CheckResult(this.ok, this.message);
}

Future<_CheckResult> _postJson(
  HttpClient client,
  String url,
  String anonKey, {
  required Map<String, dynamic> body,
  required Set<int> expectedStatus,
}) async {
  final uri = Uri.parse(url);
  final req = await client.postUrl(uri);
  req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
  req.headers.set('apikey', anonKey);
  req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $anonKey');
  req.write(jsonEncode(body));

  final res = await req.close();
  final status = res.statusCode;
  final payload = await utf8.decoder.bind(res).join();
  final safePayload = payload.length > 240 ? '${payload.substring(0, 240)}...' : payload;

  if (expectedStatus.contains(status)) {
    return _CheckResult(
      true,
      '[OK] $url -> $status',
    );
  }

  return _CheckResult(
    false,
    '[FAIL] $url -> $status (expected one of ${expectedStatus.toList()}) body=$safePayload',
  );
}

Map<String, String> _parseEnv(List<String> lines) {
  final out = <String, String>{};
  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final idx = line.indexOf('=');
    if (idx <= 0) continue;
    final key = line.substring(0, idx).trim();
    final value = line.substring(idx + 1).trim();
    out[key] = value;
  }
  return out;
}

String _join(String a, String b) {
  if (a.endsWith('\\') || a.endsWith('/')) return '$a$b';
  return '$a${Platform.pathSeparator}$b';
}
