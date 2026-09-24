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

// videoeditor5.txt real-device bug: "UnknownException: Could not start
// upload" reached the client with no way to tell which of several very
// different failure modes actually happened — three previously distinct
// server messages ("Mux create-upload failed", "Mux response missing
// data.url", "failed to mark ad uploading") had all been collapsed into
// the identical string "Could not start upload", and — the more
// important structural bug — this handler's body was never wrapped in a
// try/catch at all. Three `Deno.env.get(...)!` non-null assertions meant
// that if any of those (normally always-set, but not something this
// function could ever prove) env vars were ever missing, or literally
// any other unexpected exception occurred anywhere below, Deno would
// throw all the way out of the request handler — which the Supabase
// relay reports as an opaque relay-level failure, NOT a JSON body this
// function controls. That's exactly the shape of failure the client
// side's error handling couldn't turn into anything useful (see
// mux_video_service.dart's own fix in the same round). Every code path
// below now returns a *distinct*, stage-identifying error code, and the
// whole handler is wrapped so an unexpected throw still produces a
// structured response instead of an opaque relay error.
Deno.serve(async (req: Request) => {
  const preflight = handleCorsPreflight(req);
  if (preflight) return preflight;

  try {
    if (req.method !== "POST") {
      return json({ error: "METHOD_NOT_ALLOWED" }, 405);
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return json({ error: "AUTH_FAILED", detail: "Missing Authorization header" }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !anonKey || !serviceRoleKey) {
      // Platform-provided vars — should never actually be missing, but
      // per the bug this round, "should never happen" is exactly the
      // class of failure that must not throw past a try/catch.
      console.error("create-upload-session: platform Supabase env vars missing", {
        hasUrl: !!supabaseUrl,
        hasAnonKey: !!anonKey,
        hasServiceRoleKey: !!serviceRoleKey,
      });
      return json({ error: "UPLOAD_SESSION_CONFIG_MISSING", detail: "Supabase platform env" }, 500);
    }

    const muxTokenId = Deno.env.get("MUX_TOKEN_ID");
    const muxTokenSecret = Deno.env.get("MUX_TOKEN_SECRET");
    if (!muxTokenId || !muxTokenSecret) {
      console.error("create-upload-session: MUX_TOKEN_ID/MUX_TOKEN_SECRET not configured");
      return json({ error: "UPLOAD_SESSION_CONFIG_MISSING", detail: "Mux credentials" }, 503);
    }

    // Caller-scoped client: only used to resolve *who* is calling, via
    // their own JWT — never used for privileged writes.
    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userError } = await callerClient.auth.getUser();
    if (userError || !userData.user) {
      console.error("create-upload-session: auth.getUser failed", userError?.message);
      return json({ error: "AUTH_FAILED", detail: "Invalid session" }, 401);
    }
    const callerId = userData.user.id;

    let body: RequestBody;
    try {
      body = await req.json();
    } catch {
      return json({ error: "INVALID_REQUEST", detail: "Invalid JSON body" }, 400);
    }
    if (!body.adId || typeof body.adId !== "string") {
      return json({ error: "INVALID_REQUEST", detail: "adId is required" }, 400);
    }

    // Service-role client: privileged reads/writes, but every write
    // below is still gated on an explicit ownership + status check we
    // do ourselves — bypassing RLS here does not mean bypassing
    // authorization.
    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    const { data: ad, error: adError } = await adminClient
      .from("ads")
      .select("id, user_id, status")
      .eq("id", body.adId)
      .maybeSingle();

    if (adError) {
      console.error("create-upload-session: ad lookup failed", adError);
      return json({ error: "AD_LOOKUP_FAILED", detail: adError.message }, 500);
    }
    if (!ad || ad.user_id !== callerId) {
      return json({ error: "AD_NOT_FOUND" }, 404);
    }
    if (ad.status !== "draft") {
      return json({ error: "AD_NOT_DRAFT", detail: `status=${ad.status}` }, 409);
    }

    let muxResponse: Response;
    try {
      muxResponse = await fetch("https://api.mux.com/video/v1/uploads", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: "Basic " + btoa(`${muxTokenId}:${muxTokenSecret}`),
        },
        body: JSON.stringify({
          cors_origin: "*",
          new_asset_settings: {
            playback_policy: ["public"],
            // Correlates the eventual asset back to our `ads` row
            // without a separate lookup table (see mux-webhook/index.ts).
            passthrough: ad.id,
            max_resolution_tier: "1080p",
          },
        }),
      });
    } catch (fetchError) {
      // Network-level failure reaching Mux at all (DNS, TLS, timeout) —
      // distinct from Mux reachable-but-rejecting-the-request below.
      console.error("create-upload-session: fetch to Mux failed", fetchError);
      return json({ error: "MUX_UNREACHABLE" }, 502);
    }

    if (!muxResponse.ok) {
      const errText = await muxResponse.text();
      console.error("create-upload-session: Mux create-upload failed", muxResponse.status, errText);
      return json(
        { error: "MUX_UPLOAD_SESSION_FAILED", muxStatus: muxResponse.status, detail: errText.slice(0, 500) },
        502,
      );
    }

    const muxBody = await muxResponse.json();
    const uploadUrl: string | undefined = muxBody?.data?.url;
    if (!uploadUrl) {
      console.error("create-upload-session: Mux response missing data.url", muxBody);
      return json({ error: "MUX_RESPONSE_INVALID" }, 502);
    }

    const { error: updateError } = await adminClient
      .from("ads")
      .update({ video_provider: "mux", status: "uploading" })
      .eq("id", ad.id)
      .eq("status", "draft"); // guards against a race with a second concurrent request

    if (updateError) {
      console.error("create-upload-session: failed to mark ad uploading", updateError);
      return json({ error: "DB_UPDATE_FAILED", detail: updateError.message }, 500);
    }

    return json({ uploadUrl }, 200);
  } catch (unexpected) {
    // The actual structural fix this round: whatever this is, it must
    // still produce a JSON body the client can read, not an opaque
    // Supabase relay-level failure with no actionable message.
    console.error("create-upload-session: unexpected error", unexpected);
    return json({ error: "UNEXPECTED_ERROR", detail: String(unexpected).slice(0, 500) }, 500);
  }
});

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
