import { createClient } from "npm:@supabase/supabase-js@2";
import {
  encryptLoginCode,
  hashLoginCode,
} from "../_shared/phone_login_crypto.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const body = await request.json();
    const phoneNumber = normalizePhone(body.phoneNumber);
    if (
      !phoneNumber ||
      !(
        /^\+888\d{6,14}$/.test(phoneNumber) ||
        /^\+[1-9]\d{6,14}$/.test(phoneNumber)
      )
    ) {
      return jsonResponse({ error: "Проверьте номер телефона" }, 400);
    }

    const supabase = createServiceClient();
    const { data: users, error: lookupError } = await supabase.rpc(
      "lookup_phone_login_user",
      { p_phone_number: phoneNumber },
    );
    if (lookupError) throw lookupError;

    // Return the same shape whether the account exists or not.
    if (!Array.isArray(users) || users.length !== 1) {
      return jsonResponse({
        requestId: crypto.randomUUID(),
        expiresIn: 300,
      });
    }

    const user = users[0] as { user_id?: string; email?: string };
    if (!user.user_id || !user.email) {
      return jsonResponse({
        requestId: crypto.randomUUID(),
        expiresIn: 300,
      });
    }

    const loginCode = randomCode();
    const ipHash = await sha256(
      request.headers.get("cf-connecting-ip") ??
        request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ??
        "unknown",
    );
    const { data: requestId, error: createError } = await supabase.rpc(
      "create_phone_login_challenge",
      {
        p_user_id: user.user_id,
        p_phone_number: phoneNumber,
        p_code_ciphertext: await encryptLoginCode(loginCode),
        p_code_hash: await hashLoginCode(loginCode),
        p_requester_ip_hash: ipHash,
      },
    );
    if (createError) {
      if (createError.message.includes("rate_limited")) {
        return jsonResponse(
          { error: "Слишком много запросов. Попробуйте позже." },
          429,
        );
      }
      throw createError;
    }

    return jsonResponse({ requestId, expiresIn: 300 });
  } catch (error) {
    console.error("Phone login request failed:", error);
    return jsonResponse(
      { error: "Не удалось создать запрос на вход. Попробуйте позже." },
      500,
    );
  }
});

function createServiceClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceRoleKey) {
    throw new Error("Supabase service credentials are not configured");
  }
  return createClient(url, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

function normalizePhone(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const digits = value.replace(/\D/g, "");
  return digits ? `+${digits}` : null;
}

function randomCode(): string {
  const upperLimit = Math.floor(0x1_0000_0000 / 1_000_000) * 1_000_000;
  let value: number;
  do {
    const random = new Uint32Array(1);
    crypto.getRandomValues(random);
    value = random[0];
  } while (value >= upperLimit);
  return (value % 1_000_000).toString().padStart(6, "0");
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: corsHeaders,
  });
}
