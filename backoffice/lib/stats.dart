import 'package:flutter/material.dart';

import 'errors.dart';
import 'l10n/generated/app_localizations.dart';
import 'staff_api.dart';

/// Opt-in usage totals over the last 30 days; totals under 10 arrive
/// hidden from the server.
class StatsPage extends StatelessWidget {
  const StatsPage({super.key, required this.api});
  final StaffApi api;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final today = DateTime.now().toUtc();
    return FutureBuilder<List<UsageRow>>(
      future: api.usage(today.subtract(const Duration(days: 30)), today),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text(staffErrorText(l, snapshot.error!)));
        }
        final rows = snapshot.data;
        if (rows == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(l.last30Days, style: Theme.of(context).textTheme.titleLarge),
            DataTable(
              columns: [
                DataColumn(label: Text(l.day)),
                DataColumn(label: Text(l.event)),
                DataColumn(label: Text(l.appVersion)),
                DataColumn(label: Text(l.count), numeric: true),
              ],
              rows: [
                for (final r in rows)
                  DataRow(
                    cells: [
                      DataCell(Text(r.day)),
                      DataCell(Text(r.event)),
                      DataCell(Text(r.appVersion)),
                      DataCell(Text(r.count?.toString() ?? l.hidden)),
                    ],
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}
