import { createClient } from "npm:@supabase/supabase-js@2";
import { decryptLoginCode } from "../_shared/phone_login_crypto.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Content-Type": "application/json",
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "GET" && request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const authorization = request.headers.get("Authorization");
    const accessToken = authorization?.match(/^Bearer\s+(.+)$/i)?.[1];
    if (!accessToken) {
      return jsonResponse({ error: "Unauthorized" }, 401);
    }

    const url = requiredEnv("SUPABASE_URL");
    const anonKey = requiredEnv("SUPABASE_ANON_KEY");
    const userClient = createClient(url, anonKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { data: userData, error: userError } =
      await userClient.auth.getUser(accessToken);
    if (userError || !userData.user) {
      return jsonResponse({ error: "Unauthorized" }, 401);
    }

    const serviceClient = createClient(
      url,
      requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
      { auth: { autoRefreshToken: false, persistSession: false } },
    );
    const { data: challenges, error: challengesError } = await serviceClient
      .from("phone_login_challenges")
      .select(
        "id, phone_number, code_ciphertext, created_at, expires_at, seen_at, consumed_at",
      )
      .eq("user_id", userData.user.id)
      .order("created_at", { ascending: true })
      .limit(50);
    if (challengesError) throw challengesError;

    const now = Date.now();
    const result = await Promise.all(
      (challenges ?? []).map(async (challenge) => {
        const isActive = challenge.consumed_at === null &&
          Date.parse(String(challenge.expires_at)) > now;
        return {
          id: challenge.id,
          phone_number: challenge.phone_number,
          login_code: isActive
            ? await decryptLoginCode(String(challenge.code_ciphertext))
            : "",
          created_at: challenge.created_at,
          expires_at: challenge.expires_at,
          seen_at: challenge.seen_at,
          consumed_at: challenge.consumed_at,
        };
      }),
    );
    return jsonResponse({ requests: result });
  } catch (error) {
    console.error("Failed to load phone login challenges:", error);
    return jsonResponse(
      { error: "Не удалось загрузить коды входа" },
      500,
    );
  }
});

function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing required secret: ${name}`);
  return value;
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: corsHeaders,
  });
}
