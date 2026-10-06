import 'dart:convert';
import 'dart:typed_data';

import 'package:eripoo/sync/remote/supabase_sync_remote.dart';
import 'package:eripoo/sync/remote/sync_remote.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('puts are encoded as the SQL functions expect', () {
    final json = encodePut(
      RemotePut(
        id: 'i',
        changeId: 'c',
        baseVersion: null,
        deleted: false,
        umkVersion: 1,
        payload: Uint8List.fromList([1, 2, 3]),
      ),
    );
    expect(json, {
      'id': 'i',
      'change_id': 'c',
      'base_version': null,
      'deleted': false,
      'umk_version': 1,
      'payload': base64.encode([1, 2, 3]),
    });
    expect(
      encodePut(
        const RemotePut(
          id: 'i',
          changeId: 'c',
          baseVersion: 4,
          deleted: true,
          umkVersion: 1,
          payload: null,
        ),
      )['payload'],
      isNull,
    );
  });

  test('push results', () {
    expect(
      decodePushResult({'id': 'a', 'status': 'applied', 'version': 7}),
      isA<PushApplied>().having((r) => r.version, 'version', 7),
    );
    final conflict = decodePushResult({
      'id': 'a',
      'status': 'conflict',
      'current': {
        'version': 3,
        'change_id': 'c',
        'device_id': 'd',
        'deleted': false,
        'umk_version': 1,
        'payload': base64.encode([9]),
      },
    }) as PushConflict;
    expect(conflict.current!.version, 3);
    expect(conflict.current!.payload, [9]);
    expect(
      decodePushResult({'id': 'a', 'status': 'conflict', 'current': null}),
      isA<PushConflict>().having((r) => r.current, 'current', isNull),
    );
    expect(
      decodePushResult({
        'id': 'a',
        'status': 'rejected',
        'reason': 'invalid_put',
      }),
      isA<PushRejected>(),
    );
  });

  test('pull pages', () {
    final page = decodePullPage({
      'head': 2,
      'records': [
        {
          'id': 'a',
          'version': 2,
          'change_id': 'c',
          'device_id': 'd',
          'deleted': true,
          'umk_version': 1,
          'payload': null,
        },
      ],
    });
    expect(page.head, 2);
    expect(page.records.single.deleted, isTrue);
    expect(page.records.single.payload, isNull);
  });

  test('server error codes', () {
    expect(mapRemoteError('device_revoked'), isA<DeviceRevoked>());
    expect(mapRemoteError('ERROR: device_unknown'), isA<DeviceUnknown>());
    expect(mapRemoteError('device_limit'), isA<DeviceLimitReached>());
    expect(mapRemoteError('rate_limited'), isA<RateLimited>());
    expect(
      mapRemoteError('reauthentication_required'),
      isA<ReauthenticationRequired>(),
    );
    expect(mapRemoteError('not_authenticated'), isA<NotAuthenticated>());
    expect(mapRemoteError('batch_too_large'), isA<RemoteRejected>());
    expect(mapRemoteError('connection reset'), isA<RemoteUnavailable>());
  });
}
