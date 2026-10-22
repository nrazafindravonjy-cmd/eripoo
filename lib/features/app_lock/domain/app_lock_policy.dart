/// Rules of the app lock (decision D4, docs/SECURITY.md §4.11).
///
/// The app lock guards access to the interface only. It is not a key and
/// never protects data cryptographically: the database stays encrypted
/// whether the lock is on or off.
abstract final class AppLockPolicy {
  static const minPinLength = 4;
  static const maxPinLength = 8;

  /// Failures allowed before waiting periods start.
  static const freeAttempts = 4;

  static const timeoutChoices = [
    Duration.zero,
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
  ];

  static const defaultTimeout = Duration(minutes: 1);

  static bool isValidPin(String pin) =>
      pin.length >= minPinLength &&
      pin.length <= maxPinLength &&
      RegExp(r'^\d+$').hasMatch(pin);

  /// Waiting period after [failedAttempts] consecutive failures. Data is
  /// never wiped after failures: the lock is not the data protection, and
  /// wiping would destroy unsynced work.
  static Duration lockoutAfter(int failedAttempts) {
    if (failedAttempts <= freeAttempts) return Duration.zero;
    return switch (failedAttempts - freeAttempts) {
      1 => const Duration(seconds: 30),
      2 => const Duration(minutes: 1),
      3 => const Duration(minutes: 5),
      4 => const Duration(minutes: 15),
      _ => const Duration(hours: 1),
    };
  }

  /// Whether returning to the app after [backgroundedAt] requires
  /// unlocking.
  static bool shouldLockOnResume({
    required DateTime backgroundedAt,
    required DateTime now,
    required Duration timeout,
  }) {
    final elapsed = now.difference(backgroundedAt);
    // A clock that went backwards is treated as "long enough".
    return elapsed.isNegative || elapsed >= timeout;
  }
}

/// Persisted lock configuration and attempt counters.
class AppLockSettings {
  const AppLockSettings({
    this.pinVerifier,
    this.biometricEnabled = false,
    this.timeout = AppLockPolicy.defaultTimeout,
    this.failedAttempts = 0,
    this.retryAfter,
  });

  factory AppLockSettings.fromJson(Map<String, Object?> json) =>
      AppLockSettings(
        pinVerifier: json['verifier'] as String?,
        biometricEnabled: json['biometric'] as bool? ?? false,
        timeout: Duration(seconds: json['timeout'] as int? ?? 60),
        failedAttempts: json['failed'] as int? ?? 0,
        retryAfter: json['retryAfter'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(json['retryAfter'] as int),
      );

  /// Argon2id verifier of the PIN (`crypto_pwhash_str`); null = lock off.
  final String? pinVerifier;
  final bool biometricEnabled;
  final Duration timeout;
  final int failedAttempts;
  final DateTime? retryAfter;

  bool get enabled => pinVerifier != null;

  Map<String, Object?> toJson() => {
    'verifier': pinVerifier,
    'biometric': biometricEnabled,
    'timeout': timeout.inSeconds,
    'failed': failedAttempts,
    'retryAfter': retryAfter?.millisecondsSinceEpoch,
  };

  AppLockSettings copyWith({
    String? Function()? pinVerifier,
    bool? biometricEnabled,
    Duration? timeout,
    int? failedAttempts,
    DateTime? Function()? retryAfter,
  }) => AppLockSettings(
    pinVerifier: pinVerifier == null ? this.pinVerifier : pinVerifier(),
    biometricEnabled: biometricEnabled ?? this.biometricEnabled,
    timeout: timeout ?? this.timeout,
    failedAttempts: failedAttempts ?? this.failedAttempts,
    retryAfter: retryAfter == null ? this.retryAfter : retryAfter(),
  );
}

/// Outcome of a PIN attempt.
sealed class UnlockResult {
  const UnlockResult();
}

final class Unlocked extends UnlockResult {
  const Unlocked();
}

final class WrongPin extends UnlockResult {
  const WrongPin({required this.retryAfter});

  /// Null when the next attempt is allowed immediately.
  final DateTime? retryAfter;
}

final class LockedOut extends UnlockResult {
  const LockedOut({required this.retryAfter});
  final DateTime retryAfter;
}
