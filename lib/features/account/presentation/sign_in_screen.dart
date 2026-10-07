import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/core_providers.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../sync/remote/sync_remote.dart';
import '../../auth/domain/auth_repository.dart';
import '../../quest/presentation/journey_providers.dart';
import '../application/account_linker.dart';
import 'account_messages.dart';
import 'account_providers.dart';
import 'recovery_screens.dart';

/// Create an account or sign in (e-mail and password, development server
/// only in this phase), then link this phone's data to the account.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key, this.create = false});

  /// Starts on "create an account" rather than "sign in".
  final bool create;

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  late bool _create = widget.create;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final backend = ref.read(accountBackendProvider).value;
    final linker = ref.read(accountLinkerProvider);
    if (backend == null || linker == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final email = _email.text.trim();
      final user = _create
          ? await backend.auth.signUpWithEmail(email, _password.text)
          : await backend.auth.signInWithEmail(email, _password.text);
      final db = ref.read(appDatabaseProvider);
      final result = await linker.link(
        ownerId: user.id,
        localKeys: ref.read(appServicesProvider).keys,
      );
      if (!mounted) return;
      final navigator = Navigator.of(context);
      switch (result) {
        case NewAccountLinked(:final recoveryCode):
          await rememberDeviceLabel(
            db,
            l10n.deviceDefaultName(context.formatter.dateShort(DateTime.now())),
          );
          ref.invalidate(linkedOwnerProvider);
          await navigator.pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => RecoveryCodeShowScreen(code: recoveryCode),
            ),
          );
        case RecoveryNeeded(:final wrap):
          await navigator.pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => UnlockChoiceScreen(ownerId: user.id, wrap: wrap),
            ),
          );
        case AlreadyLinked():
          ref.invalidate(linkedOwnerProvider);
          navigator.pop();
      }
    } on AuthFailure catch (e) {
      _error = authMessage(l10n, e);
    } on AccountMismatch {
      _error = l10n.accountMismatch;
    } on SyncRemoteFailure {
      _error = l10n.authUnavailable;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = _create ? l10n.accountCreate : l10n.accountSignIn;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(EripooSpacing.lg),
        children: [
          ReadableColumn(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.accountGuestBody),
                const SizedBox(height: EripooSpacing.lg),
                EripooTextField(
                  label: l10n.accountEmailLabel,
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  enabled: !_busy,
                ),
                const SizedBox(height: EripooSpacing.md),
                TextField(
                  controller: _password,
                  obscureText: true,
                  enabled: !_busy,
                  decoration: InputDecoration(
                    labelText: l10n.accountPasswordLabel,
                    helperText: _create ? l10n.accountPasswordHelp : null,
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: EripooSpacing.md),
                  Text(
                    _error!,
                    style: context.textStyles.bodyMedium?.copyWith(
                      color: context.colors.danger.base,
                    ),
                  ),
                ],
                const SizedBox(height: EripooSpacing.lg),
                if (_busy) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: EripooSpacing.sm),
                  Text(l10n.accountLinking),
                ] else ...[
                  EripooButton(label: title, onPressed: _submit),
                  const SizedBox(height: EripooSpacing.sm),
                  EripooButton(
                    label: _create ? l10n.accountSignIn : l10n.accountCreate,
                    variant: EripooButtonVariant.tertiary,
                    onPressed: () => setState(() => _create = !_create),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
