import 'package:eripoo/core/ids/ids.dart';
import 'package:eripoo/sync/remote/media_remote.dart';
import 'package:eripoo/sync/remote/sync_remote.dart';

import '../helpers/fake_sync_server.dart';
import 'sync_remote_contract.dart';

class _FakeHarness implements ContractHarness {
  final server = FakeSyncServer();

  @override
  Future<ContractSession> newUser() async {
    final owner = Ids.random();
    final session = Ids.random();
    return ContractSession(
      owner,
      server.clientFor(owner, session: session),
      server.mediaFor(owner, session: session),
      session,
    );
  }

  @override
  Future<ContractSession> signInAgain(ContractSession user) async {
    final session = Ids.random();
    return ContractSession(
      user.ownerId,
      server.clientFor(user.ownerId, session: session),
      server.mediaFor(user.ownerId, session: session),
      session,
    );
  }

  @override
  SyncRemote anonymous() => server.anonymous();

  @override
  MediaRemote anonymousMedia() => server.mediaFor('', session: '');

  @override
  Future<bool> canRefresh(ContractSession session) async =>
      !server.isSessionRevoked(session.handle as String);

  @override
  Future<void> dispose() async {}
}

void main() => syncRemoteContract(() async => _FakeHarness());
