/// An AdSubject — the first-class topic entity Ads belong to (e.g. SOCK,
/// MONDAY, MY DAD). Mirrors public.ad_subjects (CLAUDE.md section 3/10).
final class AdSubject {
  const AdSubject({
    required this.id,
    required this.canonicalKey,
    required this.displayName,
    required this.adsCount,
  });

  factory AdSubject.fromRow(Map<String, dynamic> row) {
    return AdSubject(
      id: row["id"] as String,
      canonicalKey: row["canonical_key"] as String,
      displayName: row["display_name"] as String,
      adsCount: (row["ads_count"] as num).toInt(),
    );
  }

  final String id;
  final String canonicalKey;
  final String displayName;
  final int adsCount;
}
