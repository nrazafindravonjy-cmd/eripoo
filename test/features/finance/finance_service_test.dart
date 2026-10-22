// The money of a project on the real local database: amounts by kind,
// refused inputs, the price and sales expected, the results computed from
// them, the trash, and two phones. Fictitious data only.
import 'package:eripoo/content/json_reader.dart';
import 'package:eripoo/content/planner.dart';
import 'package:eripoo/content/rules.dart';
import 'package:eripoo/core/ids/ids.dart';
import 'package:eripoo/core/logging/app_logger.dart';
import 'package:eripoo/data/local/app_database.dart';
import 'package:eripoo/features/finance/application/finance_service.dart';
import 'package:eripoo/features/finance/domain/finance_math.dart';
import 'package:eripoo/features/project/data/project_repository.dart';
import 'package:eripoo/features/quest/application/journey_service.dart';
import 'package:eripoo/features/trash/application/trash_service.dart';
import 'package:eripoo/security/crypto_service.dart';
import 'package:eripoo/security/key_manager.dart';
import 'package:eripoo/sync/engine/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_sync_server.dart';
import '../../helpers/journey_overrides.dart';
import '../../helpers/test_database.dart';

const owner = '0192f2a0-7c1e-7b3a-9c2d-1f2e3d4c5b6a';

void main() {
  late AppDatabase db;
  late FinanceService finance;
  late String project;

  setUp(() async {
    db = memoryDatabase();
    finance = FinanceService(db);
    project = (await ProjectRepository(db).create('Savon du quartier')).id;
  });
  tearDown(() => db.close());

  Future<void> soapWorkshop(FinanceService f, String p) async {
    await f.add(
      projectId: p,
      kind: FinanceKind.variableCost,
      label: 'Huile',
      amountMga: 450,
    );
    await f.add(
      projectId: p,
      kind: FinanceKind.variableCost,
      label: 'Emballage',
      amountMga: 150,
    );
    await f.add(
      projectId: p,
      kind: FinanceKind.fixedCost,
      label: 'Loyer',
      amountMga: 100000,
    );
    await f.add(
      projectId: p,
      kind: FinanceKind.fixedCost,
      label: 'Crédit téléphone',
      amountMga: 20000,
    );
    await f.add(
      projectId: p,
      kind: FinanceKind.investment,
      label: 'Moules',
      amountMga: 300000,
    );
    await f.add(
      projectId: p,
      kind: FinanceKind.funding,
      label: 'Économies',
      amountMga: 200000,
      source: FundingSource.own,
    );
  }

  test('nothing yet: no result is invented', () async {
    final s = await finance.snapshot(project);
    expect(s.items, isEmpty);
    expect(s.hasUnitCost, isFalse);
    expect(s.unitMargin, isNull);
    expect(s.breakEvenPoint, isNull);
    expect(s.cash, isNull);
    expect(s.gap, isNull);
  });

  test('amounts by kind give the results of the calculators', () async {
    await soapWorkshop(finance, project);
    var s = await finance.snapshot(project);
    expect(s.unitCost, 600);
    expect(s.fixedMonthly, 120000);
    expect(s.investment, 300000);
    expect(s.funding, 200000);
    expect(s.unitMargin, isNull, reason: 'no price chosen yet');

    await finance.savePlan(
      project,
      priceMga: 1000,
      volumeFirst: null,
      volumeLast: null,
    );
    s = await finance.snapshot(project);
    expect(s.unitMargin!.unitMargin, 400);
    expect(s.breakEvenPoint!.units, 300);
    expect(s.cash, isNull, reason: 'no sales expected yet');

    await finance.savePlan(
      project,
      priceMga: 1000,
      volumeFirst: 100,
      volumeLast: 400,
    );
    s = await finance.snapshot(project);
    expect(s.cash!.months, hasLength(12));
    expect(s.cash!.startingCash, 200000);
    final need = s.gap!.need;
    expect(need, greaterThan(300000), reason: 'equipment + first months');
    expect(s.gap!.missing, need - 200000);
  });

  test('refused: empty or long label, out of range, source on a cost, '
      'too many', () async {
    for (final bad in [
      () => finance.add(
        projectId: project,
        kind: FinanceKind.fixedCost,
        label: ' ',
        amountMga: 1,
      ),
      () => finance.add(
        projectId: project,
        kind: FinanceKind.fixedCost,
        label: 'X' * 81,
        amountMga: 1,
      ),
      () => finance.add(
        projectId: project,
        kind: FinanceKind.fixedCost,
        label: 'X',
        amountMga: -1,
      ),
      () => finance.add(
        projectId: project,
        kind: FinanceKind.fixedCost,
        label: 'X',
        amountMga: FinanceLimits.maxAmount + 1,
      ),
      () => finance.add(
        projectId: project,
        kind: FinanceKind.fixedCost,
        label: 'X',
        amountMga: 1,
        source: FundingSource.bank,
      ),
      () => finance.add(
        projectId: project,
        kind: FinanceKind.funding,
        label: 'X',
        amountMga: 1,
      ),
      () => finance.savePlan(
        project,
        priceMga: -1,
        volumeFirst: null,
        volumeLast: null,
      ),
      () => finance.savePlan(
        project,
        priceMga: 1,
        volumeFirst: FinanceLimits.maxMonthlyVolume + 1,
        volumeLast: 0,
      ),
    ]) {
      await expectLater(bad(), throwsA(isA<InvalidFinanceItem>()));
    }
    for (var i = 0; i < FinanceLimits.maxItems; i++) {
      await finance.add(
        projectId: project,
        kind: FinanceKind.fixedCost,
        label: 'Frais $i',
        amountMga: FinanceLimits.maxAmount,
      );
    }
    await expectLater(
      finance.add(
        projectId: project,
        kind: FinanceKind.fixedCost,
        label: 'Un de trop',
        amountMga: 1,
      ),
      throwsA(isA<InvalidFinanceItem>()),
    );
    // The largest sum still computes.
    final s = await finance.snapshot(project);
    expect(s.fixedMonthly, FinanceLimits.maxItems * FinanceLimits.maxAmount);
  });

  test('edited, deleted through the trash and restored', () async {
    final rent = await finance.add(
      projectId: project,
      kind: FinanceKind.fixedCost,
      label: 'Loyer',
      amountMga: 100000,
    );
    final edited = await finance.update(
      rent.id,
      label: 'Loyer du local',
      amountMga: 80000,
    );
    expect(edited.amountMga, 80000);
    final trash = TrashService(db);
    await trash.moveToTrash(TrashKind.financeItem, rent.id);
    expect((await finance.snapshot(project)).fixedMonthly, 0);
    final item = (await trash.items()).single;
    expect(item.label, 'Loyer du local');
    expect(item.amountMga, 80000);
    await trash.restore(TrashKind.financeItem, rent.id);
    expect((await finance.snapshot(project)).fixedMonthly, 80000);
  });

  test('the rules count amounts by kind, never by value', () async {
    await soapWorkshop(finance, project);
    final input = await JourneyService(pack: basePack(), db: db).input();
    expect(
      evaluateRule(
        Rule.read(
          JsonReader({
            'count': 'finance_items',
            'where': {'kind': 'variable_cost'},
            'gte': 2,
          }),
        ),
        input,
      ),
      isTrue,
    );
  });

  group('across two phones', () {
    late CryptoService crypto;
    setUpAll(() async => crypto = await CryptoService.init());

    test('amounts and the plan reach the other phone; a plan changed on '
        'both keeps one version and a copy', () async {
      final server = FakeSyncServer();
      final umk = crypto.generateKey();
      final keys = DataKeys(crypto, umk);
      final b = memoryDatabase();
      addTearDown(() async {
        keys.dispose();
        umk.dispose();
        await b.close();
      });
      Future<void> sync(AppDatabase database, String device) =>
          SyncEngine(
            db: database,
            remote: server.clientFor(owner, session: device),
            crypto: crypto,
            logger: AppLogger(sinks: const []),
          ).runCycle(
            SyncSession(
              ownerId: owner,
              deviceId: device,
              recordKey: keys.records,
              umkVersion: 1,
            ),
          );
      final devA = Ids.random();
      final devB = Ids.random();

      await soapWorkshop(finance, project);
      await finance.savePlan(
        project,
        priceMga: 1000,
        volumeFirst: 100,
        volumeLast: 400,
      );
      await sync(db, devA);
      await sync(b, devB);
      final onB = await FinanceService(b).snapshot(project);
      expect(onB.unitCost, 600);
      expect(onB.plan.priceMga, 1000);

      await finance.savePlan(
        project,
        priceMga: 1200,
        volumeFirst: 100,
        volumeLast: 400,
      );
      await FinanceService(b)
          .savePlan(project, priceMga: 900, volumeFirst: 100, volumeLast: 400);
      await sync(db, devA);
      await sync(b, devB);
      await sync(db, devA);
      final a = (await finance.snapshot(project)).plan.priceMga;
      final bb = (await FinanceService(b).snapshot(project)).plan.priceMga;
      expect(a, bb, reason: 'both phones converge');
      final copies = [...await db.select(db.conflictCopies).get()];
      expect(copies, hasLength(1), reason: 'the other price is kept');
    });
  });
}
