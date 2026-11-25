type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[];

type BotRow = {
  id: string;
  owner_id: string;
  name: string;
  tag: string;
  description: string;
  avatar_url: string | null;
  token_hash: string;
  is_verified: boolean;
  is_enabled: boolean;
};
type BotProfile = Omit<BotRow, "token_hash">;

type BotApiRest = {
  url: string;
  serviceRoleKey: string;
};
type RestFilter = {
  column: string;
  operator: "eq" | "is" | "lt" | "gte";
  value: string | number | boolean | null;
};
type RestError = { message: string; code?: string };
type RestResult<T> = { data: T | null; error: RestError | null };
type UpdateRow = {
  id: number;
  actor_id: string | null;
  update_type: "message" | "callback_query";
  chat_id: string;
  message_id: string | null;
  callback_data: string | null;
  text: string | null;
  payload: Json;
  created_at: string;
};
type MessageResult = { id: string; room_id: string; created_at: string };

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type InlineButton = {
  [key: string]: Json | undefined;
  text: string;
  callback_data?: string;
  url?: string;
  style?: "primary" | "success" | "danger" | "secondary";
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json({ ok: false, description: "Method not allowed" }, 405);
  }

  const authorization = request.headers.get("authorization") ?? "";
  const tokenMatch = /^Bearer\s+(\S+)$/i.exec(authorization);
  if (!tokenMatch) {
    return json({ ok: false, description: "Unauthorized" }, 401);
  }

  let phase = "reading request";
  try {
    const body = await readRequestBody(request);
    const method = getMethod(body, request.url);
    const tokenHash = await sha256(tokenMatch[1]);
    phase = "initializing Supabase client";
    const supabase = createRestClient(
      requiredEnv("SUPABASE_URL"),
      requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
    );

    phase = "looking up bot token";
    const { data: bot, error: botError } = await restMaybeSingle<BotProfile>(
      supabase,
      "bots",
      "id,owner_id,name,tag,description,avatar_url,is_verified,is_enabled",
      [
        { column: "token_hash", operator: "eq", value: tokenHash },
        { column: "is_enabled", operator: "eq", value: true },
      ],
    );
    if (botError) {
      console.error("Bot token lookup failed:", botError);
      return json(
        {
          ok: false,
          description: safeErrorMessage(botError.message, tokenMatch[1]),
          code: botError.code ?? "BOT_LOOKUP_FAILED",
        },
        500,
      );
    }
    if (!bot) {
      return json({ ok: false, description: "Invalid bot token" }, 401);
    }

    phase = `executing ${method}`;
    switch (method) {
      case "getMe":
        return json({
          ok: true,
          result: {
            id: bot.id,
            name: bot.name,
            tag: bot.tag,
            description: bot.description,
            avatar_url: bot.avatar_url,
            is_verified: bot.is_verified,
          },
        });
      case "getUpdates":
        return await getUpdates(supabase, bot.id, body);
      case "sendMessage":
        return await sendMessage(supabase, bot, body);
      case "editMessageText":
        return await editMessageText(supabase, bot.id, body);
      case "editMessageReplyMarkup":
        return await editMessageReplyMarkup(supabase, bot.id, body);
      case "deleteMessage":
        return await deleteMessage(supabase, bot.id, body);
      case "answerCallbackQuery":
        return await answerCallbackQuery(supabase, bot.id, body);
      default:
        return json({ ok: false, description: "Unknown method" }, 404);
    }
  } catch (error) {
    if (error instanceof ApiError) {
      return json({ ok: false, description: error.message }, error.status);
    }
    const errorMessage = error instanceof Error ? error.message : String(error);
    const diagnostic = {
      phase,
      name: error instanceof Error ? error.name : "UnknownError",
      message: safeErrorMessage(errorMessage, tokenMatch[1]),
    };
    console.error("Bot API request failed:", diagnostic);
    return json(
      {
        ok: false,
        description: `${phase}: ${diagnostic.message}`,
        code: diagnostic.name,
      },
      500,
    );
  }
});

async function getUpdates(
  supabase: BotApiRest,
  botId: string,
  body: Record<string, unknown>,
) {
  const limit = integerParam(body.limit, "limit", 100, 1, 100);
  const offset = integerParam(
    body.offset,
    "offset",
    0,
    0,
    Number.MAX_SAFE_INTEGER,
  );

  if (offset > 0) {
    const { error } = await restRequest(supabase, "bot_updates", {
      method: "PATCH",
      filters: [
        { column: "bot_id", operator: "eq", value: botId },
        { column: "processed_at", operator: "is", value: null },
        { column: "id", operator: "lt", value: offset },
      ],
      body: { processed_at: new Date().toISOString() },
    });
    if (error) throw error;
  }

  const { data, error } = await restRequest<UpdateRow>(
    supabase,
    "bot_updates",
    {
      select:
        "id,actor_id,update_type,chat_id,message_id,callback_data,text,payload,created_at",
      filters: [
        { column: "bot_id", operator: "eq", value: botId },
        { column: "processed_at", operator: "is", value: null },
        { column: "id", operator: "gte", value: offset },
      ],
      order: "id.asc",
      limit,
    },
  );
  if (error) throw error;

  const updates = (data ?? []).map((update) => {
    const updateId = String(update.id);
    const payload = isRecord(update.payload) ? update.payload : {};
    if (update.update_type !== "callback_query") {
      const originalFrom = isRecord(payload.from) ? payload.from : {};
      return {
        id: update.id,
        update_id: updateId,
        update_type: "message" as const,
        chat_id: update.chat_id ?? null,
        message_id: update.message_id ?? null,
        text: update.text ?? null,
        from: {
          id: originalFrom.id ?? null,
          name: originalFrom.name ?? null,
          tag: originalFrom.tag ?? null,
        },
        payload,
        created_at: update.created_at,
      };
    }

    const originalCallback = isRecord(payload.callback_query)
      ? payload.callback_query
      : {};
    const callbackFrom = { id: update.actor_id ?? null };
    return {
      id: update.id,
      update_id: updateId,
      update_type: "callback_query" as const,
      actor_id: update.actor_id ?? null,
      chat_id: update.chat_id ?? null,
      message_id: update.message_id ?? null,
      callback_data: update.callback_data ?? null,
      text: update.text ?? null,
      payload: {
        ...payload,
        callback_query: {
          ...originalCallback,
          id: updateId,
          chat_id: update.chat_id,
          message_id: update.message_id,
          data: update.callback_data,
          from: callbackFrom,
        },
      },
      from: callbackFrom,
      created_at: update.created_at,
    };
  });

  return json({ ok: true, result: updates });
}

async function sendMessage(
  supabase: BotApiRest,
  bot: BotProfile,
  body: Record<string, unknown>,
) {
  const chatId = requiredString(body.chat_id, "chat_id");
  const text = requiredText(body.text);
  const keyboard = parseReplyMarkup(body.reply_markup);
  const replyToId = optionalString(body.reply_to_message_id);

  await requireBotChat(supabase, chatId, String(bot.id));
  if (replyToId) {
    const { data, error } = await restMaybeSingle<{ id: string }>(
      supabase,
      "messages",
      "id",
      [
        { column: "id", operator: "eq", value: replyToId },
        { column: "room_id", operator: "eq", value: chatId },
      ],
    );
    if (error) throw error;
    if (!data) throw new ApiError("Reply message not found", 404);
  }

  const { data, error } = await restMaybeSingle<MessageResult>(
    supabase,
    "messages",
    "id,room_id,created_at",
    [],
    {
      room_id: chatId,
      profile_id: bot.owner_id,
      bot_id: bot.id,
      encrypted_content: text,
      encrypted_content_type: "text/plain",
      sender_name: bot.name,
      sender_tag: bot.tag,
      sender_avatar: bot.avatar_url,
      sender_is_channel: false,
      bot_plaintext: true,
      is_bot_message: true,
      bot_inline_keyboard: keyboard,
      ...(replyToId ? { reply_to_id: replyToId } : {}),
      created_at: new Date().toISOString(),
    },
    "POST",
  );
  if (error) throw error;

  return json({ ok: true, result: data });
}

async function editMessageText(
  supabase: BotApiRest,
  botId: string,
  body: Record<string, unknown>,
) {
  const chatId = requiredString(body.chat_id, "chat_id");
  const messageId = requiredString(body.message_id, "message_id");
  const text = requiredText(body.text);
  const hasMarkup = Object.hasOwn(body, "reply_markup");
  const keyboard = hasMarkup ? parseReplyMarkup(body.reply_markup) : undefined;

  const changes: Record<string, Json | undefined> = {
    encrypted_content: text,
    bot_plaintext: true,
    is_edited: true,
    updated_at: new Date().toISOString(),
  };
  if (hasMarkup) changes.bot_inline_keyboard = keyboard;

  const { data, error } = await restMaybeSingle<MessageResult>(
    supabase,
    "messages",
    "id,room_id,created_at",
    [
      { column: "id", operator: "eq", value: messageId },
      { column: "room_id", operator: "eq", value: chatId },
      { column: "bot_id", operator: "eq", value: botId },
      { column: "is_bot_message", operator: "eq", value: true },
    ],
    changes,
    "PATCH",
  );
  if (error) throw error;
  if (!data) throw new ApiError("Bot message not found", 404);
  return json({ ok: true, result: data });
}

async function deleteMessage(
  supabase: BotApiRest,
  botId: string,
  body: Record<string, unknown>,
) {
  const chatId = requiredString(body.chat_id, "chat_id");
  const messageId = requiredString(body.message_id, "message_id");

  const { data, error } = await restMaybeSingle<{ id: string }>(
    supabase,
    "messages",
    "id",
    [
      { column: "id", operator: "eq", value: messageId },
      { column: "room_id", operator: "eq", value: chatId },
      { column: "bot_id", operator: "eq", value: botId },
      { column: "is_bot_message", operator: "eq", value: true },
    ],
    undefined,
    "DELETE",
  );
  if (error) throw error;
  if (!data) throw new ApiError("Bot message not found", 404);
  return json({ ok: true, result: true });
}

async function editMessageReplyMarkup(
  supabase: BotApiRest,
  botId: string,
  body: Record<string, unknown>,
) {
  const chatId = requiredString(body.chat_id, "chat_id");
  const messageId = requiredString(body.message_id, "message_id");
  if (!Object.hasOwn(body, "reply_markup")) {
    throw new ApiError("reply_markup is required", 400);
  }
  const keyboard = parseReplyMarkup(body.reply_markup);
  const { data, error } = await restMaybeSingle<MessageResult>(
    supabase,
    "messages",
    "id,room_id,created_at",
    [
      { column: "id", operator: "eq", value: messageId },
      { column: "room_id", operator: "eq", value: chatId },
      { column: "bot_id", operator: "eq", value: botId },
      { column: "is_bot_message", operator: "eq", value: true },
    ],
    { bot_inline_keyboard: keyboard },
    "PATCH",
  );
  if (error) throw error;
  if (!data) throw new ApiError("Bot message not found", 404);
  return json({ ok: true, result: data });
}

async function answerCallbackQuery(
  supabase: BotApiRest,
  botId: string,
  body: Record<string, unknown>,
) {
  const callbackQueryId = requiredString(
    body.callback_query_id,
    "callback_query_id",
  );
  const callbackQueryNumericId = Number(callbackQueryId);
  if (
    !Number.isSafeInteger(callbackQueryNumericId) ||
    callbackQueryNumericId < 1
  ) {
    throw new ApiError("callback_query_id must be a positive update ID", 400);
  }
  const text = optionalString(body.text);
  if (text != null && text.length > 200) {
    throw new ApiError("text must be 200 characters or fewer", 400);
  }
  const showAlert = body.show_alert === true;

  const { data, error } = await restMaybeSingle<{ id: number }>(
    supabase,
    "bot_updates",
    "id",
    [
      { column: "id", operator: "eq", value: callbackQueryNumericId },
      { column: "bot_id", operator: "eq", value: botId },
      { column: "update_type", operator: "eq", value: "callback_query" },
    ],
    {
      processed_at: new Date().toISOString(),
      callback_answer_text: text,
      callback_answer_show_alert: showAlert,
    },
    "PATCH",
  );
  if (error) throw error;
  if (!data) throw new ApiError("Callback query not found", 404);

  return json({
    ok: true,
    result: { callback_query_id: callbackQueryId, text, show_alert: showAlert },
  });
}

async function requireBotChat(
  supabase: BotApiRest,
  chatId: string,
  botId: string,
) {
  const { data, error } = await restMaybeSingle<{ room_id: string }>(
    supabase,
    "bot_chat_participants",
    "room_id",
    [
      { column: "room_id", operator: "eq", value: chatId },
      { column: "bot_id", operator: "eq", value: botId },
    ],
  );
  if (error) throw error;
  if (!data) throw new ApiError("Bot is not a participant of this chat", 403);
}

function parseReplyMarkup(value: unknown): InlineButton[][] | null {
  if (value == null) return null;
  if (!isRecord(value) || !Array.isArray(value.inline_keyboard)) {
    throw new ApiError("reply_markup.inline_keyboard must be an array", 400);
  }

  const rows = value.inline_keyboard;
  if (rows.length === 0 || rows.length > 100) {
    throw new ApiError("inline_keyboard must contain 1-100 rows", 400);
  }

  return rows.map((row, rowIndex) => {
    if (!Array.isArray(row) || row.length === 0 || row.length > 8) {
      throw new ApiError(
        `inline_keyboard row ${rowIndex + 1} must contain 1-8 buttons`,
        400,
      );
    }
    return row.map((candidate, buttonIndex) => {
      if (!isRecord(candidate)) {
        throw new ApiError("Inline keyboard button must be an object", 400);
      }

      const text = requiredString(candidate.text, "button.text");
      if (text.length > 64) {
        throw new ApiError("Button text must be 64 characters or fewer", 400);
      }
      const callbackData = optionalRawString(candidate.callback_data);
      const url = optionalString(candidate.url);
      const style = optionalString(candidate.style);
      if (
        style != null &&
        !["primary", "success", "danger", "secondary"].includes(style)
      ) {
        throw new ApiError(
          "button.style must be primary, success, danger, or secondary",
          400,
        );
      }
      if ((callbackData == null) === (url == null)) {
        throw new ApiError(
          `Button ${rowIndex + 1}:${
            buttonIndex + 1
          } must have exactly one of callback_data or url`,
          400,
        );
      }
      if (callbackData != null) {
        if (new TextEncoder().encode(callbackData).length > 64) {
          throw new ApiError("callback_data must be 64 bytes or fewer", 400);
        }
        return {
          text,
          callback_data: callbackData,
          ...(style ? { style: style as InlineButton["style"] } : {}),
        };
      }

      let parsedUrl: URL;
      try {
        parsedUrl = new URL(url!);
      } catch {
        throw new ApiError("Button url must be a valid http(s) URL", 400);
      }
      if (!["http:", "https:"].includes(parsedUrl.protocol)) {
        throw new ApiError("Button url must use http or https", 400);
      }
      return {
        text,
        url: parsedUrl.toString(),
        ...(style ? { style: style as InlineButton["style"] } : {}),
      };
    });
  });
}

async function readRequestBody(
  request: Request,
): Promise<Record<string, unknown>> {
  const rawBody = await request.text();
  if (new TextEncoder().encode(rawBody).length > 64 * 1024) {
    throw new ApiError("Request body must be 64 KB or smaller", 413);
  }

  let value: unknown;
  try {
    value = JSON.parse(rawBody);
  } catch {
    throw new ApiError("Request body must be valid JSON", 400);
  }
  if (!isRecord(value)) {
    throw new ApiError("Request body must be a JSON object", 400);
  }
  return value;
}

function getMethod(body: Record<string, unknown>, requestUrl: string) {
  const pathMethod = new URL(requestUrl).pathname.split("/").filter(Boolean)
    .pop();
  const value = body.method ?? (pathMethod === "bot-api" ? null : pathMethod);
  return requiredString(value, "method");
}

function integerParam(
  value: unknown,
  name: string,
  fallback: number,
  min: number,
  max: number,
) {
  if (value == null) return fallback;
  const parsed = typeof value === "number" ? value : Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < min || parsed > max) {
    throw new ApiError(`${name} must be an integer from ${min} to ${max}`, 400);
  }
  return parsed;
}

function requiredText(value: unknown) {
  if (typeof value !== "string" || !value.trim()) {
    throw new ApiError("text is required", 400);
  }
  const text = value;
  if (text.length > 4096) {
    throw new ApiError("text must be 4096 characters or fewer", 400);
  }
  return text;
}

function requiredString(value: unknown, name: string) {
  const result = typeof value === "string" ? value.trim() : "";
  if (!result) throw new ApiError(`${name} is required`, 400);
  return result;
}

function optionalString(value: unknown) {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function optionalRawString(value: unknown) {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function createRestClient(url: string, serviceRoleKey: string): BotApiRest {
  return { url: url.replace(/\/+$/, ""), serviceRoleKey };
}

async function restRequest<T>(
  supabase: BotApiRest,
  table: string,
  options: {
    method?: "GET" | "POST" | "PATCH" | "DELETE";
    select?: string;
    filters?: RestFilter[];
    order?: string;
    limit?: number;
    body?: unknown;
  } = {},
): Promise<RestResult<T[]>> {
  const method = options.method ?? "GET";
  const url = new URL(`${supabase.url}/rest/v1/${encodeURIComponent(table)}`);
  if (options.select) url.searchParams.set("select", options.select);
  if (options.order) url.searchParams.set("order", options.order);
  if (options.limit != null) {
    url.searchParams.set("limit", String(options.limit));
  }
  for (const filter of options.filters ?? []) {
    const value = filter.value === null ? "null" : String(filter.value);
    url.searchParams.append(
      filter.column,
      `${filter.operator}.${value}`,
    );
  }

  const headers = new Headers({
    apikey: supabase.serviceRoleKey,
    Authorization: `Bearer ${supabase.serviceRoleKey}`,
    Accept: "application/json",
  });
  if (options.body !== undefined) {
    headers.set("Content-Type", "application/json");
    headers.set(
      "Prefer",
      options.select ? "return=representation" : "return=minimal",
    );
  }

  const response = await fetch(url, {
    method,
    headers,
    ...(options.body !== undefined
      ? { body: JSON.stringify(options.body) }
      : {}),
    signal: AbortSignal.timeout(10_000),
  });
  const text = await response.text();
  let value: unknown = [];
  if (text) {
    try {
      value = JSON.parse(text);
    } catch {
      if (response.ok) {
        return {
          data: null,
          error: { message: "Supabase REST returned invalid JSON" },
        };
      }
      value = { message: text };
    }
  }

  if (!response.ok) {
    const details = isRecord(value) ? value : {};
    return {
      data: null,
      error: {
        message: typeof details.message === "string"
          ? details.message
          : `Supabase REST request failed (${response.status})`,
        ...(typeof details.code === "string" ? { code: details.code } : {}),
      },
    };
  }
  if (!Array.isArray(value)) {
    return {
      data: null,
      error: { message: "Supabase REST returned an unexpected response" },
    };
  }
  return { data: value as T[], error: null };
}

async function restMaybeSingle<T>(
  supabase: BotApiRest,
  table: string,
  select: string,
  filters: RestFilter[],
  body?: unknown,
  method: "GET" | "POST" | "PATCH" | "DELETE" = "GET",
): Promise<RestResult<T>> {
  const { data, error } = await restRequest<T>(supabase, table, {
    method,
    select,
    filters,
    ...(body !== undefined ? { body } : {}),
  });
  if (error) return { data: null, error };
  if (!data || data.length === 0) return { data: null, error: null };
  if (data.length > 1) {
    return {
      data: null,
      error: {
        message: "Supabase REST returned multiple rows for a single-row query",
        code: "PGRST116",
      },
    };
  }
  return { data: data[0], error: null };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

async function sha256(value: string) {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing environment variable: ${name}`);
  return value;
}

function safeErrorMessage(message: string, token: string) {
  return message
    .replaceAll(token, "[redacted]")
    .replace(/Bearer\s+\S+/gi, "Bearer [redacted]")
    .replace(/\b(?:sb_secret_|eyJ)[A-Za-z0-9._-]{16,}/g, "[redacted]")
    .slice(0, 500);
}

class ApiError extends Error {
  constructor(message: string, readonly status: number) {
    super(message);
  }
}

function json(value: unknown, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
