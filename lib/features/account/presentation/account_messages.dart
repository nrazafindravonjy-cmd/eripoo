import '../../../l10n/generated/app_localizations.dart';
import '../../../security/device_transfer.dart';
import '../../auth/domain/auth_repository.dart';

String authMessage(AppLocalizations l10n, AuthFailure failure) =>
    switch (failure) {
      InvalidCredentials() => l10n.authInvalidCredentials,
      EmailNotConfirmed() => l10n.authEmailNotConfirmed,
      AccountAlreadyExists() => l10n.authAccountExists,
      WeakPassword() => l10n.authWeakPassword,
      InvalidEmail() => l10n.authInvalidEmail,
      TooManyAttempts() => l10n.authTooManyAttempts,
      AuthUnavailable() => l10n.authUnavailable,
    };

String transferMessage(AppLocalizations l10n, TransferFailure failure) =>
    switch (failure) {
      TransferFailure.malformed => l10n.transferMalformed,
      TransferFailure.unsupportedVersion => l10n.transferUnsupported,
      TransferFailure.wrongAccount => l10n.transferWrongAccount,
      TransferFailure.wrongCode => l10n.transferWrongCode,
      TransferFailure.wrongTransfer ||
      TransferFailure.cannotOpen => l10n.transferRetry,
      TransferFailure.expired => l10n.transferExpired,
      TransferFailure.keyDoesNotMatch => l10n.transferKeyMismatch,
    };
