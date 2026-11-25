# Strazh Bot API

Strazh bots are separate records in `public.bots`; creating one does not create an `auth.users` account. Create a bot in the `@BotFather` chat with `/newbot`, then choose a name and a username ending in `bot`. Use `/mybots` to list your bots and `/token @username` to retrieve a token again.

Bots receive ordinary chat messages as plaintext. Messages sent in bot chats are not end-to-end encrypted. Keep bot tokens private: anyone with a token can act as that bot.

## Public server API

The bot API is served publicly by the Supabase instance on the server. Studio's SSH tunnel is only for the admin UI; bot clients do not use localhost or that tunnel. The server-side Edge Runtime provides the Supabase URL and service-role key. `bot-api` has `verify_jwt = false` because it authenticates each request using the BotFather token.

On the current server, the Edge Runtime container mounts `/root/supabase-functions` as its function directory. `/root/supabase/functions` is not mounted, so putting the function there does not make it available to Kong. Install the function in the mounted directory:

```sh
mkdir -p /root/supabase-functions/bot-api
cp /root/supabase/functions/bot-api/index.ts /root/supabase-functions/bot-api/index.ts
```

No database migration or reset is needed for this file copy.

The function uses Supabase's PostgREST HTTP API directly and has no `npm:` imports. This is necessary because the server's Edge Runtime cannot reach `registry.npmjs.org` to resolve npm dependencies at worker startup.

## Authentication and endpoint

```text
POST https://auth.strazh.chat/functions/v1/bot-api
Authorization: Bearer <BOT_TOKEN>
Content-Type: application/json
```

This is the public server endpoint, not localhost. Bot authors need only the BotFather token, with no project URL, anon key, or service-role key. Send the method in the JSON body. Every successful response uses `{"ok":true,"result":...}`; errors use `{"ok":false,"description":"..."}` and an appropriate HTTP status. Requests without a valid bot token are rejected.

After copying the updated function, verify that a POST without a token returns `401 Unauthorized`. Then run the example with a valid token to verify database access.

### Preventing bots from replying to themselves

Stop the running sample bot with `Ctrl+C`, then apply `202611200002_prevent_bot_self_updates.sql` to the server database. It restores the trigger guard that stops a bot's outgoing messages from being enqueued back to that same bot and marks already-queued self-messages as processed. Restart the sample bot after applying the migration.

### Identifying callback users

Apply `202611200003_bot_callback_actor.sql` before deploying this API version. It adds `actor_id` to `bot_updates` and restricts callback inserts to the signed-in user who tapped a button.

### Displaying callback answers

Apply `202611200004_bot_callback_answers.sql` to enable in-chat callback alerts and toasts. `answerCallbackQuery` stores the answer, and the active chat displays it through Realtime. `show_alert: true` opens a dialog; otherwise `text` appears as a toast. The user must still have the chat open and connected when the answer arrives; callback answers are not queued for later display.

The local source tree does not establish whether these migrations have been applied to the remote database. Verify/apply `202611200002`, `202611200003`, and `202611200004` in the server's database before deploying the matching API/client. No database reset is needed.

## Methods

### `getMe`

```json
{"method":"getMe"}
```

Returns the bot's `id`, `name`, `tag`, `description`, `avatar_url`, and `is_verified`.

### `getUpdates`

```json
{"method":"getUpdates","offset":0,"limit":100}
```

Only two update types are defined by the database: `message` and `callback_query`; there is no separate system or membership update type. `getUpdates` returns those two types with a stable shape. Message updates always include `from` (with `id`, `name`, and `tag`, which may individually be `null`), `chat_id`, `message_id` (nullable), and `text` (nullable). Callback updates always include `actor_id` (nullable for old rows), `chat_id`, `message_id` (nullable), and `callback_data` (nullable). `actor_id` is the UUID of the user who pressed the button; apply migration `202611200003` for reliable attribution.

`limit` is an integer from 1 to 100. `offset` is the next update ID to receive. After handling an update, set the next offset to `update_id + 1`; the next poll acknowledges earlier updates, so they will not be returned again. Delivery is at least once: a process can receive an update again if it stops before polling with the next offset.

Message update:

```json
{
  "id": 31,
  "update_id": "31",
  "update_type": "message",
  "from": {"id":"<user UUID>","name":"Name","tag":"username"},
  "chat_id": "<room UUID>",
  "message_id": "<message UUID>",
  "text": "/start",
  "payload": {
    "from": {"id":"<user UUID>","name":"Name","tag":"username"},
    "chat_id":"<room UUID>",
    "text":"/start"
  }
}
```

## BotFather token commands

- `/token @username` reveals the current token to the owner.

Callback update:

```json
{
  "id": 32,
  "update_id": "32",
  "update_type": "callback_query",
  "actor_id": "<user UUID>",
  "from": {"id":"<user UUID>"},
  "chat_id": "<room UUID>",
  "message_id": "<bot message UUID>",
  "callback_data": "confirm",
  "payload": {
    "callback_query": {
      "id": "32",
      "from": {"id":"<user UUID>"},
      "chat_id": "<room UUID>",
      "message_id": "<bot message UUID>",
      "data": "confirm"
    }
  }
}
```

`update_id` is the stable identifier to use for polling offsets. For callback acknowledgements, pass `payload.callback_query.id` as `callback_query_id`.
Callback updates include the verified player ID who tapped the button in `actor_id`, top-level `from`, and `payload.callback_query.from`; callback `from` currently contains only `id`. Message updates include the sender in `from`. Use these UUIDs as stable game-player IDs instead of Telegram numeric IDs.

An inline callback payload is 1–64 UTF-8 bytes. The API validates the encoded byte length and preserves the exact string (including leading/trailing whitespace); it does not truncate it. Maximum-size examples:

```python
ascii_callback = "x" * 64
cyrillic_callback = "я" * 32  # 32 characters, 64 UTF-8 bytes
too_long = "я" * 33           # 66 UTF-8 bytes; rejected with HTTP 400
```

### `sendMessage`

The bot must already be a participant of `chat_id`. Text is limited to 4096 characters. `reply_to_message_id` is optional and must refer to a message in that chat.

```json
{
  "method":"sendMessage",
  "chat_id":"<room UUID>",
  "text":"Choose an action:",
  "reply_to_message_id":"<optional message UUID>",
  "reply_markup":{
    "inline_keyboard":[
      [
        {"text":"Confirm","callback_data":"confirm","style":"success"},
        {"text":"Cancel","callback_data":"cancel","style":"danger"}
      ],
      [{"text":"Open website","url":"https://example.com"}]
    ]
  }
}
```

`reply_markup` may be omitted. An inline keyboard contains 1–100 rows and 1–8 buttons per row. Each button needs a 1–64 character `text` and exactly one of:

- `callback_data`: up to 64 UTF-8 bytes. Tapping queues a `callback_query` update for the bot.
- `url`: a valid `http://` or `https://` URL. Tapping opens the URL; it does not create a callback update.

`style` is optional: `primary` (default), `success`, `danger`, or `secondary`. Buttons are filled and stretch evenly across the message bubble; buttons in one row share its width.
The same Flutter button renderer is used by the Android, iOS, and web app targets.

### `editMessageText`

Only messages previously sent by the authenticated bot can be edited. If `reply_markup` is omitted, the current keyboard is retained; set it to `{"inline_keyboard":[...]}` to replace it, or `null` to remove it.
Edits apply to any existing message owned by the bot; there is no age-based edit TTL. The open chat receives changes through Realtime. `editMessageReplyMarkup` has the same ownership and lifetime rules.

```json
{
  "method":"editMessageText",
  "chat_id":"<room UUID>",
  "message_id":"<bot message UUID>",
  "text":"Updated text",
  "reply_markup":null
}
```

### `deleteMessage`

Only messages previously sent by the authenticated bot can be deleted.
There is no API method for deleting a user's message, including in a direct bot chat. Keep user input in the chat or update the bot's own prompt/message instead.

```json
{
  "method":"deleteMessage",
  "chat_id":"<room UUID>",
  "message_id":"<bot message UUID>"
}
```

Returns `{"ok":true,"result":true}` when deletion succeeds.

### `editMessageReplyMarkup`

Replace or remove the inline keyboard without changing the message text. Only messages previously sent by the authenticated bot can be changed. Pass `reply_markup: null` to remove all buttons.

```json
{
  "method":"editMessageReplyMarkup",
  "chat_id":"<room UUID>",
  "message_id":"<bot message UUID>",
  "reply_markup":{
    "inline_keyboard":[
      [{"text":"Next turn","callback_data":"turn:next","style":"success"}]
    ]
  }
}
```

### `answerCallbackQuery`

Pass the callback query ID from `payload.callback_query.id`. This acknowledges the callback so it is not returned again after polling. `text` is optional and limited to 200 characters. With migration `202611200004_bot_callback_answers.sql` applied, the active chat displays `text` as a dialog when `show_alert` is true and as a toast otherwise.

```json
{
  "method":"answerCallbackQuery",
  "callback_query_id":"32",
  "text":"Received",
  "show_alert":false
}
```

## Telegram features not implemented

- There is no `parse_mode` or `entities` support. `sendMessage` and `editMessageText` accept plain text; Markdown/HTML syntax is shown literally.
- There is no `register_next_step_handler`, FSM, or `force_reply`. Keep per-user conversation state in the bot's own storage and route incoming `message.text` yourself.
- There is no Telegram-compatible bot deep link or `/start` payload URL in the app. A user can open the bot chat and send `/start` (or `/start payload`), but an external link that opens the chat and pre-fills that payload is not supported.
- `sendMessage` returns the stored message ID, not a delivery/read receipt. The Bot API does not expose a delivery/read status method.
- No per-bot request/message rate limit or `429 retry_after` contract is currently implemented. Throttle polling and sends in the bot; do not assume broadcast throughput.

## HTTP errors

| HTTP | Meaning | Typical description / action |
|---|---|---|
| `400` | Invalid request parameters or JSON | Fix the named field and retry. |
| `401` | Missing/invalid bot token | Check the `Authorization: Bearer <BOT_TOKEN>` header; rotate a revoked token through BotFather. |
| `403` | Bot is not a participant of the chat | Add/open the bot in that chat before sending. |
| `404` | Unknown method, message, reply target, or callback | Check the method name and IDs. |
| `405` | Unsupported HTTP method | Use `POST` (or `OPTIONS` for CORS preflight). |
| `413` | Request body exceeds 64 KB | Reduce the request body. |
| `500` | Supabase/runtime error | Check server function logs; do not blindly retry non-idempotent sends. |

There is no `429` response or `retry_after` field at this time. A nonexistent chat and a chat the bot has not joined both currently produce `403` from `sendMessage`.

## Runnable example bot

[`examples/test_bot.py`](../examples/test_bot.py) is a no-dependency Python example. It responds to `/start` and `/help`, echoes text, sends callback and URL inline buttons, and acknowledges callback presses.

Set the token from BotFather as an environment variable, or run the script and enter it at the hidden prompt. Do not put a real token in source control:

```sh
export STRAZH_BOT_TOKEN="<BOT_TOKEN>"
python3 examples/test_bot.py
```

Open the bot's direct chat in Strazh and press **Start** to send `/start`. Stop the script with `Ctrl+C`.

The API supports game-style flows with player-attributed updates, callbacks, and editable keyboards; the bot can store game state in its own backend. Bot tokens do not grant permission to read or mutate users' Encoins balances. Encoins changes must use the app's authenticated, user-authorized flows.
