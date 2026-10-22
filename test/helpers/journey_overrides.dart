import 'dart:io';

import 'package:eripoo/content/content_pack.dart';
import 'package:eripoo/data/local/app_database.dart';
import 'package:eripoo/features/quest/presentation/journey_providers.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_database.dart';

/// The pack embedded in the app, as built from content/ (the real content,
/// so screens are tested with what users will see).
ContentPack basePack() =>
    ContentPack.parse(File(basePackAsset).readAsStringSync());

/// What bootstrap() provides to the journey screens: an in-memory database
/// (closed after the test) and the content pack.
List<Override> journeyOverrides({AppDatabase? db, ContentPack? pack}) {
  final database = db ?? memoryDatabase();
  if (db == null) addTearDown(database.close);
  return [
    appDatabaseProvider.overrideWithValue(database),
    contentPackProvider.overrideWithValue(pack ?? basePack()),
  ];
}
