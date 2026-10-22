// "A new device was added" (docs/SECURITY.md §6.8): told once on the
// other phones, never about this phone or a removed one, nothing the
// first time. Server dates only. Fictitious data.
import 'package:eripoo/data/local/app_database.dart';
import 'package:eripoo/features/devices/application/new_device_alerts.dart';
import 'package:eripoo/sync/remote/sync_remote.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_database.dart';

RemoteDevice device(
  String id,
  int day, {
  bool current = false,
  bool revoked = false,
}) => RemoteDevice(
  id: id,
  label: 'Téléphone $id',
  revoked: revoked,
  createdAt: DateTime.utc(2026, 10, day),
  lastSeenAt: null,
  current: current,
);

void main() {
  late AppDatabase db;
  late NewDeviceAlerts alerts;
  setUp(() {
    db = memoryDatabase();
    alerts = NewDeviceAlerts(db);
  });
  tearDown(() => db.close());

  test('the first time, the devices already there are known', () async {
    final before = [device('A', 1, current: true), device('B', 2)];
    expect(await alerts.pending(before), isEmpty);
    expect(await alerts.pending(before), isEmpty);
  });

  test('a device added later is told until acknowledged', () async {
    final before = [device('A', 1, current: true)];
    await alerts.pending(before);
    final after = [...before, device('N', 5)];
    expect((await alerts.pending(after)).map((d) => d.id), ['N']);
    expect((await alerts.pending(after)).map((d) => d.id), ['N']);
    await alerts.acknowledge(after);
    expect(await alerts.pending(after), isEmpty);
  });

  test('never this phone, never a removed device', () {
    final since = DateTime.utc(2026, 10, 1);
    expect(
      devicesAddedSince([
        device('A', 3, current: true),
        device('R', 4, revoked: true),
        device('N', 5),
      ], since).map((d) => d.id),
      ['N'],
    );
  });

  test('acknowledging an older list never forgets a newer device', () async {
    await alerts.pending([device('A', 1, current: true)]);
    await alerts.acknowledge([device('A', 1, current: true), device('N', 5)]);
    await alerts.acknowledge([device('A', 1, current: true)]);
    expect(
      await alerts.pending([device('A', 1, current: true), device('N', 5)]),
      isEmpty,
    );
  });
}
