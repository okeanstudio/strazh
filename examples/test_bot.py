#!/usr/bin/env python3
"""Minimal Strazh bot example using only the Python standard library."""

import json
import getpass
import os
import sys
import time
import urllib.error
import urllib.request


API_URL = "https://auth.strazh.chat/functions/v1/bot-api"
BOT_TOKEN = os.environ.get("STRAZH_BOT_TOKEN") or getpass.getpass(
    "BotFather token: "
).strip()
REQUEST_TIMEOUT = 20


class BotApiError(RuntimeError):
    pass


def api(method, **params):
    request_data = {"method": method, **params}
    request = urllib.request.Request(
        API_URL,
        data=json.dumps(request_data).encode("utf-8"),
        headers={
            "Authorization": "Bearer " + BOT_TOKEN,
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT) as response:
            result = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        try:
            response_body = json.loads(detail)
            detail = response_body.get("description", detail)
            if response_body.get("code"):
                detail += " (code: {})".format(response_body["code"])
        except (json.JSONDecodeError, AttributeError):
            pass
        raise BotApiError("HTTP {}: {}".format(error.code, detail)) from error
    except urllib.error.URLError as error:
        raise BotApiError("Network error: {}".format(error.reason)) from error

    if not result.get("ok"):
        raise BotApiError(result.get("description", "Unknown API error"))
    return result.get("result")


def handle_message(update):
    payload = update.get("payload") or {}
    text = update.get("text") or payload.get("text") or ""
    chat_id = update["chat_id"]

    if text.strip().lower().split(" ", 1)[0] in ("/start", "/help"):
        api(
            "sendMessage",
            chat_id=chat_id,
            text=(
                "Привет! Я тестовый бот Strazh.\n"
                "Напиши мне любой текст — я отвечу."
            ),
            reply_markup={
                "inline_keyboard": [
                    [{"text": "Проверить кнопку", "callback_data": "ping"}],
                    [{"text": "Открыть сайт", "url": "https://example.com"}],
                ]
            },
        )
    else:
        api("sendMessage", chat_id=chat_id, text="Получено: " + text)


def handle_callback(update):
    callback = (update.get("payload") or {}).get("callback_query") or {}
    callback_id = callback.get("id", update.get("update_id", update.get("id")))
    chat_id = update["chat_id"]
    message_id = update.get("message_id")
    callback_data = callback.get("data") or update.get("callback_data") or ""

    api(
        "sendMessage",
        chat_id=chat_id,
        text="Кнопка нажата: " + callback_data,
        **({"reply_to_message_id": message_id} if message_id else {}),
    )
    if callback_id is not None:
        api(
            "answerCallbackQuery",
            callback_query_id=str(callback_id),
            text="Нажатие получено",
            show_alert=False,
        )


def main():
    try:
        bot = api("getMe")
        print("Running as @{}".format(bot["tag"]))
        offset = 0

        while True:
            updates = api("getUpdates", offset=offset, limit=100)
            failed_update = False
            for update in updates:
                update_id = int(update.get("update_id", update.get("id")))
                try:
                    if update.get("update_type") == "callback_query":
                        handle_callback(update)
                    elif update.get("update_type") == "message":
                        handle_message(update)
                except (BotApiError, KeyError, TypeError) as error:
                    print(
                        "Could not process update {}: {}".format(update_id, error),
                        file=sys.stderr,
                    )
                    failed_update = True
                    break
                offset = max(offset, update_id + 1)
            if not updates or failed_update:
                time.sleep(1)
    except KeyboardInterrupt:
        print("\nBot stopped.")
    except BotApiError as error:
        print("Bot API error: {}".format(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
