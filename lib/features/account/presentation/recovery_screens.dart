import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../security/envelopes.dart';
import '../../../security/key_manager.dart';
import '../../../security/recovery_code.dart';
import '../../../services/platform/secure_window.dart';
import '../../../sync/remote/sync_remote.dart';
import '../../devices/presentation/receive_key_screen.dart';
import '../../quest/presentation/journey_providers.dart';
import '../application/account_linker.dart';
import 'account_providers.dart';

/// Shown once, right after the account was created: the only way back to
/// the data without another device. Never stored, never sent; the screen
/// cannot be captured (FLAG_SECURE).
class RecoveryCodeShowScreen extends StatefulWidget {
  const RecoveryCodeShowScreen({super.key, required this.code});
  final String code;

  @override
  State<RecoveryCodeShowScreen> createState() => _RecoveryCodeShowScreenState();
}

class _RecoveryCodeShowScreenState extends State<RecoveryCodeShowScreen> {
  bool _written = false;
  final _last = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _last.dispose();
    super.dispose();
  }

  void _done() {
    final l10n = AppLocalizations.of(context);
    final expected = widget.code.substring(widget.code.length - 4);
    if (_last.text.trim() != expected) {
      setState(() => _error = l10n.recoveryConfirmWrong);
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SecureScreen(
      child: PopScope(
        // Leaving without confirming would lose the code for good.
        canPop: false,
        child: Scaffold(
          appBar: AppBar(
            title: Text(l10n.recoveryTitle),
            automaticallyImplyLeading: false,
          ),
          body: ListView(
            padding: const EdgeInsets.all(EripooSpacing.lg),
            children: [
              ReadableColumn(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l10n.recoveryShowBody),
                    const SizedBox(height: EripooSpacing.lg),
                    EripooCard(
                      child: Wrap(
                        spacing: EripooSpacing.md,
                        runSpacing: EripooSpacing.sm,
                        alignment: WrapAlignment.center,
                        children: [
                          for (final group in RecoveryCode.groups(widget.code))
                            Text(
                              group,
                              style: context.textStyles.headlineSmall?.copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: EripooSpacing.lg),
                    CheckboxListTile(
                      value: _written,
                      onChanged: (v) => setState(() => _written = v ?? false),
                      title: Text(l10n.recoveryConfirmCheck),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                    if (_written) ...[
                      EripooTextField(
                        label: l10n.recoveryConfirmLast,
                        controller: _last,
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                        errorText: _error,
                      ),
                      const SizedBox(height: EripooSpacing.md),
                      EripooButton(label: l10n.actionDone, onPressed: _done),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The account already has data: open it with the other phone (double
/// QR, the normal way) or with the recovery code (the fallback).
class UnlockChoiceScreen extends StatelessWidget {
  const UnlockChoiceScreen({
    super.key,
    required this.ownerId,
    required this.wrap,
  });

  final String ownerId;
  final RecoveryWrap wrap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.unlockTitle)),
      body: ListView(
        padding: const EdgeInsets.all(EripooSpacing.lg),
        children: [
          ReadableColumn(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.unlockBody),
                const SizedBox(height: EripooSpacing.lg),
                EripooButton(
                  label: l10n.unlockWithPhone,
                  icon: Icons.qr_code_2,
                  onPressed: () => navigator.push(
                    MaterialPageRoute<void>(
                      builder: (_) => ReceiveKeyScreen(ownerId: ownerId),
                    ),
                  ),
                ),
                const SizedBox(height: EripooSpacing.md),
                EripooButton(
                  label: l10n.unlockWithCode,
                  icon: Icons.password,
                  variant: EripooButtonVariant.secondary,
                  onPressed: () => navigator.push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          RecoveryCodeEnterScreen(ownerId: ownerId, wrap: wrap),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Types the recovery code to open the account's data on this phone.
class RecoveryCodeEnterScreen extends ConsumerStatefulWidget {
  const RecoveryCodeEnterScreen({
    super.key,
    required this.ownerId,
    required this.wrap,
  });

  final String ownerId;
  final RecoveryWrap wrap;

  @override
  ConsumerState<RecoveryCodeEnterScreen> createState() =>
      _RecoveryCodeEnterScreenState();
}

class _RecoveryCodeEnterScreenState
    extends ConsumerState<RecoveryCodeEnterScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final l10n = AppLocalizations.of(context);
    final linker = ref.read(accountLinkerProvider);
    if (linker == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await linker.unlockWithRecoveryCode(
        ownerId: widget.ownerId,
        wrap: widget.wrap,
        typedCode: _code.text,
      );
      if (!mounted) return;
      await rememberDeviceLabel(
        ref.read(appDatabaseProvider),
        l10n.deviceDefaultName(context.formatter.dateShort(DateTime.now())),
      );
      // New data key: the app restarts to load it.
      await ref.read(appRestartProvider)();
    } on MalformedRecoveryCode {
      _error = l10n.recoveryMalformed;
    } on WrongRecoveryCode {
      _error = l10n.recoveryWrong;
    } on AccountMismatch {
      _error = l10n.accountMismatch;
    } on RateLimited {
      _error = l10n.recoveryRateLimited;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SecureScreen(
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.recoveryEnterTitle)),
        body: ListView(
          padding: const EdgeInsets.all(EripooSpacing.lg),
          children: [
            ReadableColumn(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _code,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    autocorrect: false,
                    enableSuggestions: false,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d\s-]')),
                    ],
                    decoration: InputDecoration(
                      labelText: l10n.recoveryEnterLabel,
                      errorText: _error,
                    ),
                    minLines: 2,
                    maxLines: 3,
                  ),
                  const SizedBox(height: EripooSpacing.lg),
                  if (_busy) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: EripooSpacing.sm),
                    Text(l10n.recoveryWorking),
                  ] else
                    EripooButton(
                      label: l10n.unlockWithCode,
                      onPressed: _unlock,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
