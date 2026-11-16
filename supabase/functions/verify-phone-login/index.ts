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
    const requestId = typeof body.requestId === "string"
      ? body.requestId
      : "";
    const code = typeof body.code === "string"
      ? body.code.replace(/\D/g, "")
      : "";
    if (
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
        .test(requestId) ||
      !/^\d{6}$/.test(code)
    ) {
      return jsonResponse({ error: "Неверный или просроченный код" }, 400);
    }

    const supabaseUrl = requiredEnv("SUPABASE_URL").replace(/\/+$/, "");
    const serviceRoleKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
    const serviceHeaders = {
      apikey: serviceRoleKey,
      Authorization: `Bearer ${serviceRoleKey}`,
      "Content-Type": "application/json",
    };

    const consumeResponse = await fetch(
      `${supabaseUrl}/rest/v1/rpc/verify_phone_login_message`,
      {
        method: "POST",
        headers: serviceHeaders,
        body: JSON.stringify({
          p_request_id: requestId,
          p_code: code,
        }),
      },
    );
    if (!consumeResponse.ok) {
      throw new Error(
        `Challenge verification RPC failed with HTTP ${consumeResponse.status}`,
      );
    }
    const userId = await consumeResponse.json();
    if (typeof userId !== "string") {
      return jsonResponse({ error: "Неверный или просроченный код" }, 400);
    }

    const userResponse = await fetch(
      `${supabaseUrl}/auth/v1/admin/users/${encodeURIComponent(userId)}`,
      { headers: serviceHeaders },
    );
    if (!userResponse.ok) {
      throw new Error(
        `Auth user lookup failed with HTTP ${userResponse.status}`,
      );
    }
    const user = await userResponse.json();
    if (typeof user.email !== "string" || user.email.length === 0) {
      return jsonResponse({ error: "Для аккаунта не подтверждена почта" }, 400);
    }

    const linkResponse = await fetch(
      `${supabaseUrl}/auth/v1/admin/generate_link`,
      {
        method: "POST",
        headers: serviceHeaders,
        body: JSON.stringify({ type: "magiclink", email: user.email }),
      },
    );
    if (!linkResponse.ok) {
      throw new Error(
        `Auth OTP generation failed with HTTP ${linkResponse.status}`,
      );
    }
    const linkData = await linkResponse.json();
    const emailOtp = linkData.email_otp ?? linkData.properties?.email_otp;
    if (typeof emailOtp !== "string" || emailOtp.length === 0) {
      throw new Error("Supabase Auth did not return a one-time OTP");
    }

    return jsonResponse({ email: user.email, emailOtp });
  } catch (error) {
    console.error("Phone login verification failed:", error);
    return jsonResponse(
      { error: "Не удалось выполнить вход. Попробуйте запросить новый код." },
      500,
    );
  }
});

function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: corsHeaders,
  });
}
