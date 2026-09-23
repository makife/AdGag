/// Base type for expected, user-facing failures. Repositories catch raw
/// exceptions (PostgrestException, AuthException, SocketException, ...) at
/// the data layer and rethrow as one of these, so presentation code never
/// pattern-matches on a third-party exception type (CLAUDE.md section 56 —
/// consistent error handling).
sealed class AppException implements Exception {
  const AppException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => "$runtimeType: $message";
}

final class NetworkException extends AppException {
  const NetworkException([super.message = "Network error. Check your connection.", super.cause]);
}

final class AuthException extends AppException {
  const AuthException([super.message = "Authentication failed.", super.cause]);
}

final class NotFoundException extends AppException {
  const NotFoundException([super.message = "Not found.", super.cause]);
}

final class ConflictException extends AppException {
  const ConflictException([super.message = "This action was already performed.", super.cause]);
}

final class ValidationException extends AppException {
  const ValidationException([super.message = "Invalid input.", super.cause]);
}

final class PermissionDeniedException extends AppException {
  const PermissionDeniedException([super.message = "You can't do that.", super.cause]);
}

/// Fallback for anything unexpected. Kept distinct from a bare catch so
/// crash reporting (section 55) can flag these as truly unhandled.
final class UnknownException extends AppException {
  const UnknownException([super.message = "Something went wrong.", super.cause]);
}
