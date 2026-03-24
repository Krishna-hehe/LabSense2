import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'services/rate_limiter_service.dart';
import 'services/log_service.dart';

class StorageService {
  final SupabaseClient _supabase;
  final RateLimiterService _rateLimiter;

  StorageService(this._supabase, this._rateLimiter);

  Future<String?> uploadLabReport(Uint8List bytes, String fileName) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return null;

      // Rate Limit: 10 uploads per 5 mins
      final limitKey = 'upload_$userId';
      final waitTime = _rateLimiter.checkLimit(
        limitKey,
        limit: 10,
        window: const Duration(minutes: 5),
      );
      if (waitTime != null) {
        throw 'Upload limit reached. Retry in ${waitTime.inMinutes + 1} min.';
      }

      final path = '$userId/${DateTime.now().millisecondsSinceEpoch}_$fileName';

      // Compress image if possible to speed up upload
      final compressedBytes = await _compressImage(bytes);

      await _supabase.storage
          .from('lab-reports')
          .uploadBinary(
            path,
            compressedBytes,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
          );

      return path;
    } catch (e) {
      AppLogger.error('Error uploading lab report: $e');
      return null;
    }
  }

  Future<String?> uploadProfilePhoto(String profileId, Uint8List bytes) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('User not logged in');

    // Rate Limit
    final limitKey = 'upload_$userId';
    final waitTime = _rateLimiter.checkLimit(
      limitKey,
      limit: 10,
      window: const Duration(minutes: 5),
    );
    if (waitTime != null) {
      throw 'Upload limit reached. Retry in ${waitTime.inMinutes + 1} min.';
    }

    // Compress
    final compressedBytes = await _compressImage(bytes);

    // Use profileId for distinct photos
    final path = '$userId/profiles/$profileId.jpg';

    await _supabase.storage
        .from('profiles')
        .uploadBinary(
          path,
          compressedBytes,
          fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
        );

    final String publicUrl = _supabase.storage
        .from('profiles')
        .getPublicUrl(path);
    return publicUrl;
  }

  Future<String?> uploadPrescriptionImage(Uint8List bytes) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return null;

      // Rate Limit
      final limitKey = 'upload_$userId';
      final waitTime = _rateLimiter.checkLimit(
        limitKey,
        limit: 10,
        window: const Duration(minutes: 5),
      );
      if (waitTime != null) {
        throw 'Upload limit reached. Retry in ${waitTime.inMinutes + 1} min.';
      }

      final compressedBytes = await _compressImage(bytes);

      final path = '$userId/${DateTime.now().millisecondsSinceEpoch}.jpg';

      await _supabase.storage
          .from('prescriptions')
          .uploadBinary(
            path,
            compressedBytes,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
          );

      final String publicUrl = _supabase.storage
          .from('prescriptions')
          .getPublicUrl(path);
      return publicUrl;
    } catch (e) {
      AppLogger.error('Error uploading prescription image: $e');
      return null;
    }
  }

  Future<Uint8List> _compressImage(Uint8List list) async {
    try {
      // Simple validation for small files (skip if < 200KB)
      if (list.lengthInBytes < 200 * 1024 || kIsWeb) return list;

      final result = await FlutterImageCompress.compressWithList(
        list,
        minHeight: 1920,
        minWidth: 1920,
        quality: 80,
      );
      return result;
    } catch (e) {
      AppLogger.warning('Compression failed, using original bytes: $e');
      return list;
    }
  }

  Future<void> deleteLabReportFile(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      await _supabase.storage.from('lab-reports').remove([path]);
    } catch (e) {
      AppLogger.error('Error deleting lab report file from storage: $e');
    }
  }
}
