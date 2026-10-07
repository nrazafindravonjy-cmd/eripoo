// A real conflict between two phones, then the user's choice, which both
// phones end up sharing. Fictitious data only.
import 'package:eripoo/features/conflicts/application/conflict_service.dart';
import 'package:eripoo/features/project/data/project_repository.dart';
import 'package:eripoo/security/crypto_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';

import '../../helpers/fake_sync_server.dart';
import '../trash/trash_service_test.dart' as two show Phone;

void main() {
  late CryptoService crypto;
  late SecureKey umk;
  late FakeSyncServer server;
  late two.Phone a;
  late two.Phone b;
  late String project;

  setUpAll(() async => crypto = await CryptoService.init());
  setUp(() async {
    umk = crypto.generateKey();
    server = FakeSyncServer();
    a = two.Phone(crypto, umk, server);
    b = two.Phone(crypto, umk, server);
    project = (await ProjectRepository(a.db).create('Savon')).id;
    await a.sync();
    await b.sync();
    // The same project renamed on both phones, offline.
    await ProjectRepository(a.db).rename(project, 'Savon artisanal');
    await ProjectRepository(b.db).rename(project, 'Savon et bougies');
    await a.sync();
    await b.sync(); // B resolves: keeps its version, A's set aside
    await a.sync();
  });
  tearDown(() async {
    await a.close();
    await b.close();
    umk.dispose();
  });

  test('the version set aside is shown with its difference', () async {
    final views = await ConflictService(b.db).pending();
    expect(views, hasLength(1));
    expect(views.single.entityType, 'project');
    final d = views.single.differences.single;
    expect(d.current, 'Savon et bougies');
    expect(d.other, 'Savon artisanal');
    // The copy is synchronised: A sees it too.
    expect(await ConflictService(a.db).pending(), hasLength(1));
  });

  test(
    'keep the other version: both phones get it, nothing left to check',
    () async {
      final view = (await ConflictService(b.db).pending()).single;
      await ConflictService(b.db).keepOther(view.id);
      await b.sync();
      await a.sync();
      for (final p in [a, b]) {
        expect(
          (await ProjectRepository(p.db).get(project))!.title,
          'Savon artisanal',
        );
        expect(await ConflictService(p.db).pending(), isEmpty);
      }
    },
  );

  test('keep the current version: the copy is resolved everywhere, kept in '
      'the history', () async {
    final view = (await ConflictService(a.db).pending()).single;
    await ConflictService(a.db).keepCurrent(view.id);
    await a.sync();
    await b.sync();
    for (final p in [a, b]) {
      expect(
        (await ProjectRepository(p.db).get(project))!.title,
        'Savon et bougies',
      );
      expect(await ConflictService(p.db).pending(), isEmpty);
      expect(await p.db.select(p.db.conflictCopies).get(), hasLength(1));
    }
  });
}
