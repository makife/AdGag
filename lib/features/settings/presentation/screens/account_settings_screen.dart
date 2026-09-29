import "dart:async" show unawaited;

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../../core/localization/generated/app_localizations.dart";
import "../../../../core/theme/app_spacing.dart";
import "../../../auth/presentation/providers/auth_providers.dart";

/// Settings > Account: the private account details (email is never shown
/// anywhere public — CLAUDE.md section 45), password change, and account
/// deletion (Google Play / App Store require an in-app path).
class AccountSettingsScreen extends ConsumerWidget {
  const AccountSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String email = ref.watch(currentAppUserProvider).valueOrNull?.email ?? "";

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsAccount)),
      body: ListView(
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: Text(l10n.accountEmail),
            subtitle: Text("$email\n${l10n.accountEmailNote}"),
            isThreeLine: true,
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: Text(l10n.accountChangePassword),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => unawaited(
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => const _ChangePasswordSheet(),
              ),
            ),
          ),
          const Divider(height: AppSpacing.xxl),
          ListTile(
            leading: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
            title: Text(l10n.accountDelete, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            subtitle: Text(l10n.accountDeleteSubtitle),
            onTap: () => unawaited(
              showDialog<void>(context: context, builder: (_) => const _DeleteAccountDialog()),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChangePasswordSheet extends ConsumerStatefulWidget {
  const _ChangePasswordSheet();

  @override
  ConsumerState<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends ConsumerState<_ChangePasswordSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).changePassword(_password.text);
      if (!mounted) {
        return;
      }
      final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text(l10n.accountPasswordChanged)));
    } catch (e) {
      if (mounted) {
        setState(() => _error = "$e");
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(l10n.accountChangePassword, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _password,
              obscureText: true,
              autofillHints: const <String>[AutofillHints.newPassword],
              decoration: InputDecoration(labelText: l10n.accountNewPassword),
              validator: (String? v) => (v == null || v.length < 8) ? l10n.accountPasswordTooShort : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _confirm,
              obscureText: true,
              decoration: InputDecoration(labelText: l10n.accountConfirmPassword),
              validator: (String? v) => v != _password.text ? l10n.accountPasswordMismatch : null,
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: _saving ? null : () => unawaited(_save()),
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(l10n.genericSave),
            ),
          ],
        ),
      ),
    );
  }
}

/// Permanent account deletion. The user types their username to confirm —
/// a deliberate step for something that can't be undone.
class _DeleteAccountDialog extends ConsumerStatefulWidget {
  const _DeleteAccountDialog();

  @override
  ConsumerState<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<_DeleteAccountDialog> {
  final TextEditingController _confirm = TextEditingController();
  bool _deleting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _confirm.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState navigator = Navigator.of(context);
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).deleteAccount();
      // Signed out now: the router's auth redirect leaves Settings.
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(l10n.accountDeleted)));
    } catch (e) {
      if (mounted) {
        setState(() {
          _deleting = false;
          _error = l10n.accountDeleteFailed("$e");
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String username = ref.watch(currentAppUserProvider).valueOrNull?.username ?? "";
    final bool confirmed = username.isNotEmpty && _confirm.text.trim().toLowerCase() == username;
    final Color danger = Theme.of(context).colorScheme.error;

    return AlertDialog(
      title: Text(l10n.accountDeleteTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(l10n.accountDeleteBody),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _confirm,
              enabled: !_deleting,
              autocorrect: false,
              decoration: InputDecoration(labelText: l10n.accountDeleteConfirmHint(username)),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: TextStyle(color: danger)),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _deleting ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.genericCancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: danger, foregroundColor: Theme.of(context).colorScheme.onError),
          onPressed: confirmed && !_deleting ? () => unawaited(_delete()) : null,
          child: _deleting
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(l10n.accountDeleteButton),
        ),
      ],
    );
  }
}
