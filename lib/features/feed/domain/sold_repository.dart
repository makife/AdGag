/// SOLD (CLAUDE.md section 7): "This ad sold me." Toggle semantics — press
/// again to remove — enforced atomically server-side (see
/// `toggle_sold_reaction` in supabase/migrations/0007_sold_reactions.sql),
/// not as a client insert-then-delete.
abstract interface class SoldRepository {
  /// Returns the new state: true if now SOLD, false if just un-SOLD.
  Future<bool> toggle(String adId);

  Future<bool> isSoldByCurrentUser(String adId);
}
