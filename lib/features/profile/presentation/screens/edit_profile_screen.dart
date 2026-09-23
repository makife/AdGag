import "dart:async" show unawaited;

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../../core/theme/app_spacing.dart";
import "../../../auth/presentation/providers/auth_providers.dart";
import "../../domain/public_profile.dart";
import "../providers/profile_providers.dart";

/// Account settings (CLAUDE.md section 13/24): display name and bio only —
/// the two fields `profiles_update_own`'s column grant
/// (0002_profiles_and_auth_trigger.sql) actually allows a user to change
/// themselves, besides avatar_url. Avatar upload needs a Supabase Storage
/// bucket + RLS policy that doesn't exist yet in this codebase; deliberately
/// not built here — see README.md's editor/profile section for that gap.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  bool _loadedInitial = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(profileRepositoryProvider).updateProfile(
            displayName: _displayNameController.text.trim(),
            bio: _bioController.text.trim(),
          );
      ref.invalidate(currentAppUserProvider);
      final String? username = ref.read(currentAppUserProvider).valueOrNull?.username;
      if (username != null) {
        ref.invalidate(profileByUsernameProvider(username));
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() => _error = "Couldn't save: $e");
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appUserAsync = ref.watch(currentAppUserProvider);
    final String? username = appUserAsync.valueOrNull?.username;

    if (username != null && !_loadedInitial) {
      final PublicProfile? profile = ref.watch(profileByUsernameProvider(username)).valueOrNull;
      if (profile != null) {
        _displayNameController.text = profile.displayName ?? "";
        _bioController.text = profile.bio ?? "";
        _loadedInitial = true;
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Edit profile")),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextField(
                controller: _displayNameController,
                maxLength: 40,
                decoration: const InputDecoration(labelText: "Display name"),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _bioController,
                maxLength: 300,
                maxLines: 3,
                decoration: const InputDecoration(labelText: "Bio"),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : () => unawaited(_save()),
                  child: _saving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text("Save"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
