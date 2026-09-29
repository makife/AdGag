// Mux asset deletion shared by delete-ad, delete-account and mux-webhook.
//
// Required secrets: MUX_TOKEN_ID, MUX_TOKEN_SECRET.

// deno-lint-ignore no-explicit-any
type AdminClient = any;

/** true when the asset is gone at Mux (deleted now, or already absent). */
export async function deleteMuxAsset(assetId: string): Promise<boolean> {
  const tokenId = Deno.env.get("MUX_TOKEN_ID");
  const tokenSecret = Deno.env.get("MUX_TOKEN_SECRET");
  if (!tokenId || !tokenSecret) {
    console.error("deleteMuxAsset: MUX_TOKEN_ID/MUX_TOKEN_SECRET not configured");
    return false;
  }
  try {
    const res = await fetch(`https://api.mux.com/video/v1/assets/${encodeURIComponent(assetId)}`, {
      method: "DELETE",
      headers: { Authorization: "Basic " + btoa(`${tokenId}:${tokenSecret}`) },
    });
    // 204 = deleted; 404 = already gone — both mean nothing is left at Mux.
    if (res.status === 204 || res.status === 404) {
      await res.body?.cancel();
      return true;
    }
    console.error("deleteMuxAsset: Mux DELETE failed", assetId, res.status, (await res.text()).slice(0, 300));
    return false;
  } catch (e) {
    console.error("deleteMuxAsset: fetch failed", assetId, e);
    return false;
  }
}

/**
 * Deletes the Mux assets of this user's deleted Ads that are still pending
 * cleanup (status deleted, asset id known, not yet marked deleted), marking
 * each success. Returns how many are still pending afterwards.
 */
export async function cleanUpDeletedAdAssets(admin: AdminClient, userId: string, limit = 20): Promise<number> {
  const { data: pending, error } = await admin
    .from("ads")
    .select("id, video_asset_id")
    .eq("user_id", userId)
    .eq("status", "deleted")
    .not("video_asset_id", "is", null)
    .is("video_asset_deleted_at", null)
    .limit(limit);
  if (error) {
    console.error("cleanUpDeletedAdAssets: lookup failed", error);
    return -1;
  }
  let remaining = 0;
  for (const ad of pending ?? []) {
    if (await deleteMuxAsset(ad.video_asset_id)) {
      await admin.from("ads").update({ video_asset_deleted_at: new Date().toISOString() }).eq("id", ad.id);
    } else {
      remaining++;
    }
  }
  return remaining;
}
