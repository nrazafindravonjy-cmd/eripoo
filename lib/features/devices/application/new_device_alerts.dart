import '../../../data/local/app_database.dart';
import '../../../sync/remote/sync_remote.dart';

/// Devices added to the account since [since] (docs/SECURITY.md §6.8):
/// active, other than this phone. Metadata only (name, date).
List<RemoteDevice> devicesAddedSince(
  List<RemoteDevice> devices,
  DateTime since,
) => [
  for (final d in devices)
    if (!d.current && !d.revoked && d.createdAt.isAfter(since)) d,
];

/// "A new device was added": told on the other phones, once each. What
/// this phone already knows is kept locally as the server date of the
/// newest device seen (server dates only, so the phone's clock does not
/// matter). The first time, the devices already there are taken as known.
class NewDeviceAlerts {
  NewDeviceAlerts(this._db);

  final AppDatabase _db;

  static const _key = 'devices.known_until';

  /// The devices to tell about, from the account's current [devices].
  Future<List<RemoteDevice>> pending(List<RemoteDevice> devices) async {
    final raw = await _db.readValue(_key);
    if (raw == null) {
      await acknowledge(devices);
      return const [];
    }
    final since = DateTime.fromMillisecondsSinceEpoch(
      int.parse(raw),
      isUtc: true,
    );
    return devicesAddedSince(devices, since);
  }

  /// The user has seen [devices]: none of them is told again.
  Future<void> acknowledge(List<RemoteDevice> devices) async {
    var newest = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    for (final d in devices) {
      if (d.createdAt.isAfter(newest)) newest = d.createdAt;
    }
    final raw = await _db.readValue(_key);
    final known = raw == null ? 0 : int.parse(raw);
    if (newest.millisecondsSinceEpoch > known) {
      await _db.writeValue(_key, '${newest.millisecondsSinceEpoch}');
    }
  }
}
