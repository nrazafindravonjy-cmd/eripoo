/// Account authentication (docs/SECURITY.md §3, §10). Authentication gives
/// access to the account's **encrypted** data only; decrypting needs an
/// authorised device or the recovery code.
class AuthUser {
  const AuthUser({required this.id, this.email});

  final String id;
  final String? email;
}

sealed class AuthFailure implements Exception {
  const AuthFailure();
}

final class InvalidCredentials extends AuthFailure {
  const InvalidCredentials();
}

final class EmailNotConfirmed extends AuthFailure {
  const EmailNotConfirmed();
}

final class AccountAlreadyExists extends AuthFailure {
  const AccountAlreadyExists();
}

final class WeakPassword extends AuthFailure {
  const WeakPassword();
}

final class InvalidEmail extends AuthFailure {
  const InvalidEmail();
}

final class TooManyAttempts extends AuthFailure {
  const TooManyAttempts();
}

/// No network, server unreachable, or no backend configured. The app keeps
/// working offline.
final class AuthUnavailable extends AuthFailure {
  const AuthUnavailable();
}

abstract final class AuthRules {
  static const minPasswordLength = 8;

  static String validateEmail(String email) {
    final trimmed = email.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(trimmed)) {
      throw const InvalidEmail();
    }
    return trimmed;
  }

  static void validatePassword(String password) {
    if (password.length < minPasswordLength) throw const WeakPassword();
  }
}

/// MVP: e-mail and password. Google and phone (OTP) are planned in the
/// interface of the next step, once the development project is configured
/// (OAuth client, SMS test numbers).
abstract interface class AuthRepository {
  AuthUser? get currentUser;
  Stream<AuthUser?> userChanges();
  Future<AuthUser> signUpWithEmail(String email, String password);
  Future<AuthUser> signInWithEmail(String email, String password);
  Future<void> sendPasswordReset(String email);

  /// Ends this device's session only.
  Future<void> signOut();

  /// Ends every other session of the account (after a password change or
  /// a lost phone).
  Future<void> signOutOtherDevices();
}
