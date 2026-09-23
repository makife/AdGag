import "package:flutter_riverpod/flutter_riverpod.dart";

import "../supabase/supabase_providers.dart";
import "analytics_service.dart";
import "supabase_analytics_service.dart";

final Provider<AnalyticsService> analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  final SupabaseAnalyticsService service = SupabaseAnalyticsService(ref.watch(supabaseClientProvider));
  ref.onDispose(service.dispose);
  return service;
});
