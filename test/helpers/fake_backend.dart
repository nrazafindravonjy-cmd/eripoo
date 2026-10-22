import 'dart:async';
import 'dart:io';

import 'package:eripoo/app/startup/app_services.dart';
import 'package:eripoo/core/ids/ids.dart';
import 'package:eripoo/data/local/app_database.dart';
import 'package:eripoo/features/auth/domain/auth_repository.dart';
import 'package:eripoo/security/crypto_service.dart';
import 'package:eripoo/security/envelopes.dart';
import 'package:eripoo/security/key_manager.dart';
import 'package:eripoo/services/backend/backend.dart';
import 'package:eripoo/sync/remote/media_remote.dart';
import 'package:eripoo/sync/remote/sync_remote.dart';

import 'fake_sync_server.dart';
import 'memory_secure_store.dart';
import 'test_database.dart';

/// Accounts of the fake server: e-mail → (id, password).
class FakeAccounts {
  final _users = <String, ({String id, String password})>{};
}

/// E-mail and password sign-in over [FakeAccounts], one per phone.
class FakeAuth implements AuthRepository {
  FakeAuth(this._accounts);

  final FakeAccounts _accounts;
  final _changes = StreamController<AuthUser?>.broadcast();
  AuthUser? _user;

  /// Increases at every sign-in: a new session, as on the real server.
  int sessions = 0;

  @override
  AuthUser? get currentUser => _user;

  @override
  Stream<AuthUser?> userChanges() => _changes.stream;

  AuthUser _signIn(String email, String id) {
    sessions++;
    _user = AuthUser(id: id, email: email);
    _changes.add(_user);
    return _user!;
  }

  @override
  Future<AuthUser> signUpWithEmail(String email, String password) async {
    AuthRules.validateEmail(email);
    AuthRules.validatePassword(password);
    if (_accounts._users.containsKey(email)) {
      throw const AccountAlreadyExists();
    }
    final id = Ids.random();
    _accounts._users[email] = (id: id, password: password);
    return _signIn(email, id);
  }

  @override
  Future<AuthUser> signInWithEmail(String email, String password) async {
    final account = _accounts._users[email];
    if (account == null || account.password != password) {
      throw const InvalidCredentials();
    }
    return _signIn(email, account.id);
  }

  @override
  Future<void> sendPasswordReset(String email) async {}

  @override
  Future<void> signOut() async {
    _user = null;
    _changes.add(null);
  }

  @override
  Future<void> signOutOtherDevices() async {}
}

/// One phone's view of the fake server.
class FakeBackend implements AccountBackend {
  FakeBackend(this.server, FakeAccounts accounts, {required this.phone})
    : auth = FakeAuth(accounts);

  final FakeSyncServer server;
  final String phone;
  @override
  final FakeAuth auth;

  String get _session => '$phone-${auth.sessions}';

  /// Like the Supabase client: always the session signed in at call time.
  @override
  SyncRemote get sync => _LiveSyncRemote(this);

  FakeSyncRemote get _current => userId == null
      ? server.anonymous()
      : server.clientFor(userId!, session: _session);

  @override
  MediaRemote get media => server.mediaFor(userId ?? '', session: _session);

  @override
  String? get userId => auth.currentUser?.id;
}

/// What bootstrap() opens, for a test phone: keys in a memory keystore,
/// an in-memory database, a temporary media directory.
Future<AppServices> testServices(CryptoService crypto) async {
  final keyManager = KeyManager(crypto, MemorySecureKeyStore());
  final keys = await keyManager.loadOrCreate(databaseExists: false);
  final AppDatabase db = memoryDatabase();
  return AppServices(
    crypto: crypto,
    keyManager: keyManager,
    keys: keys,
    database: db,
    mediaDirectory: Directory.systemTemp.createTempSync('eripoo_phone'),
  );
}

class _LiveSyncRemote implements SyncRemote {
  _LiveSyncRemote(this._backend);
  final FakeBackend _backend;
  FakeSyncRemote get _r => _backend._current;

  @override
  Future<void> registerDevice(
    String deviceId,
    String label, {
    String? appVersion,
  }) => _r.registerDevice(deviceId, label, appVersion: appVersion);
  @override
  Future<List<PushResult>> push(String deviceId, List<RemotePut> puts) =>
      _r.push(deviceId, puts);
  @override
  Future<PullPage> pull(String deviceId, int since, {int limit = 200}) =>
      _r.pull(deviceId, since, limit: limit);
  @override
  Future<void> setRecoveryWrap(RecoveryWrap wrap) => _r.setRecoveryWrap(wrap);
  @override
  Future<RecoveryWrap?> getRecoveryWrap() => _r.getRecoveryWrap();
  @override
  Future<int> rotateDataKey({
    required String deviceId,
    required int fromVersion,
    required RecoveryWrap wrap,
  }) => _r.rotateDataKey(
    deviceId: deviceId,
    fromVersion: fromVersion,
    wrap: wrap,
  );
  @override
  Future<void> leaveDevice(String deviceId) => _r.leaveDevice(deviceId);
  @override
  Future<void> deleteAccount() => _r.deleteAccount();
  @override
  Future<void> revokeDevice(String deviceId) => _r.revokeDevice(deviceId);
  @override
  Future<List<RemoteDevice>> listDevices({String? currentDeviceId}) =>
      _r.listDevices(currentDeviceId: currentDeviceId);
}
