import 'package:eripoo/core/config/app_config.dart';
import 'package:eripoo/features/auth/data/supabase_auth_repository.dart';
import 'package:eripoo/features/auth/domain/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

void main() {
  group('rules', () {
    test('e-mail format', () {
      expect(
        AuthRules.validateEmail('  hery@example.com '),
        'hery@example.com',
      );
      expect(
        () => AuthRules.validateEmail('hery'),
        throwsA(isA<InvalidEmail>()),
      );
      expect(
        () => AuthRules.validateEmail('a@b'),
        throwsA(isA<InvalidEmail>()),
      );
    });

    test('password of at least 8 characters', () {
      AuthRules.validatePassword('12345678');
      expect(
        () => AuthRules.validatePassword('1234567'),
        throwsA(isA<WeakPassword>()),
      );
    });
  });

  group('Supabase error mapping (no server message reaches the UI)', () {
    test('known codes', () {
      expect(
        mapAuthException(const AuthException('x', code: 'email_not_confirmed')),
        isA<EmailNotConfirmed>(),
      );
      expect(
        mapAuthException(const AuthException('x', code: 'user_already_exists')),
        isA<AccountAlreadyExists>(),
      );
      expect(
        mapAuthException(const AuthException('x', code: 'email_exists')),
        isA<AccountAlreadyExists>(),
      );
      expect(
        mapAuthException(
          const AuthException('x', code: 'over_request_rate_limit'),
        ),
        isA<TooManyAttempts>(),
      );
      expect(
        mapAuthException(const AuthException('x', code: 'invalid_credentials')),
        isA<InvalidCredentials>(),
      );
    });

    test('status codes', () {
      expect(
        mapAuthException(const AuthException('x', statusCode: '429')),
        isA<TooManyAttempts>(),
      );
      expect(
        mapAuthException(
          const AuthException('x', statusCode: '400'),
          signingIn: true,
        ),
        isA<InvalidCredentials>(),
      );
      expect(
        mapAuthException(const AuthException('x', statusCode: '500')),
        isA<AuthUnavailable>(),
      );
    });
  });

  test('without build-time configuration the app runs offline', () {
    final config = AppConfig.fromEnvironment();
    expect(config.hasBackend, isFalse);
    expect(config.environment, AppEnvironment.local);
  });

  test('outside the local environment, only an HTTPS server is used', () {
    AppConfig config(AppEnvironment env, String url) => AppConfig(
      environment: env,
      supabaseUrl: url,
      supabaseAnonKey: 'public-anon-key',
    );
    expect(
      config(AppEnvironment.local, 'http://127.0.0.1:54321').hasBackend,
      isTrue,
    );
    expect(
      config(
        AppEnvironment.development,
        'http://dev.example.invalid',
      ).hasBackend,
      isFalse,
    );
    expect(
      config(
        AppEnvironment.production,
        'http://api.example.invalid',
      ).hasBackend,
      isFalse,
    );
    expect(
      config(
        AppEnvironment.production,
        'https://api.example.invalid',
      ).hasBackend,
      isTrue,
    );
  });
}
