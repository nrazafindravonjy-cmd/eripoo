// When synchronisation runs (docs/OFFLINE_SYNC.md §8), in fake time: the
// triggers, the backoff with jitter, and never two cycles at once.
import 'dart:async';
import 'dart:math';

import 'package:eripoo/sync/sync_scheduler.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// A server that answers each cycle with the next planned result.
class Script {
  Script(this.results);
  final List<SyncAttempt> results;
  int calls = 0;
  int running = 0;
  int maxRunning = 0;
  Duration cycle = const Duration(milliseconds: 100);

  Future<SyncAttempt> call() async {
    calls++;
    running++;
    maxRunning = max(maxRunning, running);
    await Future<void>.delayed(cycle);
    running--;
    return results.isEmpty ? SyncAttempt.complete : results.removeAt(0);
  }
}

void main() {
  SyncScheduler scheduler(Script s, {double jitterDraw = 0.5}) =>
      SyncScheduler(attempt: s.call, random: _Fixed(jitterDraw));

  test('start syncs once, then every 5 minutes in the foreground only', () {
    fakeAsync((time) {
      final s = Script([]);
      final sync = scheduler(s)..start();
      time.elapse(const Duration(seconds: 1));
      expect(s.calls, 1);
      expect(sync.state, SyncState.saved);
      time.elapse(const Duration(minutes: 5));
      expect(s.calls, 2);

      sync.paused();
      time.elapse(const Duration(minutes: 30));
      expect(s.calls, 2, reason: 'nothing in the background');

      sync.resumed();
      time.elapse(const Duration(seconds: 1));
      expect(s.calls, 3, reason: 'back in the foreground');
      sync.dispose();
    });
  });

  test('a local change syncs 5 s later; typing pushes the delay back', () {
    fakeAsync((time) {
      final s = Script([]);
      final sync = scheduler(s)..start();
      time.elapse(const Duration(seconds: 1));
      sync.localChange();
      time.elapse(const Duration(seconds: 3));
      sync.localChange();
      time.elapse(const Duration(seconds: 3));
      expect(s.calls, 1, reason: 'still typing');
      time.elapse(const Duration(seconds: 3));
      expect(s.calls, 2);
      sync.dispose();
    });
  });

  test('failures back off 5 s, 15 s, 1 min, 5 min, 15 min, then hourly; '
      'success resets', () {
    fakeAsync((time) {
      final s = Script(List.filled(8, SyncAttempt.incomplete, growable: true));
      final sync = scheduler(s)..start();
      time.elapse(const Duration(milliseconds: 200));
      expect(sync.state, SyncState.waiting);
      final gaps = <Duration>[];
      var last = time.elapsed;
      for (var i = 0; i < 7; i++) {
        final before = s.calls;
        while (s.calls == before) {
          time.elapse(const Duration(seconds: 1));
        }
        gaps.add(time.elapsed - last);
        last = time.elapsed;
      }
      // Jitter drawn at the middle (0.5): the exact steps (time moves by
      // 1 s, and each retry waits for the end of the 100 ms cycle).
      const steps = [5, 15, 60, 300, 900, 3600, 3600];
      for (var i = 0; i < steps.length; i++) {
        expect(gaps[i].inSeconds, closeTo(steps[i], 1), reason: '$i');
      }
      time.elapse(const Duration(hours: 2));
      expect(sync.state, SyncState.saved);
      expect(sync.failures, 0);
      sync.dispose();
    });
  });

  test('jitter stays within ±20 %', () {
    final low = SyncScheduler(
      attempt: () async => SyncAttempt.complete,
      random: _Fixed(0),
    );
    final high = SyncScheduler(
      attempt: () async => SyncAttempt.complete,
      random: _Fixed(0.999999),
    );
    expect(low.delayFor(3), const Duration(seconds: 48));
    expect(high.delayFor(3).inSeconds, 71);
    expect(low.delayFor(50), const Duration(minutes: 48));
  });

  test('network back: waiting changes go at once', () {
    fakeAsync((time) {
      final s = Script([SyncAttempt.incomplete, SyncAttempt.incomplete]);
      final sync = scheduler(s)..start();
      time.elapse(const Duration(seconds: 6)); // 1st retry fails too
      expect(s.calls, 2);
      expect(sync.retryPlanned, isTrue); // next one in 15 s
      sync.networkBack();
      time.elapse(const Duration(seconds: 1));
      expect(s.calls, 3);
      expect(sync.state, SyncState.saved);
      expect(sync.retryPlanned, isFalse);
      sync.networkBack(); // nothing waiting: no extra call
      time.elapse(const Duration(seconds: 1));
      expect(s.calls, 3);
      sync.dispose();
    });
  });

  test('never two cycles at once; a trigger during a cycle runs one more '
      'afterwards', () {
    fakeAsync((time) {
      final s = Script([])..cycle = const Duration(seconds: 2);
      final sync = scheduler(s)..start();
      time.elapse(const Duration(milliseconds: 500));
      sync
        ..syncNow()
        ..syncNow()
        ..syncNow();
      time.elapse(const Duration(seconds: 10));
      expect(s.maxRunning, 1);
      expect(s.calls, 2);
      sync.dispose();
    });
  });

  test('sign-in needed or phone removed: everything stops', () {
    fakeAsync((time) {
      final s = Script([SyncAttempt.signInNeeded]);
      final sync = scheduler(s)..start();
      time.elapse(const Duration(seconds: 1));
      expect(sync.state, SyncState.signInNeeded);
      sync
        ..localChange()
        ..syncNow();
      time.elapse(const Duration(hours: 3));
      expect(s.calls, 1);

      sync.restart(); // signed in again
      time.elapse(const Duration(seconds: 1));
      expect(s.calls, 2);
      expect(sync.state, SyncState.saved);
      sync.dispose();

      final r = Script([SyncAttempt.removed]);
      final removed = scheduler(r)..start();
      time.elapse(const Duration(hours: 1));
      expect(removed.state, SyncState.removed);
      expect(r.calls, 1);
      removed.dispose();
    });
  });

  test('an unexpected error is a failed attempt, retried', () {
    fakeAsync((time) {
      var calls = 0;
      final sync = SyncScheduler(
        attempt: () async {
          if (calls++ == 0) throw StateError('boom');
          return SyncAttempt.complete;
        },
        random: _Fixed(0.5),
      )..start();
      time.elapse(const Duration(seconds: 6));
      expect(calls, 2);
      expect(sync.state, SyncState.saved);
      sync.dispose();
    });
  });

  test('states are published', () {
    fakeAsync((time) {
      final seen = <SyncState>[];
      final sync = scheduler(Script([SyncAttempt.incomplete]));
      final sub = sync.states.listen(seen.add);
      sync.start();
      time.elapse(const Duration(seconds: 10));
      expect(seen, [
        SyncState.running,
        SyncState.waiting,
        SyncState.running,
        SyncState.saved,
      ]);
      unawaited(sub.cancel());
      sync.dispose();
    });
  });
}

class _Fixed implements Random {
  _Fixed(this.value);
  final double value;
  @override
  double nextDouble() => value;
  @override
  int nextInt(int max) => 0;
  @override
  bool nextBool() => false;
}
