// delete-account
//
// In-app account deletion (Google Play / App Store requirement for apps
// with sign-up; CLAUDE.md section 44). Deletes, for the CALLER only:
//   1. every video of theirs at Mux (Ads in any state that have an asset),
//   2. their avatar files in the `avatars` bucket,
//   3. the auth user — which cascades to profiles and from there to ads,
//      comments, SOLD reactions, follows, blocks, reports they filed,
//      notifications and device tokens (see the FK `on delete cascade`s in
//      the migrations); analytics events keep no user id (set null).
//
// Mux deletion is attempted for every asset but does not block the account
// deletion: an asset Mux fails to delete is logged with its id for manual
// cleanup (the Ad row is gone after step 3, so there is nothing to retry
// from). Uploads still in flight produce assets later; mux-webhook deletes
// assets whose Ad no longer exists.
//
// The request body must be {"confirm": "DELETE"} — a guard against an
// accidental call, not a security measure (the JWT is).
//
// Required secrets: MUX_TOKEN_ID, MUX_TOKEN_SECRET.

import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders, handleCorsPreflight } from "../_shared/cors.ts";
import { deleteMuxAsset } from "../_shared/mux.ts";

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
    const userId = userData.user.id;

    let confirm: unknown;
    try {
      confirm = (await req.json())?.confirm;
    } catch {
      return json({ error: "INVALID_REQUEST" }, 400);
    }
    if (confirm !== "DELETE") return json({ error: "CONFIRMATION_REQUIRED" }, 400);

    const admin = createClient(supabaseUrl, serviceRoleKey);

    // 1. Videos at Mux.
    const { data: ads, error: adsError } = await admin
      .from("ads")
      .select("id, video_asset_id")
      .eq("user_id", userId)
      .not("video_asset_id", "is", null)
      .is("video_asset_deleted_at", null);
    if (adsError) {
      console.error("delete-account: ads lookup failed", adsError);
      return json({ error: "DB_LOOKUP_FAILED" }, 500);
    }
    const failedAssets: string[] = [];
    for (const ad of ads ?? []) {
      if (!(await deleteMuxAsset(ad.video_asset_id))) failedAssets.push(ad.video_asset_id);
    }
    if (failedAssets.length > 0) {
      console.error("delete-account: Mux assets left for manual cleanup", { userId, failedAssets });
    }

    // 2. Avatar files ({userId}/avatar.<ext>).
    const { data: files } = await admin.storage.from("avatars").list(userId);
    if (files && files.length > 0) {
      const { error: removeError } = await admin.storage
        .from("avatars")
        .remove(files.map((f: { name: string }) => `${userId}/${f.name}`));
      if (removeError) console.error("delete-account: avatar removal failed", removeError);
    }

    // 3. The account itself (cascades to every table keyed by the profile).
    const { error: deleteError } = await admin.auth.admin.deleteUser(userId);
    if (deleteError) {
      console.error("delete-account: auth deleteUser failed", deleteError);
      return json({ error: "DELETE_FAILED", detail: deleteError.message }, 500);
    }

    return json({ deleted: true }, 200);
  } catch (unexpected) {
    console.error("delete-account: unexpected error", unexpected);
    return json({ error: "UNEXPECTED_ERROR", detail: String(unexpected).slice(0, 300) }, 500);
  }
});

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
