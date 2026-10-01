import "dart:async";

import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:supabase_flutter/supabase_flutter.dart";

import "../../../../core/supabase/supabase_providers.dart";

/// An Ad's public counters, fresh from the server.
final class AdCounts {
  const AdCounts({required this.sold, required this.comments, required this.shares, required this.adThis});

  final int sold;
  final int comments;
  final int shares;
  final int adThis;

  static int _n(Object? v) => (v as num?)?.toInt() ?? 0;

  static AdCounts fromRow(Map<String, dynamic> row) => AdCounts(
        sold: _n(row["sold_count"]),
        comments: _n(row["comment_count"]),
        shares: _n(row["share_count"]),
        adThis: _n(row["ad_this_count"]),
      );

  /// The "counts" broadcast of 0027_live_ad_counts_and_installations.sql.
  static AdCounts? fromBroadcast(Map<String, dynamic> message) {
    final Object? inner = message["payload"];
    final Map<String, dynamic> m = inner is Map ? Map<String, dynamic>.from(inner) : message;
    if (!m.containsKey("sold") && !m.containsKey("comments")) {
      return null;
    }
    return AdCounts(sold: _n(m["sold"]), comments: _n(m["comments"]), shares: _n(m["shares"]), adThis: _n(m["ad_this"]));
  }
}

/// Live counters of ONE Ad: read once, then kept current by the database's
/// `ad-counts:<id>` Realtime broadcast — someone else's review, SOLD or
/// GAG! shows on everyone's screen at once. Watched only by the Ad on
/// screen (AdVideoCard), so one subscription at a time; auto-disposed (and
/// unsubscribed) when that Ad leaves the screen.
final AutoDisposeStreamProviderFamily<AdCounts, String> liveAdCountsProvider =
    StreamProvider.autoDispose.family<AdCounts, String>((ref, String adId) {
  final SupabaseClient client = ref.watch(supabaseClientProvider);
  final StreamController<AdCounts> out = StreamController<AdCounts>();

  unawaited(
    client
        .from("ads")
        .select("sold_count, comment_count, share_count, ad_this_count")
        .eq("id", adId)
        .maybeSingle()
        .then((Map<String, dynamic>? row) {
      if (row != null && !out.isClosed) {
        out.add(AdCounts.fromRow(row));
      }
    }).catchError((Object _) {}),
  );

  final RealtimeChannel channel = client
      .channel("ad-counts:$adId")
      .onBroadcast(
        event: "counts",
        callback: (Map<String, dynamic> message) {
          final AdCounts? counts = AdCounts.fromBroadcast(message);
          if (counts != null && !out.isClosed) {
            out.add(counts);
          }
        },
      )
      .subscribe();

  ref.onDispose(() {
    unawaited(client.removeChannel(channel));
    unawaited(out.close());
  });
  return out.stream;
});
