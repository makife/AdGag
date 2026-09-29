// delete-ad
//
// Deletes one of the caller's own Ads: hides it at once (the existing
// delete_own_ad RPC, called with the CALLER's JWT so its ownership check
// applies unchanged), then deletes its video at Mux — the privacy policy
// promises the video is removed, not just hidden. The Mux step is
// best-effort: if Mux is unreachable the Ad is still deleted for everyone,
// and the asset stays "pending" (video_asset_deleted_at null) so the next
// delete-ad / delete-account call from this user retries it.
//
// An Ad deleted before Mux reported its asset (still uploading/processing)
// has no asset id yet; mux-webhook deletes such late-arriving assets.
//
// Required secrets: MUX_TOKEN_ID, MUX_TOKEN_SECRET.

import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders, handleCorsPreflight } from "../_shared/cors.ts";
import { cleanUpDeletedAdAssets } from "../_shared/mux.ts";

Deno.serve(async (req: Request) => {
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;

  try {
    if (req.method !== "POST") return json({ error: "METHOD_NOT_ALLOWED" }, 405);

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "AUTH_FAILED" }, 401);

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !anonKey || !serviceRoleKey) {
      return json({ error: "CONFIG_MISSING" }, 500);
    }

    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userError } = await callerClient.auth.getUser();
    if (userError || !userData.user) return json({ error: "AUTH_FAILED" }, 401);
    const callerId = userData.user.id;

    let adId: unknown;
    try {
      adId = (await req.json())?.adId;
    } catch {
      return json({ error: "INVALID_REQUEST" }, 400);
    }
    if (typeof adId !== "string" || adId.length === 0) {
      return json({ error: "INVALID_REQUEST", detail: "adId is required" }, 400);
    }

    const { error: rpcError } = await callerClient.rpc("delete_own_ad", { p_ad_id: adId });
    if (rpcError) {
      return json({ error: "AD_NOT_FOUND", detail: rpcError.message }, 404);
    }

    // This Ad plus any earlier ones whose Mux deletion failed.
    const adminClient = createClient(supabaseUrl, serviceRoleKey);
    const pending = await cleanUpDeletedAdAssets(adminClient, callerId);

    return json({ deleted: true, pendingVideoCleanups: pending }, 200);
  } catch (unexpected) {
    console.error("delete-ad: unexpected error", unexpected);
    return json({ error: "UNEXPECTED_ERROR", detail: String(unexpected).slice(0, 300) }, 500);
  }
});

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
