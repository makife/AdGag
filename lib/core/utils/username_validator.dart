import "../localization/generated/app_localizations.dart";

/// Username rules (CLAUDE.md section 24). Mirrored server-side by a CHECK
/// constraint in supabase/migrations/0002_profiles_and_auth_trigger.sql —
/// this copy is a UX convenience only, never the enforcement point.
abstract final class UsernameValidator {
  static final RegExp _pattern = RegExp(r"^[a-z][a-z0-9_]{2,19}$");

  static const int minLength = 3;
  static const int maxLength = 20;

  /// Lowercases and strips characters the server would reject, for
  /// as-you-type normalization in the sign-up field.
  static String normalize(String raw) {
    return raw.trim().toLowerCase().replaceAll(RegExp(r"[^a-z0-9_]"), "");
  }

  static bool isValid(String username) => _pattern.hasMatch(username);

  /// Returns a user-facing reason the username is invalid, or null if
  /// valid — in the user's language when [l10n] is given.
  static String? validationError(String username, [AppLocalizations? l10n]) {
    if (username.length < minLength) {
      return l10n?.usernameTooShort("$minLength") ?? "Username must be at least $minLength characters.";
    }
    if (username.length > maxLength) {
      return l10n?.usernameTooLong("$maxLength") ?? "Username must be at most $maxLength characters.";
    }
    if (!RegExp(r"^[a-z]").hasMatch(username)) {
      return l10n?.usernameStartLetter ?? "Username must start with a letter.";
    }
    if (!_pattern.hasMatch(username)) {
      return l10n?.usernameChars ?? "Username can only contain lowercase letters, numbers, and underscores.";
    }
    return null;
  }
}
