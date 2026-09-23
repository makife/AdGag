import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../../core/supabase/supabase_providers.dart";
import "../../data/auth_repository_impl.dart";
import "../../domain/app_user.dart";
import "../../domain/auth_repository.dart";

final Provider<AuthRepository> authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl(ref.watch(supabaseClientProvider));
});

/// The current app user (auth identity + profile row), or null when signed
/// out. This is the provider the router and most screens should watch.
final StreamProvider<AppUser?> currentAppUserProvider = StreamProvider<AppUser?>((ref) {
  return ref.watch(authRepositoryProvider).watchCurrentUser();
});

enum AuthMode { signIn, signUp }

/// Drives the sign-in/sign-up form: holds submit-in-flight state and
/// surfaces errors as an [AsyncValue] the widget can render directly
/// (loading spinner / error banner) without separate boolean flags.
final class AuthController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {
    // No initial async work; state starts as AsyncData(null).
  }

  Future<void> signInWithEmail({required String email, required String password}) async {
    state = const AsyncLoading<void>();
    state = await AsyncValue.guard(
      () => ref.read(authRepositoryProvider).signInWithEmail(email: email, password: password),
    );
  }

  Future<void> signUpWithEmail({
    required String email,
    required String password,
    required String username,
  }) async {
    state = const AsyncLoading<void>();
    state = await AsyncValue.guard(
      () => ref.read(authRepositoryProvider).signUpWithEmail(
            email: email,
            password: password,
            username: username,
          ),
    );
  }

  Future<void> signInWithApple() async {
    state = const AsyncLoading<void>();
    state = await AsyncValue.guard(() => ref.read(authRepositoryProvider).signInWithApple());
  }

  Future<void> signInWithGoogle() async {
    state = const AsyncLoading<void>();
    state = await AsyncValue.guard(() => ref.read(authRepositoryProvider).signInWithGoogle());
  }

  Future<void> signOut() async {
    state = const AsyncLoading<void>();
    state = await AsyncValue.guard(() => ref.read(authRepositoryProvider).signOut());
  }
}

final AsyncNotifierProvider<AuthController, void> authControllerProvider =
    AsyncNotifierProvider<AuthController, void>(AuthController.new);
