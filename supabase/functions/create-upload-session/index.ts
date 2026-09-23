// create-upload-session
//
// CLAUDE.md section 18/42: video upload sessions are minted server-side so
// the Mux access token/secret never reaches the client, and so we can
// verify the caller actually owns a draft Ad before letting them attach a
// video to it. The client never talks to Mux directly except to PUT the
// video bytes to the short-lived `uploadUrl` this returns.
//
// Required secrets (supabase secrets set ...):
//   MUX_TOKEN_ID, MUX_TOKEN_SECRET
// Auto-provided by the Supabase platform:
//   SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY

import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders, handleCorsPreflight } from "../_shared/cors.ts";

interface RequestBody {
  adId: string;
}

Deno.serve(async (req: Request) => {
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;

  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return json({ error: "Missing Authorization header" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const muxTokenId = Deno.env.get("MUX_TOKEN_ID");
  const muxTokenSecret = Deno.env.get("MUX_TOKEN_SECRET");

  if (!muxTokenId || !muxTokenSecret) {
    console.error("create-upload-session: MUX_TOKEN_ID/MUX_TOKEN_SECRET not configured");
    return json({ error: "Video upload is not configured yet" }, 503);
  }

  // Caller-scoped client: only used to resolve *who* is calling, via their
  // own JWT — never used for privileged writes.
  const callerClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userError } = await callerClient.auth.getUser();
  if (userError || !userData.user) {
    return json({ error: "Invalid session" }, 401);
  }
  const callerId = userData.user.id;

  let body: RequestBody;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }
  if (!body.adId || typeof body.adId !== "string") {
    return json({ error: "adId is required" }, 400);
  }

  // Service-role client: privileged reads/writes, but every write below is
  // still gated on an explicit ownership + status check we do ourselves —
  // bypassing RLS here does not mean bypassing authorization.
  const adminClient = createClient(supabaseUrl, serviceRoleKey);

  const { data: ad, error: adError } = await adminClient
    .from("ads")
    .select("id, user_id, status")
    .eq("id", body.adId)
    .maybeSingle();

  if (adError) {
    console.error("create-upload-session: ad lookup failed", adError);
    return json({ error: "Lookup failed" }, 500);
  }
  if (!ad || ad.user_id !== callerId) {
    return json({ error: "Ad not found" }, 404);
  }
  if (ad.status !== "draft") {
    return json({ error: `Ad is not in a draft state (status=${ad.status})` }, 409);
  }

  const muxResponse = await fetch("https://api.mux.com/video/v1/uploads", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: "Basic " + btoa(`${muxTokenId}:${muxTokenSecret}`),
    },
    body: JSON.stringify({
      cors_origin: "*",
      new_asset_settings: {
        playback_policy: ["public"],
        // Correlates the eventual asset back to our `ads` row without a
        // separate lookup table (see mux-webhook/index.ts).
        passthrough: ad.id,
        max_resolution_tier: "1080p",
      },
    }),
  });

  if (!muxResponse.ok) {
    const errText = await muxResponse.text();
    console.error("create-upload-session: Mux create-upload failed", muxResponse.status, errText);
    return json({ error: "Could not start upload" }, 502);
  }

  const muxBody = await muxResponse.json();
  const uploadUrl: string | undefined = muxBody?.data?.url;
  if (!uploadUrl) {
    console.error("create-upload-session: Mux response missing data.url", muxBody);
    return json({ error: "Could not start upload" }, 502);
  }

  const { error: updateError } = await adminClient
    .from("ads")
    .update({ video_provider: "mux", status: "uploading" })
    .eq("id", ad.id)
    .eq("status", "draft"); // guards against a race with a second concurrent request

  if (updateError) {
    console.error("create-upload-session: failed to mark ad uploading", updateError);
    return json({ error: "Could not start upload" }, 500);
  }

  return json({ uploadUrl }, 200);
});

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
