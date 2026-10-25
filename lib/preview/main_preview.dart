// Web preview for the project owner's tests (docs/PREVIEW.md): the same
// screens, journeys and content, with fictitious-only use in mind. No
// server, no account, no voice, no biometrics, and an in-memory database
// that is NOT encrypted and disappears when the page closes. Never a way
// to use Eripoo with real data.
import 'package:drift/wasm.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlite3/wasm.dart';

import '../app/app.dart';
import '../app/di/core_providers.dart';
import '../content/content_pack.dart';
import '../data/local/app_database.dart';
import '../features/quest/presentation/journey_providers.dart';
import '../security/secure_key_store.dart';

class _MemoryKeyStore implements SecureKeyStore {
  final _values = <String, String>{};

  @override
  Future<String?> read(String name) async => _values[name];

  @override
  Future<void> write(String name, String value) async => _values[name] = value;

  @override
  Future<void> delete(String name) async => _values.remove(name);

  @override
  Future<void> deleteAll() async => _values.clear();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sqlite = await WasmSqlite3.loadFromUrl(Uri.parse('sqlite3.wasm'));
  sqlite.registerVirtualFileSystem(InMemoryFileSystem(), makeDefault: true);
  final database = AppDatabase(WasmDatabase.inMemory(sqlite));
  final pack = ContentPack.parse(await rootBundle.loadString(basePackAsset));
  runApp(
    ProviderScope(
      overrides: [
        secureKeyStoreProvider.overrideWithValue(_MemoryKeyStore()),
        appDatabaseProvider.overrideWithValue(database),
        contentPackProvider.overrideWithValue(pack),
      ],
      child: const EripooApp(),
    ),
  );
}
