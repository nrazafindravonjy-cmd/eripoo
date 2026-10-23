import 'dart:io';

import 'package:flutter/services.dart';

/// Loads the bundled interface fonts (Instrument Serif, Arimo) and the
/// Material icon font shipped with the Flutter SDK, so text is measured as
/// on a phone instead of with the square test font.
Future<void> loadRealFonts() async {
  final root = Platform.environment['FLUTTER_ROOT']!;
  final dir = '$root/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final file in files) {
      final bytes = File('$dir/$file').readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  await load('Roboto', [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
  Future<void> asset(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final file in files) {
      final bytes = File('assets/fonts/$file').readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  await asset('InstrumentSerif', ['InstrumentSerif-Regular.ttf']);
  await asset('Arimo', ['Arimo-Variable.ttf']);
}
