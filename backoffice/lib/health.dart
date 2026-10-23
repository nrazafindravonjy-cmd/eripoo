import 'package:flutter/material.dart';

import 'errors.dart';
import 'l10n/generated/app_localizations.dart';
import 'staff_api.dart';

/// Service-wide technical totals (staff_health): no row per person, no
/// payload; totals under 10 arrive hidden from the server.
class HealthPage extends StatelessWidget {
  const HealthPage({super.key, required this.api});
  final StaffApi api;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return FutureBuilder<Map<String, Object?>>(
      future: api.health(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text(staffErrorText(l, snapshot.error!)));
        }
        final h = snapshot.data;
        if (h == null) return const Center(child: CircularProgressIndicator());
        final rows = [
          (l.healthAccounts, h['accounts']),
          (l.healthAccountsNew, h['accounts_new_7d']),
          (l.healthDevicesActive, h['devices_active']),
          (l.healthDevicesSeen, h['devices_seen_7d']),
          (l.healthSyncRecords, h['sync_records']),
          (l.healthSyncBytes, h['sync_bytes']),
          (l.healthSync24h, h['sync_changes_24h']),
          (l.healthSync7d, h['sync_changes_7d']),
          (l.healthMediaFiles, h['media_files']),
          (l.healthMediaBytes, h['media_bytes']),
          (l.healthDocuments, h['content_documents']),
        ];
        final versions = (h['app_versions'] as List<Object?>? ?? const [])
            .cast<Map<String, Object?>>();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(l.health, style: Theme.of(context).textTheme.titleLarge),
            for (final (label, value) in rows)
              ListTile(
                title: Text(label),
                trailing: Text(value?.toString() ?? l.hidden),
              ),
            const Divider(),
            Text(
              l.healthAppVersions,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final v in versions)
              ListTile(
                title: Text(v['version']! as String),
                trailing: Text('${v['devices']}'),
              ),
          ],
        );
      },
    );
  }
}
