import 'dart:convert';

import 'package:flutter/material.dart';

import 'errors.dart';
import 'l10n/generated/app_localizations.dart';
import 'localized_texts.dart';
import 'staff_api.dart';

class DocumentsPage extends StatefulWidget {
  const DocumentsPage({
    super.key,
    required this.api,
    required this.canEditStructure,
  });
  final StaffApi api;
  final bool canEditStructure;

  @override
  State<DocumentsPage> createState() => _DocumentsPageState();
}

class _DocumentsPageState extends State<DocumentsPage> {
  late Future<List<DocumentSummary>> _list = widget.api.documents();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return FutureBuilder<List<DocumentSummary>>(
      future: _list,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text(staffErrorText(l, snapshot.error!)));
        }
        final docs = snapshot.data;
        if (docs == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (docs.isEmpty) return Center(child: Text(l.noDocuments));
        return ListView(
          children: [
            for (final d in docs)
              ListTile(
                title: Text(d.path),
                subtitle: Text(l.version(d.version)),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => DocumentEditor(
                        api: widget.api,
                        path: d.path,
                        canEditStructure: widget.canEditStructure,
                      ),
                    ),
                  );
                  setState(() => _list = widget.api.documents());
                },
              ),
          ],
        );
      },
    );
  }
}

/// One document: its localized texts (translators and editors) and, for
/// editors, its whole structure as JSON.
class DocumentEditor extends StatefulWidget {
  const DocumentEditor({
    super.key,
    required this.api,
    required this.path,
    required this.canEditStructure,
  });
  final StaffApi api;
  final String path;
  final bool canEditStructure;

  @override
  State<DocumentEditor> createState() => _DocumentEditorState();
}

class _DocumentEditorState extends State<DocumentEditor> {
  Object? _body;
  int _version = 0;
  Object? _error;
  final _json = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _json.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final doc = await widget.api.document(widget.path);
      setState(() {
        _error = null;
        _body = doc?.$1;
        _version = doc?.$2 ?? 0;
        _json.text = const JsonEncoder.withIndent('  ').convert(doc?.$1);
      });
    } on Object catch (e) {
      setState(() => _error = e);
    }
  }

  Future<void> _run(Future<int> Function() save) async {
    final l = AppLocalizations.of(context);
    try {
      await save();
      if (mounted) showMessage(context, l.saved);
      await _load();
    } on Object catch (e) {
      if (mounted) showMessage(context, staffErrorText(l, e));
    }
  }

  Future<void> _saveStructure() async {
    final l = AppLocalizations.of(context);
    final Object? parsed;
    try {
      parsed = jsonDecode(_json.text);
    } on FormatException {
      showMessage(context, l.errorJson);
      return;
    }
    if (parsed is! Map<String, Object?> && parsed is! List<Object?>) {
      showMessage(context, l.errorJson);
      return;
    }
    final body = parsed!;
    await _run(() => widget.api.saveDocument(widget.path, body, _version));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final body = _body;
    final tabs = [
      Tab(text: l.texts),
      if (widget.canEditStructure) Tab(text: l.structure),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${widget.path} · ${l.version(_version)}'),
          actions: [
            IconButton(
              tooltip: l.reload,
              icon: const Icon(Icons.refresh),
              onPressed: _load,
            ),
          ],
          bottom: TabBar(tabs: tabs),
        ),
        body: _error != null
            ? Center(child: Text(staffErrorText(l, _error!)))
            : body == null
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final text in localizedTexts(body))
                        _TextCard(
                          key: ValueKey('${text.pointer.join('/')}@$_version'),
                          text: text,
                          onSave: (locale, value) => _run(
                            () => widget.api.setTranslation(
                              widget.path,
                              text.pointer,
                              locale,
                              value,
                              _version,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (widget.canEditStructure)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _json,
                              maxLines: null,
                              expands: true,
                              style: const TextStyle(fontFamily: 'monospace'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _saveStructure,
                            child: Text(l.save),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _TextCard extends StatefulWidget {
  const _TextCard({super.key, required this.text, required this.onSave});
  final LocalizedText text;
  final Future<void> Function(String locale, String value) onSave;

  @override
  State<_TextCard> createState() => _TextCardState();
}

class _TextCardState extends State<_TextCard> {
  late final _controllers = {
    for (final l in locales)
      l: TextEditingController(text: widget.text.values[l] ?? ''),
  };

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text.pointer.join(' › '),
              style: Theme.of(context).textTheme.labelMedium,
            ),
            for (final locale in locales)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controllers[locale],
                      decoration: InputDecoration(labelText: locale),
                      maxLines: null,
                    ),
                  ),
                  IconButton(
                    tooltip: l.save,
                    icon: const Icon(Icons.save_outlined),
                    onPressed: () {
                      final value = _controllers[locale]!.text;
                      if (value.isNotEmpty &&
                          value != widget.text.values[locale]) {
                        widget.onSave(locale, value);
                      }
                    },
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
