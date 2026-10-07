import '../data/local/app_database.dart';
import '../features/media/application/media_sync.dart';
import 'engine/sync_engine.dart';
import 'sync_runner.dart';
import 'sync_scheduler.dart';

/// The kind of network, as far as cost is concerned.
enum NetworkKind {
  none,

  /// Wi-Fi or Ethernet: usually not counted per megabyte.
  unmetered,

  /// Mobile data: paid by the megabyte for most users.
  metered,
}

/// One synchronisation attempt, in the foreground or from WorkManager:
/// the records first, then the photos of this phone — on Wi-Fi only unless
/// the user allowed mobile data (docs/OFFLINE_SYNC.md §9).
class SyncCycle {
  SyncCycle({
    required this._db,
    required this._runner,
    required this._session,
    required this._media,
    required this._network,
  });

  final AppDatabase _db;
  final SyncRunner _runner;
  final SyncSession Function() _session;
  final MediaSync? _media;
  final Future<NetworkKind> Function() _network;

  /// Local setting (this phone only).
  static const mediaOnMobileDataKey = 'sync.media_on_mobile_data';

  /// The last cycle's report, for the status shown to the user.
  SyncReport? lastReport;
  MediaPassReport? lastMedia;

  Future<SyncAttempt> call() async {
    final network = await _network();
    // No network: the attempt would fail anyway; the scheduler retries and
    // the "network back" signal brings it forward.
    if (network == NetworkKind.none) return SyncAttempt.incomplete;

    final outcome = await _runner.run(_session());
    switch (outcome) {
      case SignInNeeded():
        return SyncAttempt.signInNeeded;
      case DeviceRemoved():
        return SyncAttempt.removed;
      case SyncRan(:final report):
        lastReport = report;
        if (!report.complete) return SyncAttempt.incomplete;
    }

    final media = _media;
    if (media == null) return SyncAttempt.complete;
    final mobileData = await _db.readValue(mediaOnMobileDataKey) == '1';
    if (network == NetworkKind.metered && !mobileData) {
      // Records are saved; photos wait for Wi-Fi. Not a failure: no retry
      // storm on mobile data.
      return SyncAttempt.complete;
    }
    final pass = await media.uploadPending();
    lastMedia = pass;
    // Refused files wait an hour on their own; only network cuts retry.
    return pass.interrupted ? SyncAttempt.incomplete : SyncAttempt.complete;
  }
}
