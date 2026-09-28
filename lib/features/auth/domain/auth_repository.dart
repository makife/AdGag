import "app_user.dart";

/// What happened after a sign-up.
enum SignUpOutcome {
  /// Signed in right away (email confirmation is off).
  signedIn,

  /// Account created; a confirmation link was emailed. No session until the
  /// user opens it (this project has email confirmation on).
  confirmEmail,

  /// The email already has an account. Supabase deliberately reports this
  /// as a "success" with no identities, so it can't be told apart otherwise.
  emailTaken,
}

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
  /// Throws a ConflictException when [username] is already taken.
  Future<SignUpOutcome> signUpWithEmail({
    required String email,
    required String password,
    required String username,
  });

  /// Sends the sign-up confirmation email again.
  Future<void> resendConfirmation(String email);

  Future<void> signInWithApple();

  Future<void> signInWithGoogle();

  Future<void> signOut();

  /// Settings > Account > Password. Sets a password on the signed-in
  /// account (for an OAuth-only account this adds email+password sign-in).
  Future<void> changePassword(String newPassword);

  /// True if [username] is available. Server-validated at insert time too
  /// (unique constraint) — this is a UX convenience, not the source of
  /// truth (section 24: "Do not trust client-side validation alone").
  Future<bool> isUsernameAvailable(String username);
}
