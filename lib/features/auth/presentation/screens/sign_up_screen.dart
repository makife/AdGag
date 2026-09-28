import "dart:async" show unawaited;

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../../core/localization/generated/app_localizations.dart";
import "../../../../core/router/route_paths.dart";
import "../../../../core/theme/app_colors.dart";
import "../../../../core/theme/app_spacing.dart";
import "../../../../core/utils/username_validator.dart";
import "../../domain/auth_repository.dart";
import "../auth_error_message.dart";
import "../providers/auth_providers.dart";

/// Sign-up. Email confirmation is on for this project, so a successful
/// sign-up usually does NOT sign the user in: a confirmation link is mailed
/// first. This screen then switches to a "check your email" state instead of
/// silently returning to the form (user report: "sign-up just comes back
/// empty").
class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  /// Set once the confirmation email went out.
  String? _confirmationSentTo;
  bool _resending = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final String email = _emailController.text.trim();
    final SignUpOutcome? outcome = await ref.read(authControllerProvider.notifier).signUpWithEmail(
          email: email,
          password: _passwordController.text,
          username: UsernameValidator.normalize(_usernameController.text),
        );
    if (!mounted || outcome == null) {
      return; // failures are shown by the listener in build()
    }
    switch (outcome) {
      case SignUpOutcome.signedIn:
        break; // the router's auth redirect takes over
      case SignUpOutcome.confirmEmail:
        setState(() => _confirmationSentTo = email);
      case SignUpOutcome.emailTaken:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).authEmailTaken)),
        );
    }
  }

  Future<void> _resend() async {
    final String? email = _confirmationSentTo;
    if (email == null) {
      return;
    }
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() => _resending = true);
    try {
      await ref.read(authRepositoryProvider).resendConfirmation(email);
      messenger.showSnackBar(SnackBar(content: Text(l10n.authCheckEmailTitle)));
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(authErrorMessage(context, e))));
      }
    } finally {
      if (mounted) {
        setState(() => _resending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<void> state = ref.watch(authControllerProvider);
    ref.listen<AsyncValue<void>>(authControllerProvider, (previous, next) {
      if (next.hasError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(authErrorMessage(context, next.error))),
        );
      }
    });

    final String? sentTo = _confirmationSentTo;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: sentTo != null ? _checkEmail(context, l10n, sentTo) : _form(context, l10n, state),
        ),
      ),
    );
  }

  Widget _checkEmail(BuildContext context, AppLocalizations l10n, String email) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Icon(Icons.mark_email_unread_outlined, size: 56, color: AppColors.brandTurquoise),
        const SizedBox(height: AppSpacing.lg),
        Text(l10n.authCheckEmailTitle, style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: AppSpacing.md),
        Text(l10n.authCheckEmailBody(email), style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: AppSpacing.sm),
        Text(l10n.authCheckSpam, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: AppSpacing.xxl),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => context.pushReplacementTo(RoutePaths.signIn),
            child: Text(l10n.authGoToSignIn),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: TextButton(
            onPressed: _resending ? null : () => unawaited(_resend()),
            child: Text(l10n.authResend),
          ),
        ),
      ],
    );
  }

  Widget _form(BuildContext context, AppLocalizations l10n, AsyncValue<void> state) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.authSignUp, style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: AppSpacing.xxl),
          TextFormField(
            controller: _usernameController,
            autocorrect: false,
            decoration: InputDecoration(labelText: l10n.authUsernameLabel),
            onChanged: (String v) {
              final String normalized = UsernameValidator.normalize(v);
              if (normalized != v) {
                _usernameController.value = TextEditingValue(
                  text: normalized,
                  selection: TextSelection.collapsed(offset: normalized.length),
                );
              }
            },
            validator: (String? v) => UsernameValidator.validationError(v ?? "", l10n),
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            autofillHints: const <String>[AutofillHints.email],
            decoration: InputDecoration(labelText: l10n.authEmailLabel),
            validator: (String? v) => (v == null || !v.contains("@")) ? l10n.authInvalidEmail : null,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _passwordController,
            obscureText: true,
            autofillHints: const <String>[AutofillHints.newPassword],
            decoration: InputDecoration(labelText: l10n.authPasswordLabel),
            validator: (String? v) => (v == null || v.length < 8) ? l10n.accountPasswordTooShort : null,
          ),
          const SizedBox(height: AppSpacing.xl),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: state.isLoading ? null : _submit,
              child: state.isLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(l10n.authSignUp),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: TextButton(
              onPressed: () => context.pushReplacementTo(RoutePaths.signIn),
              child: Text(l10n.authHaveAccount),
            ),
          ),
        ],
      ),
    );
  }
}
