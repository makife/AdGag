import "package:flutter/widgets.dart";

import "../../../core/error/app_exception.dart";
import "../../../core/localization/generated/app_localizations.dart";

/// Turns a sign-in / sign-up failure into a sentence in the user's language.
/// Supabase reports these as English messages, so the common ones are
/// recognised by their text; anything else is shown as it came.
String authErrorMessage(BuildContext context, Object? error) {
  final AppLocalizations l10n = AppLocalizations.of(context);
  if (error is ConflictException) {
    return l10n.authUsernameTaken;
  }
  final String message = error is AppException ? error.message : "${error ?? ""}";
  final String lower = message.toLowerCase();
  if (lower.contains("invalid login credentials")) {
    return l10n.authWrongCredentials;
  }
  if (lower.contains("email not confirmed")) {
    return l10n.authEmailNotConfirmed;
  }
  if (lower.contains("already registered") || lower.contains("already been registered")) {
    return l10n.authEmailTaken;
  }
  if (lower.contains("database error saving new user")) {
    return l10n.authUsernameTaken;
  }
  return message.trim().isEmpty ? l10n.authGenericError : message;
}
