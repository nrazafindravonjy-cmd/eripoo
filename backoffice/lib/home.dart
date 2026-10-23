import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'documents.dart';
import 'errors.dart';
import 'health.dart';
import 'l10n/generated/app_localizations.dart';
import 'staff_api.dart';
import 'stats.dart';

/// Sections shown according to the caller's roles (the server checks them
/// again on every call).
class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final _api = StaffApi(Supabase.instance.client);
  late final Future<List<String>> _roles = _api.myRoles();
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return FutureBuilder<List<String>>(
      future: _roles,
      builder: (context, snapshot) {
        final Widget body;
        final sections = <(NavigationRailDestination, Widget)>[];
        if (snapshot.hasError) {
          body = Center(child: Text(staffErrorText(l, snapshot.error!)));
        } else if (!snapshot.hasData) {
          body = const Center(child: CircularProgressIndicator());
        } else {
          final roles = snapshot.data!;
          final editor = roles.contains('content_editor');
          if (editor ||
              roles.contains('translator') ||
              roles.contains('content_publisher')) {
            sections.add((
              NavigationRailDestination(
                icon: const Icon(Icons.article_outlined),
                label: Text(l.documents),
              ),
              DocumentsPage(api: _api, canEditStructure: editor),
            ));
          }
          if (roles.contains('analyst')) {
            sections.add((
              NavigationRailDestination(
                icon: const Icon(Icons.bar_chart),
                label: Text(l.statistics),
              ),
              StatsPage(api: _api),
            ));
            sections.add((
              NavigationRailDestination(
                icon: const Icon(Icons.monitor_heart_outlined),
                label: Text(l.health),
              ),
              HealthPage(api: _api),
            ));
          }
          if (sections.isEmpty) {
            body = Center(child: Text(l.noRole));
          } else {
            final i = _index.clamp(0, sections.length - 1);
            body = Row(
              children: [
                if (sections.length > 1)
                  NavigationRail(
                    selectedIndex: i,
                    labelType: NavigationRailLabelType.all,
                    onDestinationSelected: (v) => setState(() => _index = v),
                    destinations: [for (final s in sections) s.$1],
                  ),
                Expanded(child: sections[i].$2),
              ],
            );
          }
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(l.appTitle),
            actions: [
              TextButton(
                onPressed: () => Supabase.instance.client.auth.signOut(),
                child: Text(l.signOut),
              ),
            ],
          ),
          body: body,
        );
      },
    );
  }
}
