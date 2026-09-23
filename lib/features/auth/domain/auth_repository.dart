import "app_user.dart";

/// Abstraction over the auth provider so presentation/controller code never
/// imports `supabase_flutter` directly. Section 27 requires the auth layer
/// stay extensible (Apple/Google/email now, more later) — new providers are
/// added as new methods/params here, not by leaking SDK types upward.
abstract interface class AuthRepository {
  Stream<AppUser?> watchCurrentUser();

  AppUser? get currentUserOrNull;

  Future<void> signInWithEmail({required String email, required String password});

  /// Creates the auth identity. The corresponding `profiles` row is created
  /// server-side by a database trigger (see
  /// supabase/migrations/0002_profiles_and_auth_trigger.sql) — the client
  /// never inserts its own profile row, which would let a user forge
  /// `id`/`username` uniqueness checks (section 28/68).
  Future<void> signUpWithEmail({
    required String email,
    required String password,
    required String username,
  });

  Future<void> signInWithApple();

  Future<void> signInWithGoogle();

  Future<void> signOut();

  /// True if [username] is available. Server-validated at insert time too
  /// (unique constraint) — this is a UX convenience, not the source of
  /// truth (section 24: "Do not trust client-side validation alone").
  Future<bool> isUsernameAvailable(String username);
}
