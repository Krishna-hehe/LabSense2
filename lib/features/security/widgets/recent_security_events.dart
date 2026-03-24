import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/services/log_service.dart';
import '../../../widgets/glass_card.dart';
import '../../../core/theme.dart';

// Simple provider for security events
final securityEventsProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final client = ref.watch(supabaseClientProvider);
  try {
    final response = await client
        .from('audit_logs')
        .select('action, details, user_agent, ip_address, created_at')
        .order('created_at', ascending: false)
        .limit(10);
    return List<Map<String, dynamic>>.from(response);
  } catch (e, stackTrace) {
    AppLogger.warning(
      'Falling back to access_logs after audit_logs query failed: $e',
      error: e,
      stackTrace: stackTrace,
    );
    final fallback = await client
        .from('access_logs')
        .select('*')
        .order('created_at', ascending: false)
        .limit(10);
    return List<Map<String, dynamic>>.from(fallback);
  }
});

class RecentSecurityEvents extends ConsumerWidget {
  const RecentSecurityEvents({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(securityEventsProvider);

    return eventsAsync.when(
      data: (events) {
        if (events.isEmpty) {
          return const Center(child: Text('No security events found.'));
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: events.length,
          itemBuilder: (context, index) {
            final event = events[index];
            final createdAt = event['created_at']?.toString();
            final date = DateTime.tryParse(createdAt ?? '') ?? DateTime.now();

            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: GlassCard(
                child: ListTile(
                  dense: true,
                  leading: const CircleAvatar(
                    radius: 12,
                    backgroundColor: Colors.white10,
                    child: Icon(
                      Icons.info_outline,
                      size: 14,
                      color: AppColors.secondary,
                    ),
                  ),
                  title: Text(
                    event['action']?.toString() ?? 'Unknown Action',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  subtitle: Text(
                    DateFormat('MMM d, HH:mm:ss').format(date),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.secondary,
                    ),
                  ),
                  trailing: (event['details'] ?? event['metadata']) != null
                      ? const Icon(Icons.chevron_right, size: 16)
                      : null,
                ),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}
