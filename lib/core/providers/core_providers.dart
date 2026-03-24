import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_service.dart';
import '../ai_service.dart';
import '../storage_service.dart';
import '../vector_service.dart';
import '../services/edge_ingestion_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/sync_service.dart';
import '../app_config.dart';
import '../services/nvidia_service.dart';
import '../services/input_validation_service.dart';
import '../services/rate_limiter_service.dart';
import '../cache_service.dart';
import '../services/rls_verification_service.dart';
import '../services/audit_service.dart'; // Import AuditService

// --- Core Infrastructure Providers ---

final auditServiceProvider = Provider<AuditService>((ref) {
  return AuditService(ref.watch(supabaseClientProvider));
});

final rlsVerificationServiceProvider = Provider<RlsVerificationService>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return RlsVerificationService(client);
});

final inputValidationServiceProvider = Provider<InputValidationService>((ref) {
  return InputValidationService();
});

final rateLimiterProvider = Provider<RateLimiterService>((ref) {
  return RateLimiterService();
});

final syncBoxProvider = Provider<Box>((ref) {
  return Hive.box('sync_queue'); // Init handled in main or CacheService
});

final syncServiceProvider = ChangeNotifierProvider<SyncService>((ref) {
  final box = ref.watch(syncBoxProvider);
  return SyncService(box);
});

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final supabaseServiceProvider = Provider<SupabaseService>((ref) {
  return SupabaseService(
    ref.watch(supabaseClientProvider),
    ref.watch(inputValidationServiceProvider),
  );
});

final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService(
    ref.watch(supabaseClientProvider),
    ref.read(rateLimiterProvider),
  );
});

final edgeIngestionServiceProvider = Provider<EdgeIngestionService>((ref) {
  final service = EdgeIngestionService(ref.watch(supabaseClientProvider));
  ref.onDispose(service.dispose);
  return service;
});

final vectorServiceProvider = Provider<VectorService>((ref) {
  final client = ref.read(supabaseClientProvider);
  return VectorService(
    client,
    apiKey: AppConfig.vectorApiKey,
    vectorBaseUrl: AppConfig.vectorBaseUrl,
    nvidiaService: NvidiaService(
      apiKey: AppConfig.vectorApiKey,
      embedApiKey: AppConfig.vectorEmbedApiKey,
      rerankApiKey: AppConfig.vectorRerankApiKey,
      baseUrl: AppConfig.vectorBaseUrl,
    ),
  );
});

final aiServiceProvider = Provider<AiService>((ref) {
  final vectorService = ref.read(vectorServiceProvider);
  final supabaseClient = ref.read(supabaseClientProvider);
  // CacheService is singleton, can instantiate directly or via provider if we had one
  // Assuming singleton usage as seen in other files
  return AiService(
    aiApiKey: AppConfig.geminiApiKey,
    aiBaseUrl: AppConfig.geminiBaseUrl,
    aiChatModel: AppConfig.geminiChatModel,
    aiProxyUrl: AppConfig.aiProxyUrl,
    aiProxyAnonKey: AppConfig.aiProxyAnonKey,
    proxyAccessTokenProvider: () async {
      return supabaseClient.auth.currentSession?.accessToken;
    },
    proxyAccessTokenRefreshProvider: () async {
      final refreshed = await supabaseClient.auth.refreshSession();
      return refreshed.session?.accessToken;
    },
    llamaParseApiKey: AppConfig.llamaParseApiKey,
    llamaParseBaseUrl: AppConfig.llamaParseBaseUrl,
    vectorService: vectorService,
    cacheService: CacheService(),
    rateLimiter: ref.read(rateLimiterProvider),
  );
});
