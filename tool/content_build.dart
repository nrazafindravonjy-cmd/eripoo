// Compiles the content sources (content/*.yaml) into the pack embedded in
// the app (assets/content/base_pack.json), after strict parsing and
// validation (docs/PRODUCT_ARCHITECTURE.md §6.1).
//
//   dart run tool/content_build.dart          # build + report
//   dart run tool/content_build.dart --check  # CI: fails if not up to date
//
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:eripoo/content/content_pack.dart';
import 'package:eripoo/content/content_validator.dart';
import 'package:eripoo/content/json_reader.dart';
import 'package:eripoo/content/localized_text.dart';
import 'package:eripoo/core/i18n/app_language.dart';
import 'package:yaml/yaml.dart';

const sourceDir = 'content';
const outputPath = 'assets/content/base_pack.json';

Object? plain(Object? yaml) => switch (yaml) {
  YamlMap() => {for (final e in yaml.entries) e.key.toString(): plain(e.value)},
  YamlList() => [for (final v in yaml) plain(v)],
  _ => yaml,
};

Object? load(String path) => plain(loadYaml(File(path).readAsStringSync()));

List<File> yamlFiles(String dir) {
  final d = Directory(dir);
  if (!d.existsSync()) return [];
  return d
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.yaml'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

/// Block types actually used, so authors never maintain the list.
Set<String> usedBlockTypes(List<Object?> quests) => {
  for (final q in quests.cast<Map<String, Object?>>())
    for (final s in (q['steps']! as List<Object?>).cast<Map<String, Object?>>())
      for (final b
          in (s['blocks']! as List<Object?>).cast<Map<String, Object?>>())
        b['type']! as String,
};

const _languageKeys = {'fr', 'mg', 'en'};

/// True for a localized text (`{fr: ..., mg: ..., en: ..., status: ...}`).
bool _isText(Map<String, Object?> map) =>
    map.containsKey('fr') &&
    map.keys.every((k) => _languageKeys.contains(k) || k == 'status');

/// Applies the pack's `default_status` to every text that does not state
/// its own status for a language, so the review state of drafts is never
/// implied as "reviewed" by omission.
Object? withDefaultStatus(Object? node, Map<String, Object?> defaults) {
  if (node is List) {
    return [for (final v in node) withDefaultStatus(v, defaults)];
  }
  if (node is! Map<String, Object?>) return node;
  if (_isText(node)) {
    final own = (node['status'] as Map<String, Object?>?) ?? const {};
    final status = {
      for (final language in _languageKeys)
        if (node.containsKey(language) &&
            (own[language] ?? defaults[language]) != null)
          language: own[language] ?? defaults[language],
    };
    return {
      for (final e in node.entries)
        if (e.key != 'status') e.key: e.value,
      if (status.isNotEmpty) 'status': status,
    };
  }
  return {
    for (final e in node.entries) e.key: withDefaultStatus(e.value, defaults),
  };
}

Map<String, Object?> assemble() {
  final meta = load('$sourceDir/pack.yaml')! as Map<String, Object?>;
  final defaults =
      (meta.remove('default_status') as Map<String, Object?>?) ?? const {};
  final quests = <Object?>[
    if (File('$sourceDir/diagnostic.yaml').existsSync())
      load('$sourceDir/diagnostic.yaml'),
    for (final f in yamlFiles('$sourceDir/quests')) load(f.path),
  ];
  final missions = <Object?>[
    for (final f in yamlFiles('$sourceDir/missions'))
      ...(load(f.path)! as List<Object?>),
  ];
  final sections = File('$sourceDir/sections.yaml').existsSync()
      ? load('$sourceDir/sections.yaml')! as List<Object?>
      : const <Object?>[];
  final tools = File('$sourceDir/tools.yaml').existsSync()
      ? load('$sourceDir/tools.yaml')! as List<Object?>
      : const <Object?>[];
  final badges = File('$sourceDir/badges.yaml').existsSync()
      ? load('$sourceDir/badges.yaml')! as List<Object?>
      : const <Object?>[];
  final finance = File('$sourceDir/finance.yaml').existsSync()
      ? load('$sourceDir/finance.yaml')! as Map<String, Object?>
      : const <String, Object?>{};
  final formalization = File('$sourceDir/formalization.yaml').existsSync()
      ? load('$sourceDir/formalization.yaml')
      : null;
  return {
    'format': supportedPackFormat,
    ...meta,
    'block_types': (usedBlockTypes(quests).toList()..sort()),
    'quests': withDefaultStatus(quests, defaults),
    'missions': withDefaultStatus(missions, defaults),
    'sections': withDefaultStatus(sections, defaults),
    'tools': withDefaultStatus(tools, defaults),
    if (badges.isNotEmpty) 'badges': withDefaultStatus(badges, defaults),
    if (formalization != null)
      'formalization': withDefaultStatus(formalization, defaults),
    if (finance['financing_guide'] != null)
      'financing_guide': withDefaultStatus(
        finance['financing_guide'],
        defaults,
      ),
  };
}

void main(List<String> args) {
  final check = args.contains('--check');
  final Map<String, Object?> json;
  final ContentPack pack;
  try {
    json = assemble();
    pack = ContentPack.read(JsonReader(json));
  } on ContentFormatException catch (e) {
    print('FORMAT ERROR ${e.path}: ${e.problem}');
    exit(1);
  } on YamlException catch (e) {
    print('YAML ERROR $e');
    exit(1);
  }

  final report = validatePack(pack);
  for (final w in report.warnings) {
    print('warning: $w');
  }
  for (final e in report.errors) {
    print('ERROR: $e');
  }
  print(
    'Pack ${pack.packId} ${pack.version}: '
    '${pack.quests.length} quests, ${pack.steps.length} steps, '
    '${pack.missions.length} missions.',
  );
  for (final language in AppLanguage.values) {
    final counts = report.reviewCounts[language] ?? const {};
    print(
      '  ${language.name}: '
      '${counts[ReviewStatus.reviewed] ?? 0} reviewed, '
      '${counts[ReviewStatus.needsReview] ?? 0} to review, '
      '${counts[ReviewStatus.machineDraft] ?? 0} machine drafts, '
      '${report.missing[language] ?? 0} missing (fallback)',
    );
  }
  if (!report.ok) exit(1);

  final output = '${const JsonEncoder.withIndent(' ').convert(json)}\n';
  final file = File(outputPath);
  if (check) {
    if (!file.existsSync() || file.readAsStringSync() != output) {
      print(
        '$outputPath is not up to date: run dart run tool/content_build.dart',
      );
      exit(1);
    }
    print('$outputPath is up to date.');
    return;
  }
  file
    ..createSync(recursive: true)
    ..writeAsStringSync(output);
  print('Wrote $outputPath');
}
