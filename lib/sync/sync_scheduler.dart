import 'dart:async';
import 'dart:math';

/// What the user can be told about synchronisation (never "saved" unless
/// the last cycle ran to the end with nothing left to send).
enum SyncState {
  /// No cycle yet since the app started.
  idle,
  running,

  /// Everything is on the server.
  saved,

  /// Changes wait on this phone (no network, server busy): retried later.
  waiting,

  /// The account session ended: sign in again; local data is kept.
  signInNeeded,

  /// This phone was removed from the account; its data is erased.
  removed,

  /// The data key was changed on another phone: this one needs the new
  /// key (code or transfer); its data is kept.
  keyOutdated,

  /// This phone switched to a new data key: restart to load it.
  restartNeeded,
}

/// The result of one attempt, as the scheduler needs it.
enum SyncAttempt {
  /// Ran to the end, nothing left to send.
  complete,

  /// Cut short or changes left: retry with backoff.
  incomplete,

  /// The session ended: stop until the user signs in again.
  signInNeeded,

  /// This phone was removed from the account: stop for good.
  removed,

  /// A newer data key exists elsewhere: stop until this phone has it.
  keyOutdated,

  /// A new data key is in use: stop until the app restarts.
  restartNeeded,
}

/// Decides **when** to synchronise (docs/OFFLINE_SYNC.md §8): at start,
/// back in the foreground, when the network returns, 5 s after a local
/// change, every 5 minutes in the foreground; after a failure, retries
/// back off (5 s, 15 s, 1 min, 5 min, 15 min, then hourly) with jitter, so
/// thousands of phones coming back online do not all call at once.
///
/// Never two cycles at the same time: a trigger during a cycle runs one
/// more cycle afterwards.
class SyncScheduler {
  SyncScheduler({
    required this._attempt,
    Random? random,
    this.writeDelay = const Duration(seconds: 5),
    this.foregroundPeriod = const Duration(minutes: 5),
  }) : _random = random ?? Random();

  final Future<SyncAttempt> Function() _attempt;
  final Random _random;
  final Duration writeDelay;
  final Duration foregroundPeriod;

  static const backoff = [
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(hours: 1),
  ];

  /// ± 20 % around each step.
  static const jitter = 0.2;

  final _states = StreamController<SyncState>.broadcast();
  SyncState _state = SyncState.idle;
  bool _running = false;
  bool _again = false;
  bool _foreground = true;
  bool _stopped = false;
  bool _disposed = false;
  int _failures = 0;
  Timer? _retry;
  Timer? _write;
  Timer? _periodic;

  SyncState get state => _state;
  Stream<SyncState> get states => _states.stream;

  /// Consecutive failed attempts (resets on a complete cycle).
  int get failures => _failures;

  /// When the next retry is planned, for tests and diagnostics.
  bool get retryPlanned => _retry?.isActive ?? false;

  void _set(SyncState state) {
    if (_state == state || _disposed) return;
    _state = state;
    _states.add(state);
  }

  /// App start.
  void start() {
    _foreground = true;
    _startPeriodic();
    syncNow();
  }

  /// Back in the foreground.
  void resumed() {
    _foreground = true;
    _startPeriodic();
    syncNow();
  }

  /// In the background: no periodic cycle (background work is left to
  /// the system scheduler, WorkManager).
  void paused() {
    _foreground = false;
    _periodic?.cancel();
  }

  /// A local change was saved: synchronise a little later, once the user
  /// has finished typing (each new change pushes the delay back).
  void localChange() {
    if (_stopped || _disposed) return;
    _write?.cancel();
    _write = Timer(writeDelay, syncNow);
  }

  /// The system says the network is back (a signal only: the attempt
  /// itself checks the connection). Waiting retries go now.
  void networkBack() {
    if (_failures == 0 && _state != SyncState.waiting) return;
    syncNow();
  }

  /// The user asked, or a trigger fired.
  void syncNow() {
    if (_stopped || _disposed) return;
    _retry?.cancel();
    if (_running) {
      _again = true;
      return;
    }
    unawaited(_run());
  }

  /// After the user signed in again.
  void restart() {
    _stopped = false;
    _failures = 0;
    syncNow();
  }

  Future<void> _run() async {
    _running = true;
    _set(SyncState.running);
    SyncAttempt result;
    try {
      result = await _attempt();
    } on Object {
      result = SyncAttempt.incomplete;
    }
    _running = false;
    if (_disposed) return;
    switch (result) {
      case SyncAttempt.complete:
        _failures = 0;
        _set(SyncState.saved);
      case SyncAttempt.incomplete:
        _failures++;
        _set(SyncState.waiting);
        _planRetry();
      case SyncAttempt.signInNeeded ||
          SyncAttempt.removed ||
          SyncAttempt.keyOutdated ||
          SyncAttempt.restartNeeded:
        _stopped = true;
        _again = false;
        _retry?.cancel();
        _write?.cancel();
        _periodic?.cancel();
        _set(switch (result) {
          SyncAttempt.removed => SyncState.removed,
          SyncAttempt.keyOutdated => SyncState.keyOutdated,
          SyncAttempt.restartNeeded => SyncState.restartNeeded,
          _ => SyncState.signInNeeded,
        });
        return;
    }
    if (_again) {
      _again = false;
      syncNow();
    }
  }

  /// The delay before retry number [failures] (1-based), with jitter.
  Duration delayFor(int failures) {
    final base = backoff[min(failures, backoff.length) - 1];
    final factor = 1 + jitter * (2 * _random.nextDouble() - 1);
    return base * factor;
  }

  void _planRetry() {
    _retry?.cancel();
    _retry = Timer(delayFor(_failures), syncNow);
  }

  void _startPeriodic() {
    _periodic?.cancel();
    _periodic = Timer.periodic(foregroundPeriod, (_) {
      // While failing, the backoff decides: the periodic cycle would
      // otherwise call the server every 5 minutes whatever happens.
      if (_foreground && _failures == 0) syncNow();
    });
  }

  void dispose() {
    _disposed = true;
    _retry?.cancel();
    _write?.cancel();
    _periodic?.cancel();
    unawaited(_states.close());
  }
}
