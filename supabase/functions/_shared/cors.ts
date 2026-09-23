// Shared CORS headers for Edge Functions called directly from the Flutter
// app (mobile builds don't send an Origin header and aren't affected by
// this, but Flutter Web and local `supabase functions serve` testing are).
export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

export function handleCorsPreflight(req: Request): Response | null {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  return null;
}
