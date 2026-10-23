import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'home.dart';
import 'l10n/generated/app_localizations.dart';

/// Sign-in, then a TOTP second factor (enrolled on first use): the staff_*
/// functions refuse any session below aal2.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  GoTrueClient get _auth => Supabase.instance.client.auth;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: _auth.onAuthStateChange,
      builder: (context, _) {
        if (_auth.currentSession == null) return const _SignIn();
        final level = _auth.mfa.getAuthenticatorAssuranceLevel().currentLevel;
        if (level != AuthenticatorAssuranceLevels.aal2) return const _Mfa();
        return const Home();
      },
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

class _SignIn extends StatefulWidget {
  const _SignIn();

  @override
  State<_SignIn> createState() => _SignInState();
}

class _SignInState extends State<_SignIn> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _failed = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
    } on AuthException {
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return _Centered(
      children: [
        Text(l.appTitle, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 24),
        TextField(
          controller: _email,
          decoration: InputDecoration(labelText: l.email),
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
        ),
        TextField(
          controller: _password,
          decoration: InputDecoration(labelText: l.password),
          obscureText: true,
          onSubmitted: (_) => _submit(),
        ),
        if (_failed) ...[
          const SizedBox(height: 12),
          Text(
            l.errorSignIn,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(onPressed: _submit, child: Text(l.signIn)),
      ],
    );
  }
}

class _Mfa extends StatefulWidget {
  const _Mfa();

  @override
  State<_Mfa> createState() => _MfaState();
}

class _MfaState extends State<_Mfa> {
  final _code = TextEditingController();
  String? _factorId;
  String? _secret;
  bool _failed = false;

  GoTrueMFAApi get _mfa => Supabase.instance.client.auth.mfa;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    final factors = await _mfa.listFactors();
    final verified = factors.totp
        .where((f) => f.status == FactorStatus.verified)
        .firstOrNull;
    if (verified != null) {
      setState(() => _factorId = verified.id);
      return;
    }
    final enrolled = await _mfa.enroll(issuer: 'Eripoo back-office');
    setState(() {
      _factorId = enrolled.id;
      _secret = enrolled.totp?.secret;
    });
  }

  Future<void> _verify() async {
    final id = _factorId;
    if (id == null) return;
    try {
      await _mfa.challengeAndVerify(factorId: id, code: _code.text.trim());
    } on AuthException {
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final secret = _secret;
    return _Centered(
      children: [
        Text(
          secret == null ? l.mfaVerifyTitle : l.mfaEnrollTitle,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        if (secret != null) ...[
          const SizedBox(height: 12),
          Text(l.mfaEnrollHelp),
          const SizedBox(height: 12),
          SelectableText(
            secret,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _code,
          decoration: InputDecoration(labelText: l.mfaCode),
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          onSubmitted: (_) => _verify(),
        ),
        if (_failed) ...[
          const SizedBox(height: 12),
          Text(
            l.errorMfa,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _factorId == null ? null : _verify,
          child: Text(l.verify),
        ),
        TextButton(
          onPressed: () => Supabase.instance.client.auth.signOut(),
          child: Text(l.signOut),
        ),
      ],
    );
  }
}
