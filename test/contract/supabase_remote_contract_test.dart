@Tags(['supabase'])
library;

import 'dart:io';

import 'package:eripoo/core/ids/ids.dart';
import 'package:eripoo/sync/remote/media_remote.dart';
import 'package:eripoo/sync/remote/supabase_media_remote.dart';
import 'package:eripoo/sync/remote/supabase_sync_remote.dart';
import 'package:eripoo/sync/remote/sync_remote.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'sync_remote_contract.dart';

/// Same contract as the fake, against a running Supabase: the local stack
/// in CI, or the development project. Never production: users are created
/// with fictitious addresses and random passwords.
///
///   ERIPOO_TEST_SUPABASE_URL=http://127.0.0.1:54321 \
///   ERIPOO_TEST_SUPABASE_ANON_KEY=... flutter test --tags supabase
final _url = Platform.environment['ERIPOO_TEST_SUPABASE_URL'];
final _key = Platform.environment['ERIPOO_TEST_SUPABASE_ANON_KEY'];

class _Login {
  _Login(this.client, this.email, this.password);
  final SupabaseClient client;
  final String email;
  final String password;
}

class _SupabaseHarness implements ContractHarness {
  final _clients = <SupabaseClient>[];

  SupabaseClient _client() {
    final client = SupabaseClient(
      _url!,
      _key!,
      authOptions: const AuthClientOptions(
        autoRefreshToken: false,
        authFlowType: AuthFlowType.implicit,
      ),
    );
    _clients.add(client);
    return client;
  }

  @override
  Future<ContractSession> newUser() async {
    final client = _client();
    final email = 'contract-${Ids.random()}@example.com';
    final password = 'pw-${Ids.random()}';
    final response = await client.auth.signUp(email: email, password: password);
    if (response.session == null) {
      throw StateError('sign-up returned no session (confirmations on?)');
    }
    return ContractSession(
      response.user!.id,
      SupabaseSyncRemote(client),
      SupabaseMediaRemote(client),
      _Login(client, email, password),
    );
  }

  @override
  Future<ContractSession> signInAgain(ContractSession user) async {
    final login = user.handle as _Login;
    final client = _client();
    await client.auth.signInWithPassword(
      email: login.email,
      password: login.password,
    );
    return ContractSession(
      user.ownerId,
      SupabaseSyncRemote(client),
      SupabaseMediaRemote(client),
      _Login(client, login.email, login.password),
    );
  }

  @override
  SyncRemote anonymous() => SupabaseSyncRemote(_client());

  @override
  MediaRemote anonymousMedia() => SupabaseMediaRemote(_client());

  @override
  Future<bool> canRefresh(ContractSession session) async {
    try {
      await (session.handle as _Login).client.auth.refreshSession();
      return true;
    } on AuthException {
      return false;
    }
  }

  @override
  Future<void> dispose() async {
    for (final client in _clients) {
      await client.dispose();
    }
  }
}

void main() {
  final url = _url;
  if (url == null || _key == null) {
    test(
      'Supabase contract',
      () {},
      skip: 'set ERIPOO_TEST_SUPABASE_URL and ERIPOO_TEST_SUPABASE_ANON_KEY',
    );
    return;
  }
  if (!url.startsWith('http://127.0.0.1') &&
      !url.startsWith('http://localhost') &&
      Platform.environment['ERIPOO_TEST_SUPABASE_ALLOW_REMOTE'] != 'dev') {
    throw StateError('refusing a non-local Supabase without explicit opt-in');
  }
  syncRemoteContract(() async => _SupabaseHarness());
}
