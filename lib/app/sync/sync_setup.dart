import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

import '../../core/logging/app_logger.dart';
import '../../features/account/application/key_rotation.dart';
import '../../features/media/application/media_sync.dart';
import '../../features/media/data/media_store.dart';
import '../../security/key_manager.dart';
import '../../security/secure_key_store.dart';
import '../../services/backend/backend.dart';
import '../../sync/engine/sync_engine.dart';
import '../../sync/sync_cycle.dart';
import '../../sync/sync_runner.dart';
import '../../sync/sync_scheduler.dart';
import '../startup/app_services.dart';
import '../startup/local_data_eraser.dart';

/// Wi-Fi and Ethernet are free for most users; anything else (mobile data,
/// VPN over an unknown link) is treated as paid.
NetworkKind networkKindOf(List<ConnectivityResult> results) {
  if (results.isEmpty || results.every((r) => r == ConnectivityResult.none)) {
    return NetworkKind.none;
  }
  if (results.any(
    (r) => r == ConnectivityResult.wifi || r == ConnectivityResult.ethernet,
  )) {
    return NetworkKind.unmetered;
  }
  return NetworkKind.metered;
}

Future<NetworkKind> currentNetwork() async {
  try {
    return networkKindOf(await Connectivity().checkConnectivity());
  } on Object {
    // Unknown: try anyway, the request itself tells.
    return NetworkKind.metered;
  }
}

/// The pieces of a synchronisation, the same in the foreground and in a
/// WorkManager task.
class SyncSetup {
  SyncSetup({
    required AppServices services,
    required AccountBackend backend,
    required String ownerId,
    required SecureKeyStore store,
    required AppLogger logger,
    required MediaStore mediaStore,
    Future<NetworkKind> Function() network = currentNetwork,
  }) : _keys = DataKeys(services.crypto, services.keys.dataKey),
       _previousKeys = services.previousDataKey == null
           ? null
           : DataKeys(services.crypto, services.previousDataKey!) {
    final engine = SyncEngine(
      db: services.database,
      remote: backend.sync,
      crypto: services.crypto,
      logger: logger,
    );
    rotation = KeyRotation(
      db: services.database,
      crypto: services.crypto,
      keyManager: services.keyManager,
      remote: backend.sync,
    );
    final media = MediaSync(
      db: services.database,
      store: mediaStore,
      remote: backend.media,
      ownerId: ownerId,
    );
    SyncSession session() => SyncSession(
      ownerId: ownerId,
      deviceId: services.keys.deviceId,
      recordKey: _keys.records,
      umkVersion: services.keys.dataKeyVersion,
      previousRecordKey: _previousKeys?.records,
    );
    cycle = SyncCycle(
      db: services.database,
      runner: SyncRunner(
        engine: engine,
        eraseLocalData: () async =>
            LocalDataEraser(
              store: store,
              databaseFile: await AppServices.databaseFile(),
            ).eraseAll(
              reason: ErasureReason.deviceRevoked,
              openDatabase: services.database,
            ),
        logger: logger,
        settleKey: (serverVersion) => rotation.settle(
          serverVersion: serverVersion,
          localVersion: services.keys.dataKeyVersion,
        ),
      ),
      session: session,
      media: media,
      network: network,
      rekey: ({required mediaAllowed}) => rotation.continueRekey(
        engine: engine,
        session: session(),
        media: media,
        mediaAllowed: mediaAllowed,
      ),
    );
  }

  final DataKeys _keys;
  final DataKeys? _previousKeys;
  late final KeyRotation rotation;
  late final SyncCycle cycle;

  void dispose() {
    _keys.dispose();
    _previousKeys?.dispose();
  }
}

/// Foreground synchronisation: the scheduler fed by the app's life cycle,
/// the network signal and every local change (docs/OFFLINE_SYNC.md §8).
class SyncController {
  SyncController(this._setup, {required Stream<void> localChanges})
    : scheduler = SyncScheduler(attempt: _setup.cycle.call) {
    _lifecycle = AppLifecycleListener(
      onResume: scheduler.resumed,
      onPause: scheduler.paused,
    );
    _changes = localChanges.listen((_) => scheduler.localChange());
    _network = Connectivity().onConnectivityChanged.listen((results) {
      if (networkKindOf(results) != NetworkKind.none) {
        scheduler.networkBack();
      }
    }, onError: (Object _) {});
    scheduler.start();
  }

  final SyncSetup _setup;
  final SyncScheduler scheduler;
  late final AppLifecycleListener _lifecycle;
  late final StreamSubscription<void> _changes;
  late final StreamSubscription<List<ConnectivityResult>> _network;

  SyncCycle get cycle => _setup.cycle;

  void dispose() {
    _lifecycle.dispose();
    unawaited(_changes.cancel());
    unawaited(_network.cancel());
    scheduler.dispose();
    _setup.dispose();
  }
}
