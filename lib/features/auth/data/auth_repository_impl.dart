import "package:supabase_flutter/supabase_flutter.dart" as supa;

import "../../../core/error/app_exception.dart" as app_error;
import "../../../core/utils/app_logger.dart";
import "../domain/app_user.dart";
import "../domain/auth_repository.dart";

/// Supabase-backed [AuthRepository].
///
/// NOTE on social sign-in (section 27): this MVP implementation uses
/// Supabase's hosted OAuth flow (`signInWithOAuth`), which opens an
/// in-app browser session — this is enough to develop and test the rest of
/// the app end to end. Before App Store submission, replace
/// [signInWithApple] with the native `sign_in_with_apple` package +
/// `signInWithIdToken`, which Apple requires for a first-class native
/// experience when Sign in with Apple is offered alongside other social
/// logins. See README.md > External Services for exact credentials needed.
final class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._client);

  final supa.SupabaseClient _client;
  final _log = AppLogger.named("AuthRepository");

  @override
  AppUser? get currentUserOrNull {
    final supa.User? user = _client.auth.currentUser;
    if (user == null) {
      return null;
    }
    // Profile is loaded asynchronously by watchCurrentUser(); this sync
    // getter is only used for a quick "are we logged in at all" check
    // during router redirects, so a minimal stand-in is acceptable there.
    return AppUser(
      id: user.id,
      email: user.email ?? "",
      username: (user.userMetadata?["username"] as String?) ?? "",
      displayName: (user.userMetadata?["username"] as String?) ?? "",
    );
  }

  @override
  Stream<AppUser?> watchCurrentUser() {
    return _client.auth.onAuthStateChange.asyncMap((supa.AuthState state) async {
      final supa.User? user = state.session?.user;
      if (user == null) {
        return null;
      }
      try {
        final Map<String, dynamic> row = await _client
            .from("profiles")
            .select()
            .eq("id", user.id)
            .single();
        return AppUser.fromProfileRow(row, email: user.email ?? "");
      } on supa.PostgrestException catch (e, st) {
        // Profile row may not exist yet for a split second right after
        // sign-up while the DB trigger runs — treat as "not ready" rather
        // than a hard failure.
        _log.warning("Profile fetch failed for ${user.id}", e, st);
        return null;
      }
    });
  }

  @override
  Future<void> signInWithEmail({required String email, required String password}) async {
    try {
      await _client.auth.signInWithPassword(email: email, password: password);
    } on supa.AuthException catch (e) {
      throw app_error.AuthException(e.message, e);
    }
  }

  @override
  Future<void> signUpWithEmail({
    required String email,
    required String password,
    required String username,
  }) async {
    try {
      await _client.auth.signUp(
        email: email,
        password: password,
        // Consumed by the handle_new_user() trigger to seed profiles.username.
        data: <String, dynamic>{"username": username},
      );
    } on supa.AuthException catch (e) {
      throw app_error.AuthException(e.message, e);
    } on supa.PostgrestException catch (e) {
      if (e.code == "23505") {
        throw const app_error.ConflictException("That username is already taken.");
      }
      throw app_error.UnknownException(e.message, e);
    }
  }

  @override
  Future<void> signInWithApple() async {
    try {
      await _client.auth.signInWithOAuth(supa.OAuthProvider.apple);
    } on supa.AuthException catch (e) {
      throw app_error.AuthException(e.message, e);
    }
  }

  @override
  Future<void> signInWithGoogle() async {
    try {
      await _client.auth.signInWithOAuth(supa.OAuthProvider.google);
    } on supa.AuthException catch (e) {
      throw app_error.AuthException(e.message, e);
    }
  }

  @override
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  @override
  Future<bool> isUsernameAvailable(String username) async {
    final List<dynamic> rows = await _client
        .from("profiles")
        .select("id")
        .eq("username", username)
        .limit(1);
    return rows.isEmpty;
  }
}
