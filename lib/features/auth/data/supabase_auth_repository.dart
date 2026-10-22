import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import '../domain/auth_repository.dart';

/// [AuthRepository] backed by Supabase Auth.
///
/// ⚠️ NOT VERIFIED against a running Supabase: no development project
/// exists yet (DEVELOPMENT_PLAN P4). Only the error mapping is unit-tested.
class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._auth);

  final GoTrueClient _auth;

  static AuthUser? _toUser(User? user) =>
      user == null ? null : AuthUser(id: user.id, email: user.email);

  @override
  AuthUser? get currentUser => _toUser(_auth.currentUser);

  @override
  Stream<AuthUser?> userChanges() =>
      _auth.onAuthStateChange.map((state) => _toUser(state.session?.user));

  @override
  Future<AuthUser> signUpWithEmail(String email, String password) async {
    final address = AuthRules.validateEmail(email);
    AuthRules.validatePassword(password);
    final response = await _guard(
      () => _auth.signUp(email: address, password: password),
    );
    final user = _toUser(response.user);
    if (user == null) throw const AuthUnavailable();
    return user;
  }

  @override
  Future<AuthUser> signInWithEmail(String email, String password) async {
    final address = AuthRules.validateEmail(email);
    final response = await _guard(
      () => _auth.signInWithPassword(email: address, password: password),
      signingIn: true,
    );
    final user = _toUser(response.user);
    if (user == null) throw const InvalidCredentials();
    return user;
  }

  @override
  Future<void> sendPasswordReset(String email) =>
      _guard(() => _auth.resetPasswordForEmail(AuthRules.validateEmail(email)));

  @override
  Future<void> signOut() => _guard(() => _auth.signOut());

  @override
  Future<void> signOutOtherDevices() =>
      _guard(() => _auth.signOut(scope: SignOutScope.others));

  static Future<T> _guard<T>(
    Future<T> Function() call, {
    bool signingIn = false,
  }) async {
    try {
      return await call();
    } on AuthException catch (e) {
      throw mapAuthException(e, signingIn: signingIn);
    } on Exception {
      throw const AuthUnavailable();
    }
  }
}

/// Maps Supabase errors to Eripoo failures. Never exposes server messages
/// to the UI or the logs.
AuthFailure mapAuthException(AuthException e, {bool signingIn = false}) {
  if (e is AuthWeakPasswordException) return const WeakPassword();
  if (e is AuthRetryableFetchException) return const AuthUnavailable();
  switch (e.code) {
    case 'email_not_confirmed':
      return const EmailNotConfirmed();
    case 'user_already_exists' || 'email_exists':
      return const AccountAlreadyExists();
    case 'weak_password':
      return const WeakPassword();
    case 'over_request_rate_limit' || 'over_email_send_rate_limit':
      return const TooManyAttempts();
    case 'invalid_credentials':
      return const InvalidCredentials();
  }
  if (e.statusCode == '429') return const TooManyAttempts();
  if (signingIn && e.statusCode == '400') return const InvalidCredentials();
  return const AuthUnavailable();
}
