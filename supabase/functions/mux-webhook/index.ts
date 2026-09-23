// mux-webhook
//
// CLAUDE.md section 43: verify webhook signatures, never trust a bare
// "video ready" POST, map the provider asset id back to the correct Ad,
// and handle delivery idempotently (providers retry on anything but a
// clean 2xx).
//
// IMPORTANT DEPLOYMENT NOTE: this endpoint is called by Mux, not by our
// own authenticated client, so it cannot go through Supabase's default
// per-function JWT verification. It MUST be deployed with JWT
// verification disabled — see supabase/config.toml
// (`[functions.mux-webhook] verify_jwt = false`) — and instead relies
// entirely on the Mux-Signature HMAC check below as its authentication.
// Forgetting the config.toml entry means every delivery 401s before
// reaching this code at all.
//
// Required secret: MUX_WEBHOOK_SIGNING_SECRET (Mux dashboard > Settings >
// Webhooks > your endpoint > Signing secret).

import { createClient } from "npm:@supabase/supabase-js@2";

const SIGNATURE_TOLERANCE_SECONDS = 5 * 60;

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const signingSecret = Deno.env.get("MUX_WEBHOOK_SIGNING_SECRET");
  if (!signingSecret) {
    console.error("mux-webhook: MUX_WEBHOOK_SIGNING_SECRET not configured");
    return new Response("Not configured", { status: 503 });
  }

  const signatureHeader = req.headers.get("Mux-Signature");
  const rawBody = await req.text();

  const verified = signatureHeader
    ? await verifyMuxSignature(rawBody, signatureHeader, signingSecret)
    : false;

  if (!verified) {
    console.warn("mux-webhook: signature verification failed");
    return new Response("Invalid signature", { status: 401 });
  }

  let payload: MuxWebhookPayload;
  try {
    payload = JSON.parse(rawBody);
  } catch {
    return new Response("Invalid JSON", { status: 400 });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const adminClient = createClient(supabaseUrl, serviceRoleKey);

  // Idempotency: record this delivery before acting on it. A primary-key
  // conflict means we've already processed it — treat as success, not an
  // error, since the provider will keep retrying otherwise.
  const eventId = payload.id ?? `${payload.type}:${payload.data?.id ?? "unknown"}:${payload.created_at ?? ""}`;
  const { error: insertError } = await adminClient
    .from("video_webhook_events")
    .insert({ provider: "mux", event_id: eventId });

  if (insertError) {
    if (insertError.code === "23505") {
      return new Response("Already processed", { status: 200 });
    }
    console.error("mux-webhook: failed to record event", insertError);
    return new Response("Internal error", { status: 500 });
  }

  try {
    await handleEvent(adminClient, payload);
  } catch (err) {
    console.error("mux-webhook: handler error", payload.type, err);
    // Still 200: we've recorded the event, and returning a 5xx here would
    // make Mux retry into an idempotency check that already says "done."
    // The failure is logged for investigation instead.
  }

  return new Response("ok", { status: 200 });
});

interface MuxWebhookPayload {
  id?: string;
  type: string;
  created_at?: string;
  data: {
    id?: string;
    passthrough?: string;
    duration?: number;
    playback_ids?: { id: string; policy: string }[];
  };
}

// deno-lint-ignore no-explicit-any
async function handleEvent(adminClient: any, payload: MuxWebhookPayload): Promise<void> {
  const { type, data } = payload;

  switch (type) {
    case "video.asset.ready": {
      const adId = data.passthrough;
      if (!adId) {
        console.warn("mux-webhook: video.asset.ready without passthrough", data.id);
        return;
      }
      const playbackId = data.playback_ids?.[0]?.id;
      const durationMs = typeof data.duration === "number" ? Math.round(data.duration * 1000) : null;

      const { error } = await adminClient
        .from("ads")
        .update({
          status: "ready",
          video_asset_id: data.id,
          playback_id: playbackId,
          thumbnail_url: playbackId ? `https://image.mux.com/${playbackId}/thumbnail.jpg?time=0` : null,
          duration_ms: durationMs,
          published_at: new Date().toISOString(),
        })
        .eq("id", adId)
        .in("status", ["uploading", "processing"]);

      if (error) {
        // Most likely the duration_range CHECK (video outside the 1.5-10s
        // product constraint slipped past client-side trimming/validation).
        // Fail the ad with a clear, recoverable state rather than leaving
        // it stuck "processing" forever (section 19).
        console.error("mux-webhook: failed to mark ad ready, marking failed instead", error);
        await adminClient.from("ads").update({ status: "failed" }).eq("id", adId);
      }
      return;
    }

    case "video.asset.errored": {
      const adId = data.passthrough;
      if (!adId) return;
      await adminClient.from("ads").update({ status: "failed" }).eq("id", adId);
      return;
    }

    case "video.upload.asset_created":
    case "video.asset.created": {
      const adId = data.passthrough;
      if (!adId) return;
      await adminClient
        .from("ads")
        .update({ status: "processing", video_asset_id: data.id })
        .eq("id", adId)
        .eq("status", "uploading");
      return;
    }

    case "video.asset.deleted": {
      // Deletion events may arrive without passthrough per Mux's docs;
      // fall back to the asset-id index (see 0006_video_pipeline.sql).
      if (!data.id) return;
      await adminClient
        .from("ads")
        .update({ status: "deleted", deleted_at: new Date().toISOString() })
        .eq("video_asset_id", data.id);
      return;
    }

    default:
      // Unhandled event types are expected (Mux sends many); no-op.
      return;
  }
}

async function verifyMuxSignature(
  rawBody: string,
  signatureHeader: string,
  secret: string,
): Promise<boolean> {
  const parts = Object.fromEntries(
    signatureHeader.split(",").map((kv) => {
      const [k, v] = kv.split("=");
      return [k.trim(), v?.trim() ?? ""];
    }),
  );
  const timestamp = parts["t"];
  const providedSignature = parts["v1"];
  if (!timestamp || !providedSignature) {
    return false;
  }

  const ageSeconds = Math.abs(Date.now() / 1000 - Number(timestamp));
  if (!Number.isFinite(ageSeconds) || ageSeconds > SIGNATURE_TOLERANCE_SECONDS) {
    return false;
  }

  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signatureBytes = await crypto.subtle.sign("HMAC", key, enc.encode(`${timestamp}.${rawBody}`));
  const expectedHex = Array.from(new Uint8Array(signatureBytes))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");

  return timingSafeEqualHex(expectedHex, providedSignature);
}

function timingSafeEqualHex(a: string, b: string): boolean {
  if (a.length !== b.length) {
    return false;
  }
  let mismatch = 0;
  for (let i = 0; i < a.length; i++) {
    mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return mismatch === 0;
}
