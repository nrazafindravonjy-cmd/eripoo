import 'package:eripoo/core/logging/app_logger.dart';
import 'package:eripoo/data/local/app_database.dart';
import 'package:eripoo/features/account/application/account_linker.dart';
import 'package:eripoo/features/profile/data/profile_repository.dart';
import 'package:eripoo/features/profile/domain/user_profile.dart';
import 'package:eripoo/features/project/data/project_repository.dart';
import 'package:eripoo/security/crypto_service.dart';
import 'package:eripoo/security/key_manager.dart';
import 'package:eripoo/security/recovery_code.dart';
import 'package:eripoo/sync/engine/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_sync_server.dart';
import '../../helpers/memory_secure_store.dart';
import '../../helpers/test_database.dart';

const owner = '0192f2a0-7c1e-7b3a-9c2d-1f2e3d4c5b6a';
const otherOwner = '0192f2a0-7c1e-7b3a-9c2d-000000000002';

/// A phone starting as a guest: its own keys, database and repositories.
class Phone {
  Phone(this.crypto, this.server)
    : db = memoryDatabase(),
      store = MemorySecureKeyStore() {
    keyManager = KeyManager(crypto, store);
    projects = ProjectRepository(db);
    profile = ProfileRepository(db);
  }

  final CryptoService crypto;
  final FakeSyncServer server;
  final AppDatabase db;
  final MemorySecureKeyStore store;
  late final KeyManager keyManager;
  late final ProjectRepository projects;
  late final ProfileRepository profile;
  late LocalKeys keys;

  Future<void> firstLaunch() async =>
      keys = await keyManager.loadOrCreate(databaseExists: false);

  AccountLinker linker(String ownerId) => AccountLinker(
    db: db,
    keyManager: keyManager,
    remote: server.clientFor(ownerId),
  );

  Future<SyncReport> sync(String ownerId) async {
    keys = await keyManager.loadOrCreate(databaseExists: true); // reload
    final dataKeys = DataKeys(crypto, keys.dataKey);
    try {
      return await SyncEngine(
        db: db,
        remote: server.clientFor(ownerId),
        crypto: crypto,
        logger: AppLogger(sinks: const []),
      ).runCycle(
        SyncSession(
          ownerId: ownerId,
          deviceId: keys.deviceId,
          recordKey: dataKeys.records,
          umkVersion: keys.dataKeyVersion,
        ),
      );
    } finally {
      dataKeys.dispose();
    }
  }
}

void main() {
  late CryptoService crypto;
  late FakeSyncServer server;
  setUpAll(() async => crypto = await CryptoService.init());
  setUp(() => server = FakeSyncServer());

  test('10. guest data migrates to a new account, then to a second phone with the code', () async {
    final phone = Phone(crypto, server);
    await phone.firstLaunch();
    // Months of guest work, before any account.
    final project = await phone.projects.create('Épicerie de quartier');
    await phone.projects.saveSection(
      projectId: project.id,
      sectionKey: 'problem',
      fields: {'statement': 'Les produits frais manquent le soir'},
      trackedFields: {'statement'},
    );
    await phone.profile.save(const UserProfile(displayName: 'Hery'));

    final result = await phone
        .linker(owner)
        .link(ownerId: owner, localKeys: phone.keys);
    expect(result, isA<NewAccountLinked>());
    final code = (result as NewAccountLinked).recoveryCode;
    expect(RecoveryCode.isWellFormed(code), isTrue);
    expect(await phone.db.readValue(AccountLinker.ownerKey), owner);
    expect(
      await phone.projects.get(project.id),
      isNotNull,
      reason: 'nothing deleted locally',
    );

    await phone.sync(owner);
    expect(server.recordsOf(owner), isNotEmpty);

    // A second phone signs in to the same account.
    final second = Phone(crypto, server);
    await second.firstLaunch();
    final link = await second
        .linker(owner)
        .link(ownerId: owner, localKeys: second.keys);
    expect(link, isA<RecoveryNeeded>());
    await second
        .linker(owner)
        .unlockWithRecoveryCode(
          ownerId: owner,
          wrap: (link as RecoveryNeeded).wrap,
          typedCode: RecoveryCode.groups(code).join(' '),
        );
    await second.sync(owner);

    expect(
      (await second.projects.get(project.id))!.title,
      'Épicerie de quartier',
    );
    expect(
      (await second.projects.section(
        project.id,
        'problem',
      ))!.fields['statement'],
      'Les produits frais manquent le soir',
    );
    expect((await second.profile.load()).displayName, 'Hery');
  });

  test('a wrong code changes nothing on the device', () async {
    final phone = Phone(crypto, server);
    await phone.firstLaunch();
    await phone.linker(owner).link(ownerId: owner, localKeys: phone.keys);

    final second = Phone(crypto, server);
    await second.firstLaunch();
    final before = second.keys.dataKey.extractBytes();
    final link =
        await second.linker(owner).link(ownerId: owner, localKeys: second.keys)
            as RecoveryNeeded;
    await expectLater(
      second
          .linker(owner)
          .unlockWithRecoveryCode(
            ownerId: owner,
            wrap: link.wrap,
            typedCode: second.keyManager.generateRecoveryCode(),
          ),
      throwsA(isA<WrongRecoveryCode>()),
    );
    final after = (await second.keyManager.loadOrCreate(databaseExists: true))
        .dataKey
        .extractBytes();
    expect(after, before);
    expect(await second.db.readValue(AccountLinker.ownerKey), isNull);
  });

  test(
    'guest data on the second phone is kept next to the account data',
    () async {
      final first = Phone(crypto, server);
      await first.firstLaunch();
      await first.projects.create('Projet du compte');
      final code =
          (await first.linker(owner).link(ownerId: owner, localKeys: first.keys)
                  as NewAccountLinked)
              .recoveryCode;
      await first.sync(owner);

      final second = Phone(crypto, server);
      await second.firstLaunch();
      await second.projects.create('Projet invité');
      final link =
          await second
                  .linker(owner)
                  .link(ownerId: owner, localKeys: second.keys)
              as RecoveryNeeded;
      await second
          .linker(owner)
          .unlockWithRecoveryCode(
            ownerId: owner,
            wrap: link.wrap,
            typedCode: code,
          );
      await second.sync(owner);
      await first.sync(owner);

      for (final phone in [first, second]) {
        final titles = (await phone.projects.watchActive().first).map(
          (p) => p.title,
        );
        expect(titles, unorderedEquals(['Projet du compte', 'Projet invité']));
      }
    },
  );

  test('a device linked to one account refuses another', () async {
    final phone = Phone(crypto, server);
    await phone.firstLaunch();
    await phone.linker(owner).link(ownerId: owner, localKeys: phone.keys);
    expect(
      await phone.linker(owner).link(ownerId: owner, localKeys: phone.keys),
      isA<AlreadyLinked>(),
    );
    await expectLater(
      phone.linker(otherOwner).link(ownerId: otherOwner, localKeys: phone.keys),
      throwsA(isA<AccountMismatch>()),
    );
  });
}
