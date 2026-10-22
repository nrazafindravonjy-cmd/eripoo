import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_version.dart';

/// Sends totals through `record_usage` (anonymous: no account needed, no
/// identifier sent, the server keeps only daily totals).
Future<void> Function(Map<String, int>) supabaseUsageSink(
  SupabaseClient client,
) =>
    (totals) => client.rpc<void>(
      'record_usage',
      params: {
        'p_events': [
          for (final e in totals.entries) {'event': e.key, 'count': e.value},
        ],
        'p_app_version': appVersion,
      },
    );
