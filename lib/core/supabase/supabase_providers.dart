import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:supabase_flutter/supabase_flutter.dart";

/// The single [SupabaseClient] instance for the app. [Supabase.initialize]
/// must run in `main()` before this provider is read (see lib/main.dart).
///
/// Every feature repository depends on this provider rather than importing
/// `Supabase.instance.client` directly, so tests can override it with a
/// fake/mocked client without touching feature code.
final Provider<SupabaseClient> supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Emits the current [AuthState] (SIGNED_IN, SIGNED_OUT, TOKEN_REFRESHED,
/// ...). Feature code should prefer [currentUserIdProvider] below rather
/// than reaching into `auth.currentUser` directly.
final StreamProvider<AuthState> authStateChangesProvider = StreamProvider<AuthState>((ref) {
  final SupabaseClient client = ref.watch(supabaseClientProvider);
  return client.auth.onAuthStateChange;
});

/// The authenticated user's id, or null when signed out. RLS policies key
/// off `auth.uid()` server-side; this is purely a client-side convenience
/// for UI state and MUST NOT be trusted as an authorization check anywhere
/// server-mediated (CLAUDE.md section 28/68).
final Provider<String?> currentUserIdProvider = Provider<String?>((ref) {
  final AsyncValue<AuthState> authState = ref.watch(authStateChangesProvider);
  return authState.valueOrNull?.session?.user.id ?? ref.watch(supabaseClientProvider).auth.currentUser?.id;
});
