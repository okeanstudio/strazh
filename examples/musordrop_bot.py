import os
import json
import random
import datetime
import time
import requests

# ============================== КОНФИГ ==============================
API_URL = "https://auth.strazh.chat/functions/v1/bot-api"
BOT_TOKEN = os.environ.get("STRAZH_BOT_TOKEN", "BOT__ctDC7GwTtayELH_-Fz9zhPi2eqdaUI0UuIiEquoMfA")
ADMIN_ID = os.environ.get("STRAZH_ADMIN_ID", "0bff375f-4888-422a-92be-85198df33209")  # UUID строкой
ADMIN_USERNAME = "@pocker"
MIN_WITHDRAW = 300
STAR = "⭐"
REF_REWARD = 10
DAILY_MIN = 10
DAILY_MAX = 40
DEBUG_UPDATES = False  # включи True для отладки

DEFAULTS = {
    "slots": {"chance": 15, "payout": 3},
    "dice": {"chance": 15, "payout": 2.5},
    "roulette_color": {"chance": 15, "payout": 2.5},
    "roulette_number": {"chance": 5, "payout": 10},
    "case": {"chance": 15, "payout": 1},
    "upgrade": {"chance": 12, "payout": 1.5},
}

CASES = {
    "case_50":   {"name": "📦 Дешёвый кейс",  "price": 50,   "min_value": 25,  "max_value": 45,
                  "items": ["💩 Кусок кала", "🗑 Мусор", "🧦 Рваный носок", "🥔 Гнилая картошка", "🪨 Камень"]},
    "case_100":  {"name": "🎁 Средний кейс",  "price": 100,  "min_value": 50,  "max_value": 90,
                  "items": ["💩 Кусок кала", "🦴 Обглоданная кость", "🍂 Сухой лист", "📄 Мятая бумажка", "🪨 Камень"]},
    "case_500":  {"name": "💼 Дорогой кейс",  "price": 500,  "min_value": 250, "max_value": 450,
                  "items": ["💩 Кусок кала", "🧻 Использованная бумага", "👞 Старый ботинок", "🥾 Дырявый сапог", "🪵 Трухлявое бревно"]},
    "case_1000": {"name": "👑 Элитный кейс",  "price": 1000, "min_value": 500, "max_value": 900,
                  "items": ["💩 Кусок кала", "🦠 Плесень", "🪳 Таракан", "🐀 Дохлая крыса", "🧟 Зомби-пыль"]},
}

UPGRADE_ITEMS = {
    "💩 Какашка": 10, "🗑 Мусор": 25, "🧦 Носок": 50, "🪨 Камень": 100,
    "🥔 Картошка": 200, "🔪 Нож": 500, "💎 Бриллиант": 1000,
    "👑 Корона": 2500, "🏆 Кубок": 5000,
}

# ============================== IN-MEMORY STATE ==============================
BALANCES = {}
USERNAMES = {}
REFERRERS = {}
DAILY = {}
BANNED = {}
TRACKED = set()
CUSH = {}
FAKE_STATE = {}
WITHDRAW_REQUESTS = {}
NEXT_RID = [1]
USER_STATE = {}
SETTINGS = {}
OFFSET = [0]
BOT_ID = [None]

def init_settings():
    for g, data in DEFAULTS.items():
        SETTINGS.setdefault(f"chance_{g}", str(data["chance"]))
        SETTINGS.setdefault(f"payout_{g}", str(data["payout"]))
    SETTINGS.setdefault("maintenance", "0")

init_settings()

# ============================== API CLIENT ==============================
def api_call(method, **params):
    if not BOT_TOKEN:
        raise RuntimeError("STRAZH_BOT_TOKEN is not set")
    payload = {"method": method}
    payload.update(params)
    r = requests.post(
        API_URL,
        json=payload,
        headers={"Authorization": f"Bearer {BOT_TOKEN}", "Content-Type": "application/json"},
        timeout=30,
    )
    try:
        data = r.json()
    except Exception:
        data = {"ok": False, "description": f"bad json (HTTP {r.status_code}): {r.text[:200]}"}
    if not data.get("ok"):
        raise RuntimeError(data.get("description", f"HTTP {r.status_code}"))
    return data.get("result")

def send_message(chat_id, text, reply_markup=None):
    text = (text or "")[:4096]
    params = {"chat_id": chat_id, "text": text}
    if reply_markup is not None:
        params["reply_markup"] = reply_markup
    try:
        return api_call("sendMessage", **params)
    except Exception as e:
        print("sendMessage error:", e)
        return None

def edit_text(chat_id, message_id, text, reply_markup=None):
    """Чистый editMessageText. Клавиатура обновляется через reply_markup."""
    text = (text or "")[:4096]
    params = {"chat_id": chat_id, "message_id": message_id, "text": text}
    if reply_markup is not None:
        params["reply_markup"] = reply_markup
    try:
        return api_call("editMessageText", **params)
    except Exception as e:
        print("editMessageText error:", e)
        return None

def delete_message(chat_id, message_id):
    try:
        return api_call("deleteMessage", chat_id=chat_id, message_id=message_id)
    except Exception as e:
        print("deleteMessage error:", e)
        return None

def answer_cb(cb_id, text="", show_alert=False):
    try:
        return api_call("answerCallbackQuery",
                        callback_query_id=cb_id,
                        text=text or "",
                        show_alert=show_alert)
    except Exception as e:
        print("answerCallbackQuery error:", e)
        return None

# ============================== HELPERS ==============================
def fmt(n):
    return f"{n:,}".replace(",", " ")

def _truncate_utf8(s, max_bytes=64):
    b = s.encode("utf-8")
    if len(b) <= max_bytes:
        return s
    return b[:max_bytes].decode("utf-8", errors="ignore")

def kb(rows):
    return {"inline_keyboard": rows}

def btn(text, data=None, url=None, style="primary"):
    b = {"text": _truncate_utf8(text, 64)}
    if data is not None:
        b["callback_data"] = _truncate_utf8(data, 64)
    elif url is not None:
        b["url"] = url
    b["style"] = style
    return b

def get_balance(uid):
    BALANCES.setdefault(uid, 0)
    return BALANCES[uid]

def update_balance(uid, amount):
    old = get_balance(uid)
    BALANCES[uid] = old + amount
    return BALANCES[uid]

def notify_trackers(uid, old, new, reason):
    if uid not in TRACKED or not ADMIN_ID:
        return
    delta = new - old
    sign = "+" if delta >= 0 else ""
    uname = USERNAMES.get(uid) or uid
    send_message(ADMIN_ID,
                 f"📊 Баланс изменён\n\n👤 @{uname} (ID: {uid})\n"
                 f"{STAR} Было: {old} → Стало: {new}\n{sign}{delta} {STAR}\n"
                 f"📝 Причина: {reason}")

def set_balance(uid, amount, reason="setbalance"):
    old = get_balance(uid)
    BALANCES[uid] = amount
    notify_trackers(uid, old, amount, reason)

def remember_username(uid, uname):
    if uname:
        USERNAMES[uid] = uname.lower()

def get_user_info(uid):
    return {
        "balance": get_balance(uid),
        "username": USERNAMES.get(uid),
        "referrer_id": REFERRERS.get(uid, ""),
        "daily_date": DAILY.get(uid, ("", 0))[0],
        "daily_amount": DAILY.get(uid, ("", 0))[1],
        "banned": 1 if uid in BANNED else 0,
        "ban_reason": BANNED.get(uid, ""),
        "tracked": 1 if uid in TRACKED else 0,
    }

def is_banned(uid):
    return (uid in BANNED, BANNED.get(uid, ""))

def find_user_id_by_username(uname):
    uname = uname.lower().lstrip("@")
    for uid, tag in USERNAMES.items():
        if tag == uname:
            return uid
    return None

def is_maintenance():
    return SETTINGS.get("maintenance", "0") == "1"

def get_chance(g):
    try:
        return int(SETTINGS.get(f"chance_{g}", DEFAULTS[g]["chance"]))
    except Exception:
        return DEFAULTS[g]["chance"]

def get_payout(g):
    try:
        return float(SETTINGS.get(f"payout_{g}", DEFAULTS[g]["payout"]))
    except Exception:
        return DEFAULTS[g]["payout"]

def roll_win(g):
    return random.randint(1, 100) <= get_chance(g)

def set_cush(uid, amount):
    CUSH[uid] = amount

def pop_cush(uid):
    return CUSH.pop(uid, None)

def set_user_state(uid, state, payload=None):
    USER_STATE[uid] = {"state": state, "payload": payload or {}}

def get_user_state(uid):
    st = USER_STATE.get(uid)
    if not st:
        return None, {}
    return st["state"], st["payload"]

def clear_user_state(uid):
    USER_STATE.pop(uid, None)

def check_banned_or_maint(uid, cid, cb_id=None):
    if is_maintenance() and uid != ADMIN_ID:
        msg = "🔧 Технический перерыв."
        if cb_id:
            answer_cb(cb_id, msg, show_alert=True)
        else:
            send_message(cid, msg)
        return True
    banned, reason = is_banned(uid)
    if banned and uid != ADMIN_ID:
        msg = f"🚫 Ты забанен.\nПричина: {reason or 'не указана'}"
        if cb_id:
            answer_cb(cb_id, msg, show_alert=True)
        else:
            send_message(cid, msg)
        return True
    return False

# ============================== KEYBOARDS ==============================
def main_menu():
    rows = [
        [btn("🎰 Слоты", "play_slots"), btn("🎲 Кости", "play_dice")],
        [btn("🎡 Рулетка", "roulette_menu"), btn("📦 Кейсы", "cases_menu")],
        [btn("📈 Апгрейдер", "upgrade_menu"), btn("🎁 Ежедневка", "daily_bonus")],
        [btn("👥 Рефералка", "referral_menu"), btn("💰 Баланс", "check_balance")],
        [btn("👤 Профиль", "profile"), btn(f"{STAR} Пополнить", "topup_request")],
        [btn("💸 Вывод", "withdraw", style="success")],
    ]
    return kb(rows)

def bet_menu(game):
    return kb([
        [btn("50", f"bet_{game}_50"), btn("100", f"bet_{game}_100"), btn("500", f"bet_{game}_500")],
        [btn("✍️ Своя ставка", f"bet_{game}_custom")],
        [btn("⬅️ Назад", "back_menu", style="secondary")],
    ])

def multi_bet_menu(game, bet):
    return kb([
        [btn("x1", f"mult_{game}_{bet}_1"), btn("x3", f"mult_{game}_{bet}_3"),
         btn("x5", f"mult_{game}_{bet}_5"), btn("x10", f"mult_{game}_{bet}_10")],
        [btn("⬅️ Назад", "back_menu", style="secondary")],
    ])

def roulette_type_menu(bet):
    return kb([
        [btn("🔴 Красное", f"rt_red_{bet}", style="danger"),
         btn("⚫ Чёрное", f"rt_black_{bet}", style="secondary")],
        [btn("🎯 Число", f"rt_number_{bet}"), btn("⬅️ Назад", "roulette_menu", style="secondary")],
    ])

def cases_menu():
    rows = [[btn(f"{d['name']} — {d['price']} {STAR}", f"open_{k}")] for k, d in CASES.items()]
    rows.append([btn("⬅️ Назад", "back_menu", style="secondary")])
    return kb(rows)

def case_multi_menu(key):
    return kb([
        [btn("x1", f"cmult_{key}_1"), btn("x3", f"cmult_{key}_3"),
         btn("x5", f"cmult_{key}_5"), btn("x10", f"cmult_{key}_10")],
        [btn("⬅️ Назад", "cases_menu", style="secondary")],
    ])

def upgrade_menu():
    rows = [[btn(f"{item} ({price}{STAR})", f"upg_{price}")] for item, price in UPGRADE_ITEMS.items()]
    rows.append([btn("⬅️ Назад", "back_menu", style="secondary")])
    return kb(rows)

def upgrade_target_menu(current_price):
    rows = []
    for item, price in UPGRADE_ITEMS.items():
        if price > current_price:
            rows.append([btn(f"{item} ({price}{STAR})", f"upgt_{current_price}_{price}")])
    rows.append([btn("⬅️ Назад", "upgrade_menu", style="secondary")])
    return kb(rows)

def fake_game_menu():
    return kb([
        [btn("🎰 Слоты", "fk_slots"), btn("🎲 Кости", "fk_dice")],
        [btn("🎡 Рулетка", "fk_roulette"), btn("📦 Кейс", "fk_case")],
        [btn("⬅️ Отмена", "back_menu", style="secondary")],
    ])

def withdraw_admin_menu(rid):
    return kb([
        [btn("✅ Подтвердить", f"wadm_ok_{rid}", style="success"),
         btn("❌ Отклонить", f"wadm_no_{rid}", style="danger")],
    ])

def chance_menu():
    return kb([
        [btn("🟢 Щедро (макс 30%)", "pres_ALL_shedro")],
        [btn("🟡 Стандарт (макс 15%)", "pres_ALL_standart")],
        [btn("🔴 Жадно (макс 12%)", "pres_ALL_greedy")],
        [btn("⚫ Всем везёт (100%)", "pres_ALL_100")],
        [btn("⛔ Никому (0%)", "pres_ALL_0", style="danger")],
    ])

def back_menu_kb():
    return kb([[btn("⬅️ Назад", "back_menu", style="secondary")]])

def ref_menu():
    return kb([
        [btn("🔗 Ввести код друга", "enter_ref")],
        [btn("⬅️ Назад", "back_menu", style="secondary")],
    ])

# ============================== ЛОГИКА ИГР ==============================
def do_slots_or_dice(uid, cid, game, bet, count):
    total_cost = bet * count
    if get_balance(uid) < total_cost:
        send_message(cid, f"❌ Нужно {fmt(total_cost)} {STAR}!", reply_markup=back_menu_kb())
        return
    old = get_balance(uid)
    update_balance(uid, -total_cost)
    notify_trackers(uid, old, get_balance(uid), f"мульти {game}")
    cush = pop_cush(uid)
    chance = get_chance("slots" if game == "slots" else "dice")
    payout = get_payout("slots" if game == "slots" else "dice")
    if chance == 0:
        max_wins = 0
    elif chance >= 60:
        max_wins = max(1, count // 3)
    elif chance >= 45:
        max_wins = max(1, count // 4)
    else:
        max_wins = max(1, count // 5)
    win_positions = set(random.sample(range(count), min(max_wins, count))) if max_wins > 0 else set()

    wins = 0
    total_win = 0
    lines = []
    for i in range(count):
        if i == 0 and cush is not None:
            update_balance(uid, cush)
            total_win += cush
            wins += 1
            lines.append(f"🎉 Выигрыш: {fmt(cush)} {STAR}")
            continue
        if i in win_positions:
            if game == "slots":
                sym = random.choice(["🍒", "🍋", "7️⃣", "💎"])
                win = int(bet * payout)
                spin = f"{sym} | {sym} | {sym}"
            else:
                pr = random.randint(2, 6)
                br = random.randint(1, pr - 1)
                win = int(bet * payout)
                spin = f"Ты: {pr} | Бот: {br}"
            update_balance(uid, win)
            total_win += win
            wins += 1
            lines.append(f"{spin} — 🎉 +{fmt(win)} {STAR}")
        else:
            if game == "slots":
                while True:
                    sa = [random.choice(["🍒", "🍋", "7️⃣", "💎"]) for _ in range(3)]
                    if not (sa[0] == sa[1] == sa[2]):
                        break
                spin = " | ".join(sa)
            else:
                pr = random.randint(1, 5)
                br = random.randint(pr + 1, 6)
                spin = f"Ты: {pr} | Бот: {br}"
            lines.append(f"{spin} — 😢")
    summary = "\n".join(lines[:15])
    if count > 15:
        summary += f"\n... и ещё {count - 15}"
    net = total_win - total_cost
    sign = "+" if net >= 0 else ""
    msg = (f"🎮 {count} игр по {fmt(bet)} {STAR} (всего {fmt(total_cost)})\n\n{summary}\n\n"
           f"✅ Выигрышных: {wins}/{count}\n💰 Получено: {fmt(total_win)} {STAR}\n"
           f"📊 Итог: {sign}{fmt(net)} {STAR}\n\n{STAR} Баланс: {fmt(get_balance(uid))}")
    send_message(cid, msg, reply_markup=main_menu())

def do_case_open(uid, cid, key, count):
    case = CASES.get(key)
    if not case:
        return
    price = case["price"]
    total_cost = price * count
    if get_balance(uid) < total_cost:
        send_message(cid, f"❌ Нужно {fmt(total_cost)} {STAR}!", reply_markup=back_menu_kb())
        return
    old = get_balance(uid)
    update_balance(uid, -total_cost)
    notify_trackers(uid, old, get_balance(uid), "кейсы")
    cush = pop_cush(uid)
    chance = get_chance("case")
    expected_wins = round(count * chance / 100)
    if chance == 0:
        expected_wins = 0
    elif count >= 3 and expected_wins == 0:
        expected_wins = 1
    expected_wins = min(expected_wins, count)
    win_positions = set(random.sample(range(count), expected_wins)) if expected_wins > 0 else set()
    wins = 0
    total_value = 0
    lines = []
    for i in range(count):
        if i == 0 and cush is not None:
            update_balance(uid, cush)
            total_value += cush
            wins += 1
            lines.append(f"💎 БРИЛЛИАНТ — {fmt(cush)} {STAR}")
            continue
        if i in win_positions:
            item = random.choice(case["items"])
            value = random.randint(case["min_value"], case["max_value"])
            update_balance(uid, value)
            total_value += value
            wins += 1
            lines.append(f"{item} — {fmt(value)} {STAR}")
        else:
            lines.append(f"{random.choice(case['items'])} — 0 {STAR}")
    summary = "\n".join(lines[:15])
    if count > 15:
        summary += f"\n... и ещё {count - 15}"
    net = total_value - total_cost
    sign = "+" if net >= 0 else ""
    msg = (f"📦 Открыто {count}x {case['name']} за {fmt(total_cost)} {STAR}\n\n{summary}\n\n"
           f"✅ Выигрышных: {wins}/{count}\n💰 Итого: {fmt(total_value)} {STAR}\n"
           f"📊 Итог: {sign}{fmt(net)} {STAR}\n\n{STAR} Баланс: {fmt(get_balance(uid))}")
    send_message(cid, msg, reply_markup=main_menu())

# ============================== ВВОД (state-machine) ==============================
def process_withdraw_amount(uid, cid, text):
    try:
        amt = int(text.strip())
    except Exception:
        send_message(cid, "❌ Введи целое число.")
        return
    if amt < MIN_WITHDRAW:
        send_message(cid, f"❌ Минимум: {MIN_WITHDRAW} {STAR}.")
        return
    cur = get_balance(uid)
    if amt > cur:
        send_message(cid, f"❌ У тебя только {fmt(cur)} {STAR}.")
        return
    rid = NEXT_RID[0]
    NEXT_RID[0] += 1
    uname = USERNAMES.get(uid, "")
    WITHDRAW_REQUESTS[rid] = {"user_id": uid, "username": uname, "amount": amt, "status": "pending"}
    send_message(cid, f"💸 Заявка #{rid} на {fmt(amt)} {STAR} создана.", reply_markup=main_menu())
    if ADMIN_ID:
        send_message(ADMIN_ID,
                     f"💸 Заявка #{rid}\n@{uname or 'без_юз'}\nID: {uid}\n"
                     f"Сумма: {fmt(amt)} {STAR}\nБаланс: {fmt(cur)}",
                     reply_markup=withdraw_admin_menu(rid))

def process_custom_bet(uid, cid, text, game):
    try:
        bet = int(text.strip())
    except Exception:
        send_message(cid, "❌ Введи целое число больше 0.")
        return
    if bet < 1:
        send_message(cid, "❌ Ставка > 0.")
        return
    if get_balance(uid) < bet:
        send_message(cid, f"❌ Мало звёзд! У тебя {fmt(get_balance(uid))} {STAR}.", reply_markup=main_menu())
        return
    if game == "roulette":
        send_message(cid, f"🎡 Ставка: {fmt(bet)} {STAR}\nНа что?", reply_markup=roulette_type_menu(bet))
    else:
        send_message(cid, f"Количество игр (ставка {fmt(bet)} {STAR}):", reply_markup=multi_bet_menu(game, bet))

def process_number_bet(uid, cid, text, bet):
    try:
        num = int(text.strip())
        if num < 0 or num > 36:
            raise ValueError
    except Exception:
        send_message(cid, "❌ Число 0-36.")
        return
    if get_balance(uid) < bet:
        send_message(cid, "❌ Мало звёзд!", reply_markup=main_menu())
        return
    old = get_balance(uid)
    update_balance(uid, -bet)
    notify_trackers(uid, old, get_balance(uid), "рулетка число")
    cush = pop_cush(uid)
    payout = get_payout("roulette_number")
    red = {1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36}
    if cush is not None:
        update_balance(uid, cush)
        msg = f"🎡 Выпало: {num}\n🎉 ТОЧНОЕ! Выигрыш: {fmt(cush)} {STAR}!"
    elif get_chance("roulette_number") > 0 and roll_win("roulette_number"):
        w = int(bet * payout)
        update_balance(uid, w)
        msg = f"🎡 Выпало: {num}\n🎉 ТОЧНОЕ! Выигрыш: {fmt(w)} {STAR}!"
    else:
        poss = [n for n in range(37) if n != num]
        r = random.choice(poss)
        rc = "🟢" if r == 0 else ("🔴" if r in red else "⚫")
        msg = f"🎡 Выпало: {r} ({rc})\n😢 Твоё число: {num}. Проигрыш."
    send_message(cid, f"{msg}\n\n{STAR} Баланс: {fmt(get_balance(uid))}", reply_markup=main_menu())

def process_fake_amount(aid, cid, text):
    st = FAKE_STATE.get(aid)
    if not st:
        send_message(cid, "❌ Сессия истекла.")
        return
    tid = st["target"]
    g = st["game"]
    try:
        amt = int(text.strip())
    except Exception:
        send_message(cid, "❌ Введи число.")
        return
    bal = get_balance(tid)
    if g == "slots":
        ft = f"🎰 [ 💎 | 💎 | 💎 ]\n\n🎉 ДЖЕКПОТ! Выигрыш: {fmt(amt)} {STAR}!\n\n{STAR} Баланс: {fmt(amt + bal)}"
    elif g == "dice":
        ft = f"🎲 Ты: 6 | Бот: 1\n\n🎉 Победа! Выигрыш: {fmt(amt)} {STAR}!\n\n{STAR} Баланс: {fmt(amt + bal)}"
    elif g == "roulette":
        ft = f"🎡 Выпало: 17\n\n🎉 ТОЧНОЕ ПОПАДАНИЕ! Выигрыш: {fmt(amt)} {STAR}!\n\n{STAR} Баланс: {fmt(amt + bal)}"
    elif g == "case":
        ft = f"📦 Ты открыл 👑 Элитный кейс\n\nВыпало: 💎 БРИЛЛИАНТ\nЦенность: {fmt(amt)} {STAR}\n\n🎉 УДАЧА!\n\n{STAR} Баланс: {fmt(amt + bal)}"
    else:
        return
    send_message(tid, ft, reply_markup=main_menu())
    send_message(cid, f"✅ Отправлено (ID {tid}).")
    FAKE_STATE.pop(aid, None)

def process_ref_code(uid, cid, text):
    code = text.strip().lstrip("@")
    if code == uid:
        send_message(cid, "❌ Нельзя пригласить себя.")
        return
    if uid in REFERRERS:
        send_message(cid, "❌ Ты уже привязан к рефереру.")
        return
    # Проверяем, что такой юзер существует (по балансу/username)
    if code not in BALANCES and find_user_id_by_username(code) is None:
        send_message(cid, "❌ Код не найден. Попроси друга прислать его ID из /myid.")
        return
    referrer = code if code in BALANCES else find_user_id_by_username(code)
    REFERRERS[uid] = referrer
    update_balance(referrer, REF_REWARD)
    send_message(cid, f"✅ Ты привязан к @{USERNAMES.get(referrer, referrer)}.\nБонус рефереру начислен.",
                 reply_markup=main_menu())

# ============================== ОБРАБОТКА СООБЩЕНИЙ ==============================
def handle_command(uid, cid, text):
    cmd = text.split()[0].lower() if text else ""

    if cmd == "/start":
        if check_banned_or_maint(uid, cid):
            return
        send_message(cid,
                     f"👋 Привет!\n\n{STAR} Твой баланс: {fmt(get_balance(uid))} звёзд.\nВыбери действие:",
                     reply_markup=main_menu())
        return

    if cmd == "/myid":
        send_message(cid, f"Твой ID: {uid}")
        return

    if cmd == "/ref":
        parts = text.split(maxsplit=1)
        if len(parts) < 2:
            send_message(cid, "❌ /ref <ID друга>")
            return
        process_ref_code(uid, cid, parts[1])
        return

    if uid != ADMIN_ID:
        return

    if cmd == "/ban":
        try:
            parts = text.split(maxsplit=2)
            target = parts[1].lstrip("@")
            reason = parts[2] if len(parts) > 2 else "не указана"
            tid = target if len(target) > 20 else find_user_id_by_username(target)
            if not tid:
                send_message(cid, "❌ Не найден.")
                return
            BANNED[tid] = reason
            send_message(cid, f"✅ @{target} забанен. Причина: {reason}")
            send_message(tid, f"🚫 Ты забанен.\nПричина: {reason}")
        except Exception:
            send_message(cid, "❌ /ban @username причина")
        return

    if cmd == "/unban":
        try:
            target = text.split()[1].lstrip("@")
            tid = target if len(target) > 20 else find_user_id_by_username(target)
            if not tid:
                send_message(cid, "❌ Не найден.")
                return
            BANNED.pop(tid, None)
            send_message(cid, f"✅ @{target} разбанен.")
            send_message(tid, "✅ Ты разбанен. Можешь снова играть.")
        except Exception:
            send_message(cid, "❌ /unban @username")
        return

    if cmd == "/track":
        try:
            parts = text.split()
            target = parts[1].lstrip("@")
            state = parts[2].lower()
            tid = target if len(target) > 20 else find_user_id_by_username(target)
            if not tid:
                send_message(cid, "❌ Не найден.")
                return
            if state == "on":
                TRACKED.add(tid)
                send_message(cid, f"✅ @{target} на отслеживании.")
            elif state == "off":
                TRACKED.discard(tid)
                send_message(cid, f"✅ @{target} снят с отслеживания.")
            else:
                send_message(cid, "❌ /track @username on|off")
        except Exception:
            send_message(cid, "❌ /track @username on|off")
        return

    if cmd == "/balance":
        try:
            t = text.split()[1]
            tid = t if len(t) > 20 else find_user_id_by_username(t)
            if not tid:
                send_message(cid, "❌ Не найден.")
                return
            info = get_user_info(tid)
            send_message(cid, f"👤 @{info['username'] or 'без_юз'} (ID: {tid})\n{STAR} Баланс: {fmt(info['balance'])} звёзд.")
        except Exception:
            send_message(cid, "❌ /balance <id | @username>")
        return

    if cmd == "/add":
        try:
            t = text.split()[1]
            amt = int(text.split()[2])
            tid = t if len(t) > 20 else find_user_id_by_username(t)
            if not tid:
                send_message(cid, "❌ Не найден.")
                return
            old = get_balance(tid)
            nb = update_balance(tid, amt)
            notify_trackers(tid, old, nb, "admin add")
            send_message(cid, f"✅ +{fmt(amt)} {STAR}. Баланс: {fmt(nb)} {STAR}.")
        except Exception:
            send_message(cid, "❌ /add <id|@u> <сумма>")
        return

    if cmd == "/remove":
        try:
            t = text.split()[1]
            amt = int(text.split()[2])
            tid = t if len(t) > 20 else find_user_id_by_username(t)
            if not tid:
                send_message(cid, "❌ Не найден.")
                return
            cur = get_balance(tid)
            rm = min(amt, cur)
            old = cur
            nb = update_balance(tid, -rm)
            notify_trackers(tid, old, nb, "admin remove")
            send_message(cid, f"✅ -{fmt(rm)} {STAR}. Баланс: {fmt(nb)} {STAR}.")
        except Exception:
            send_message(cid, "❌ /remove <id|@u> <сумма>")
        return

    if cmd == "/setbalance":
        try:
            t = text.split()[1]
            amt = int(text.split()[2])
            tid = t if len(t) > 20 else find_user_id_by_username(t)
            if not tid:
                send_message(cid, "❌ Не найден.")
                return
            set_balance(tid, amt)
            send_message(cid, f"✅ Баланс = {fmt(amt)} {STAR}.")
        except Exception:
            send_message(cid, "❌ /setbalance <id|@u> <сумма>")
        return

    if cmd == "/chance":
        text_out = (f"⚙️ Шансы\n\n"
                    f"🎰 Слоты: {get_chance('slots')}% (x{get_payout('slots')})\n"
                    f"🎲 Кости: {get_chance('dice')}% (x{get_payout('dice')})\n"
                    f"🎡 Цвет: {get_chance('roulette_color')}% (x{get_payout('roulette_color')})\n"
                    f"🎯 Число: {get_chance('roulette_number')}% (x{get_payout('roulette_number')})\n"
                    f"📦 Кейсы: {get_chance('case')}%\n"
                    f"📈 Апгрейдер: {get_chance('upgrade')}%\n\nВыбери пресет:")
        send_message(cid, text_out, reply_markup=chance_menu())
        return

    if cmd == "/ms":
        try:
            a = text.split()[1].lower()
            if a == "on":
                SETTINGS["maintenance"] = "1"
                send_message(cid, "🔧 ВКЛ.")
            elif a == "off":
                SETTINGS["maintenance"] = "0"
                send_message(cid, "✅ ВЫКЛ.")
        except Exception:
            send_message(cid, "❌ /ms on|off")
        return

    if cmd == "/givecush":
        try:
            t = text.split()[1].lstrip("@")
            amt = int(text.split()[2])
            tid = find_user_id_by_username(t)
            if not tid:
                send_message(cid, "❌ Не найден.")
                return
            set_cush(tid, amt)
            send_message(cid, f"✅ Подкрутка @{t} на {fmt(amt)} {STAR}.")
        except Exception:
            send_message(cid, "❌ /givecush @username <сумма>")
        return

    if cmd == "/send":
        text2 = text.replace("/send", "", 1).strip()
        if not text2:
            send_message(cid, "❌ /send <текст>")
            return
        sent = 0
        failed = 0
        for u in list(BALANCES.keys()):
            r = send_message(u, text2)
            if r:
                sent += 1
            else:
                failed += 1
            time.sleep(0.05)
        send_message(cid, f"📢 ✅ {sent} | ❌ {failed}")
        return

    if cmd == "/fake":
        try:
            t = text.split()[1].lstrip("@")
            tid = find_user_id_by_username(t)
            if not tid:
                send_message(cid, "❌ Не найден.")
                return
            FAKE_STATE[uid] = {"target": tid, "game": ""}
            send_message(cid, f"🎭 Игра для фейка @{t}:", reply_markup=fake_game_menu())
        except Exception:
            send_message(cid, "❌ /fake @username")
        return

def handle_message(u):
    from_obj = u.get("from") or (u.get("payload") or {}).get("from") or {}
    uid = from_obj.get("id")
    cid = u.get("chat_id") or (u.get("payload") or {}).get("chat_id")
    text = u.get("text") or (u.get("payload") or {}).get("text", "") or ""
    if not uid or not cid:
        print("skip message: no uid/cid ->", json.dumps(u, ensure_ascii=False))
        return
    remember_username(uid, from_obj.get("tag"))

    state, payload = get_user_state(uid)
    if state == "withdraw_amount":
        clear_user_state(uid)
        process_withdraw_amount(uid, cid, text)
        return
    if state == "custom_bet":
        clear_user_state(uid)
        process_custom_bet(uid, cid, text, payload.get("game"))
        return
    if state == "number_bet":
        clear_user_state(uid)
        process_number_bet(uid, cid, text, payload.get("bet", 0))
        return
    if state == "fake_amount":
        clear_user_state(uid)
        process_fake_amount(uid, cid, text)
        return
    if state == "enter_ref":
        clear_user_state(uid)
        process_ref_code(uid, cid, text)
        return

    if text.startswith("/"):
        handle_command(uid, cid, text)
        return
    send_message(cid, "Используй меню /start", reply_markup=main_menu())

# ============================== ОБРАБОТКА CALLBACK ==============================
def handle_callback(u):
    cb = (u.get("payload") or {}).get("callback_query") or {}
    uid = u.get("actor_id") or (u.get("from") or {}).get("id") or (cb.get("from") or {}).get("id")
    cid = u.get("chat_id") or cb.get("chat_id")
    mid = u.get("message_id") or cb.get("message_id")
    data = u.get("callback_data") or cb.get("data") or ""
    cb_id = cb.get("id") or u.get("update_id")
    if not uid or not cid:
        print("skip callback: no uid/cid ->", json.dumps(u, ensure_ascii=False))
        return
    remember_username(uid, (u.get("from") or {}).get("tag"))

    if data.startswith("pres_ALL_"):
        if uid != ADMIN_ID:
            answer_cb(cb_id, "❌ Нет прав", show_alert=True)
            return
        mode = data.replace("pres_ALL_", "")
        if mode == "shedro":
            SETTINGS.update({"chance_slots": "30", "payout_slots": "2.5",
                             "chance_dice": "30", "payout_dice": "2",
                             "chance_roulette_color": "30", "payout_roulette_color": "2",
                             "chance_roulette_number": "10", "payout_roulette_number": "5",
                             "chance_case": "30", "chance_upgrade": "25"})
            mode_text = "🟢 Щедро (макс 30%)"
        elif mode == "standart":
            SETTINGS.update({"chance_slots": "15", "payout_slots": "3",
                             "chance_dice": "15", "payout_dice": "2.5",
                             "chance_roulette_color": "15", "payout_roulette_color": "2.5",
                             "chance_roulette_number": "5", "payout_roulette_number": "10",
                             "chance_case": "15", "chance_upgrade": "12"})
            mode_text = "🟡 Стандарт (макс 15%)"
        elif mode == "greedy":
            SETTINGS.update({"chance_slots": "12", "payout_slots": "3",
                             "chance_dice": "12", "payout_dice": "3",
                             "chance_roulette_color": "12", "payout_roulette_color": "3",
                             "chance_roulette_number": "3", "payout_roulette_number": "12",
                             "chance_case": "12", "chance_upgrade": "10"})
            mode_text = "🔴 Жадно (макс 12%)"
        elif mode == "100":
            for g in ["slots", "dice", "roulette_color", "roulette_number", "case", "upgrade"]:
                SETTINGS[f"chance_{g}"] = "100"
            mode_text = "⚫ Всем везёт (100%)"
        elif mode == "0":
            for g in ["slots", "dice", "roulette_color", "roulette_number", "case", "upgrade"]:
                SETTINGS[f"chance_{g}"] = "0"
            mode_text = "⛔ Никому (0%)"
        else:
            return
        answer_cb(cb_id, f"✅ {mode_text}", show_alert=True)
        edit_text(cid, mid, f"✅ Режим: {mode_text}", reply_markup=chance_menu())
        return

    if data.startswith("wadm_"):
        if uid != ADMIN_ID:
            answer_cb(cb_id, "❌ Нет прав", show_alert=True)
            return
        parts = data.split("_")
        action = parts[1]
        try:
            rid = int(parts[2])
        except Exception:
            answer_cb(cb_id, "❌ Ошибка", show_alert=True)
            return
        req = WITHDRAW_REQUESTS.get(rid)
        if not req:
            answer_cb(cb_id, "❌ Не найдена", show_alert=True)
            return
        if req["status"] != "pending":
            answer_cb(cb_id, "❌ Уже обработана", show_alert=True)
            return
        if action == "ok":
            cur = get_balance(req["user_id"])
            if cur < req["amount"]:
                req["status"] = "failed"
                answer_cb(cb_id, "❌ Недостаточно баланса", show_alert=True)
                send_message(cid, f"❌ Заявка #{rid}: недостаточно баланса.")
                send_message(req["user_id"], f"❌ Вывод {fmt(req['amount'])} {STAR} отклонён.")
                return
            old = cur
            nb = update_balance(req["user_id"], -req["amount"])
            notify_trackers(req["user_id"], old, nb, f"вывод #{rid}")
            req["status"] = "approved"
            answer_cb(cb_id, "✅ Подтверждено", show_alert=True)
            send_message(cid, f"✅ Заявка #{rid}: выведено {fmt(req['amount'])} {STAR}. Новый баланс: {fmt(nb)}")
            send_message(req["user_id"], f"✅ Вывод {fmt(req['amount'])} {STAR} одобрен!\n{STAR} Баланс: {fmt(nb)}", reply_markup=main_menu())
        elif action == "no":
            req["status"] = "rejected"
            answer_cb(cb_id, "❌ Отклонено", show_alert=True)
            send_message(cid, f"❌ Заявка #{rid} отклонена.")
            send_message(req["user_id"], f"❌ Вывод {fmt(req['amount'])} {STAR} отклонён.")
        return

    if data.startswith("fk_"):
        if uid != ADMIN_ID:
            answer_cb(cb_id, "❌ Нет прав", show_alert=True)
            return
        st = FAKE_STATE.get(uid)
        if not st:
            answer_cb(cb_id, "❌ Сессия истекла", show_alert=True)
            return
        g = data.replace("fk_", "")
        st["game"] = g
        answer_cb(cb_id)
        send_message(cid, f"🎭 Игра: {g}\nВведи сумму выигрыша:")
        set_user_state(uid, "fake_amount")
        return

    if check_banned_or_maint(uid, cid, cb_id):
        return
    answer_cb(cb_id)

    if data == "back_menu":
        edit_text(cid, mid, "Главное меню:", reply_markup=main_menu())
        return
    if data == "profile":
        info = get_user_info(uid)
        edit_text(cid, mid,
                  f"👤 Профиль\n\nID: {uid}\nЮзернейм: @{info['username'] or 'нет'}\n{STAR} Баланс: {fmt(info['balance'])} звёзд",
                  reply_markup=main_menu())
        return
    if data == "check_balance":
        answer_cb(cb_id, f"{STAR} Баланс: {fmt(get_balance(uid))} звёзд!", show_alert=True)
        return
    if data == "withdraw":
        if get_balance(uid) < MIN_WITHDRAW:
            answer_cb(cb_id, f"❌ Минимум: {MIN_WITHDRAW} {STAR}.", show_alert=True)
            return
        edit_text(cid, mid,
                  f"💸 Вывод\n\n{STAR} Доступно: {fmt(get_balance(uid))}\nМинимум: {MIN_WITHDRAW}\n\nВведи сумму:",
                  reply_markup=back_menu_kb())
        set_user_state(uid, "withdraw_amount")
        return
    if data == "daily_bonus":
        today = datetime.date.today().isoformat()
        prev_date, prev_amt = DAILY.get(uid, ("", 0))
        if prev_date == today:
            answer_cb(cb_id, f"❌ Ты уже получал сегодня: {fmt(prev_amt)} {STAR}.", show_alert=True)
            return
        amt = random.randint(DAILY_MIN, DAILY_MAX)
        DAILY[uid] = (today, amt)
        old = get_balance(uid)
        update_balance(uid, amt)
        notify_trackers(uid, old, get_balance(uid), "ежедневный бонус")
        answer_cb(cb_id, f"🎁 Ты получил {fmt(amt)} {STAR}!", show_alert=True)
        edit_text(cid, mid, f"🎁 Бонус!\n\nТы получил: {fmt(amt)} {STAR}\n{STAR} Баланс: {fmt(get_balance(uid))}",
                  reply_markup=main_menu())
        return
    if data == "referral_menu":
        ref_count = sum(1 for v in REFERRERS.values() if v == uid)
        ref = REFERRERS.get(uid)
        text_out = (f"👥 Рефералка\n\nЗа друга — {REF_REWARD} {STAR}.\n\n"
                    f"🔗 Твой ID: {uid}\n"
                    f"📤 Передай другу: /ref {uid}\n\n"
                    f"👤 Приглашено: {ref_count}")
        if ref:
            text_out += f"\n✅ Твой реферер: @{USERNAMES.get(ref, ref)}"
        edit_text(cid, mid, text_out, reply_markup=ref_menu())
        return
    if data == "enter_ref":
        edit_text(cid, mid,
                  "🔗 Введи ID друга (он может узнать его через /myid):",
                  reply_markup=back_menu_kb())
        set_user_state(uid, "enter_ref")
        return
    if data == "topup_request":
        edit_text(cid, mid,
                  f"{STAR} Пополнение\n\nНапиши {ADMIN_USERNAME} — переведи звёзды или NFT, укажи юзернейм.",
                  reply_markup=main_menu())
        if ADMIN_ID:
            send_message(ADMIN_ID, f"🔔 Пополнение от @{USERNAMES.get(uid, 'без_юз')}")
        return

    if data == "play_slots":
        edit_text(cid, mid, "🎰 Слоты\n\nВыбери ставку:", reply_markup=bet_menu("slots"))
        return
    if data == "play_dice":
        edit_text(cid, mid, "🎲 Кости\n\nВыбери ставку:", reply_markup=bet_menu("dice"))
        return
    if data == "cases_menu":
        edit_text(cid, mid, "📦 Кейсы\n\nВыбери кейс:", reply_markup=cases_menu())
        return
    if data == "roulette_menu":
        edit_text(cid, mid, "🎡 Рулетка\n\nВыбери ставку:", reply_markup=bet_menu("roulette"))
        return
    if data == "upgrade_menu":
        edit_text(cid, mid, "📈 Апгрейдер\n\nВыбери предмет:", reply_markup=upgrade_menu())
        return

    if data.startswith("open_case_"):
        key = data.replace("open_", "")
        case = CASES.get(key)
        if not case:
            return
        edit_text(cid, mid, f"📦 {case['name']} — {fmt(case['price'])} {STAR}\n\nСколько открыть?",
                  reply_markup=case_multi_menu(key))
        return
    if data.startswith("cmult_"):
        parts = data.split("_")
        key = f"{parts[1]}_{parts[2]}"
        count = int(parts[3])
        do_case_open(uid, cid, key, count)
        return

    if data.startswith("bet_"):
        parts = data.split("_")
        game = parts[1]
        val = parts[2]
        if val == "custom":
            edit_text(cid, mid, "✍️ Введи ставку:", reply_markup=back_menu_kb())
            set_user_state(uid, "custom_bet", {"game": game})
            return
        bet = int(val)
        if get_balance(uid) < bet:
            answer_cb(cb_id, "❌ Мало звёзд!", show_alert=True)
            return
        if game == "roulette":
            edit_text(cid, mid, f"🎡 Ставка: {fmt(bet)} {STAR}\n\nНа что?", reply_markup=roulette_type_menu(bet))
        else:
            edit_text(cid, mid, f"Количество игр (ставка {fmt(bet)} {STAR}):", reply_markup=multi_bet_menu(game, bet))
        return
    if data.startswith("mult_"):
        parts = data.split("_")
        game = parts[1]
        bet = int(parts[2])
        count = int(parts[3])
        total = bet * count
        if get_balance(uid) < total:
            answer_cb(cb_id, f"❌ Нужно {fmt(total)} {STAR}!", show_alert=True)
            return
        do_slots_or_dice(uid, cid, game, bet, count)
        return

    if data.startswith("rt_red_") or data.startswith("rt_black_"):
        color = data.split("_")[1]
        bet = int(data.split("_")[2])
        if get_balance(uid) < bet:
            answer_cb(cb_id, "❌ Мало звёзд!", show_alert=True)
            return
        old = get_balance(uid)
        update_balance(uid, -bet)
        notify_trackers(uid, old, get_balance(uid), "рулетка цвет")
        red = {1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36}
        black = set(range(1, 37)) - red
        cush = pop_cush(uid)
        payout = get_payout("roulette_color")
        if cush is not None:
            update_balance(uid, cush)
            msg = f"🎡 Выпало: 17\n🎉 ТОЧНОЕ! Выигрыш: {fmt(cush)} {STAR}!"
        elif get_chance("roulette_color") > 0 and roll_win("roulette_color"):
            r = random.choice(list(red if color == "red" else black))
            rc = "🔴" if r in red else "⚫"
            w = int(bet * payout)
            update_balance(uid, w)
            msg = f"🎡 Выпало: {r} ({rc})\n🎉 +{fmt(w)} {STAR}"
        else:
            r = random.choice(list(black if color == "red" else red) + [0])
            rc = "🟢" if r == 0 else ("🔴" if r in red else "⚫")
            msg = f"🎡 Выпало: {r} ({rc})\n😢 Проигрыш."
        send_message(cid, f"{msg}\n\n{STAR} Баланс: {fmt(get_balance(uid))}", reply_markup=main_menu())
        return
    if data.startswith("rt_number_"):
        bet = int(data.split("_")[2])
        if get_balance(uid) < bet:
            answer_cb(cb_id, "❌ Мало звёзд!", show_alert=True)
            return
        edit_text(cid, mid, f"🎯 Ставка: {fmt(bet)} {STAR}\nВведи число 0-36:", reply_markup=back_menu_kb())
        set_user_state(uid, "number_bet", {"bet": bet})
        return

    if data.startswith("upgt_"):
        parts = data.split("_")
        cur_p = int(parts[1])
        tgt_p = int(parts[2])
        if get_balance(uid) < cur_p:
            answer_cb(cb_id, f"❌ Нужно {fmt(cur_p)} {STAR}.", show_alert=True)
            return
        old = get_balance(uid)
        update_balance(uid, -cur_p)
        notify_trackers(uid, old, get_balance(uid), "апгрейдер")
        chance = get_chance("upgrade")
        if chance > 0 and random.randint(1, 100) <= chance:
            old2 = get_balance(uid)
            update_balance(uid, tgt_p)
            notify_trackers(uid, old2, get_balance(uid), "апгрейдер выигрыш")
            msg = f"📈 АПГРЕЙД УСПЕШЕН!\n\n{fmt(cur_p)} {STAR} → {fmt(tgt_p)} {STAR}\n\n{STAR} Баланс: {fmt(get_balance(uid))}"
        else:
            msg = f"📈 АПГРЕЙД ПРОВАЛЕН\n\nТы потерял {fmt(cur_p)} {STAR}.\n\n{STAR} Баланс: {fmt(get_balance(uid))}"
        edit_text(cid, mid, msg, reply_markup=main_menu())
        return
    if data.startswith("upg_"):
        price = int(data.replace("upg_", ""))
        if get_balance(uid) < price:
            answer_cb(cb_id, f"❌ Нужно {fmt(price)} {STAR}.", show_alert=True)
            return
        edit_text(cid, mid, f"📈 Улучшаем за {fmt(price)} {STAR}.\nВыбери целевой предмет:",
                  reply_markup=upgrade_target_menu(price))
        return

# ============================== ПОЛЛИНГ ==============================
def extract_updates(result):
    if result is None:
        return []
    if isinstance(result, list):
        return result
    if isinstance(result, dict):
        if "updates" in result and isinstance(result["updates"], list):
            return result["updates"]
        if "result" in result and isinstance(result["result"], list):
            return result["result"]
    return []

def poll_once():
    result = api_call("getUpdates", offset=OFFSET[0], limit=100)
    updates = extract_updates(result)
    for u in updates:
        if DEBUG_UPDATES:
            print("UPDATE:", json.dumps(u, ensure_ascii=False))
        try:
            utype = u.get("update_type")
            if utype == "message":
                handle_message(u)
            elif utype == "callback_query":
                handle_callback(u)
        except Exception as e:
            print("handler error:", e)
            import traceback; traceback.print_exc()
        try:
            OFFSET[0] = int(u.get("update_id", OFFSET[0])) + 1
        except Exception:
            pass

def main():
    if not BOT_TOKEN:
        print("❌ Не задан STRAZH_BOT_TOKEN")
        return
    try:
        me = api_call("getMe")
        BOT_ID[0] = me.get("id")
        print(f"🚀 Бот запущен: {me.get('name')} (@{me.get('tag')}) id={BOT_ID[0]}")
    except Exception as e:
        print("❌ getMe failed:", e)
        return
    while True:
        try:
            poll_once()
        except Exception as e:
            print("poll error:", e)
        time.sleep(1.0)

if __name__ == "__main__":
    main()