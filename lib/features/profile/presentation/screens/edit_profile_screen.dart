import "dart:async" show unawaited;
import "dart:io";

import "package:cached_network_image/cached_network_image.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:image_picker/image_picker.dart";

import "../../../../core/theme/app_spacing.dart";
import "../../../auth/presentation/providers/auth_providers.dart";
import "../../domain/public_profile.dart";
import "../providers/profile_providers.dart";

/// Account settings (CLAUDE.md section 13/24): display name, bio, and
/// avatar — the fields `profiles_update_own`'s column grant
/// (0002_profiles_and_auth_trigger.sql) allows a user to change about
/// themselves. Avatar upload goes to the `avatars` Storage bucket
/// (0018_avatar_storage.sql).
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
  bool _uploadingAvatar = false;
  String? _pendingAvatarPath;
  String? _error;

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final XFile? file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (file == null) {
      return;
    }
    setState(() {
      _pendingAvatarPath = file.path;
      _uploadingAvatar = true;
      _error = null;
    });
    try {
      await ref.read(profileRepositoryProvider).uploadAvatar(File(file.path));
      ref.invalidate(currentAppUserProvider);
      final String? username = ref.read(currentAppUserProvider).valueOrNull?.username;
      if (username != null) {
        ref.invalidate(profileByUsernameProvider(username));
      }
    } catch (e) {
      setState(() => _error = "Couldn't upload avatar: $e");
    } finally {
      if (mounted) {
        setState(() => _uploadingAvatar = false);
      }
    }
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
    PublicProfile? profile;

    if (username != null) {
      profile = ref.watch(profileByUsernameProvider(username)).valueOrNull;
      if (profile != null && !_loadedInitial) {
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: GestureDetector(
                  onTap: _uploadingAvatar ? null : () => unawaited(_pickAvatar()),
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      CircleAvatar(
                        radius: 48,
                        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                        backgroundImage: _pendingAvatarPath != null
                            ? FileImage(File(_pendingAvatarPath!))
                            : (profile?.avatarUrl != null
                                ? CachedNetworkImageProvider(profile!.avatarUrl!)
                                : null),
                        child: (_pendingAvatarPath == null && profile?.avatarUrl == null)
                            ? const Icon(Icons.person, size: 40)
                            : null,
                      ),
                      if (_uploadingAvatar)
                        const CircularProgressIndicator()
                      else
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(AppSpacing.xs),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
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
              FilledButton(
                onPressed: _saving ? null : () => unawaited(_save()),
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text("Save"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
