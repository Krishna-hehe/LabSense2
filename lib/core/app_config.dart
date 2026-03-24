import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  static String get supabaseUrl => dotenv.env['SUPABASE_URL'] ?? '';
  static String get supabaseAnonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? '';
  static String get geminiApiKey =>
      dotenv.env['GEMINI_API_KEY'] ?? dotenv.env['XAI_API_KEY'] ?? '';
  static String get geminiBaseUrl =>
      dotenv.env['GEMINI_BASE_URL'] ??
      'https://generativelanguage.googleapis.com/v1beta';
  static String get geminiChatModel =>
      dotenv.env['GEMINI_CHAT_MODEL'] ?? 'gemini-flash-lite-latest';
  static String get aiProxyUrl {
    final explicit = (dotenv.env['AI_PROXY_URL'] ?? '').trim();
    if (explicit.isNotEmpty) return explicit;
    final base = supabaseUrl.trim();
    if (base.isEmpty) return '';
    return '${base.replaceAll(RegExp(r'/+$'), '')}/functions/v1/gemini-chat-proxy';
  }
  static String get aiProxyAnonKey =>
      dotenv.env['AI_PROXY_ANON_KEY'] ?? supabaseAnonKey;
  static String get shareBaseUrl => dotenv.env['SHARE_BASE_URL'] ?? '';
  // Backward-compatible aliases for any remaining legacy references.
  static String get xaiApiKey => geminiApiKey;
  static String get xaiBaseUrl => geminiBaseUrl;
  static String get xaiChatModel => geminiChatModel;
  static String get llamaParseApiKey => dotenv.env['LLAMAPARSE_API_KEY'] ?? '';
  static String get vectorApiKey => dotenv.env['VECTOR_API_KEY'] ?? '';
  static String get vectorEmbedApiKey =>
      dotenv.env['VECTOR_EMBED_API_KEY'] ?? '';
  static String get vectorRerankApiKey =>
      dotenv.env['VECTOR_RERANK_API_KEY'] ?? '';
  static String get llamaParseBaseUrl =>
      dotenv.env['LLAMAPARSE_BASE_URL'] ?? 'https://api.cloud.llamaindex.ai';
  static String get vectorBaseUrl =>
      dotenv.env['VECTOR_BASE_URL'] ?? 'https://integrate.api.nvidia.com/v1';
  static String get sentryDsn => dotenv.env['SENTRY_DSN'] ?? '';
}
