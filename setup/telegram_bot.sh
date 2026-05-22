#!/usr/bin/env bash
# Настройка Telegram-бота (токен + chat ID) и проверка подключения
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"
VENV="$PROJECT_DIR/.venv"

source "$SCRIPT_DIR/common.sh"
cd "$PROJECT_DIR"

h1 "TELEGRAM БОТ"
cat << 'DOC'
  Как создать бота:
    1. Telegram → @BotFather → /newbot
    2. Придумай имя и username (заканчивается на bot)
    3. BotFather пришлёт токен вида: 1234567890:AABB-ccDDee...
DOC
echo

cur_token="$(read_env TELEGRAM_BOT_TOKEN)"
cur_chat_id="$(read_env TELEGRAM_CHAT_ID)"
cur_aiogram_proxy="$(read_env AIOGRAM_PROXY_URL)"

[[ -n "$cur_token" ]]   && info "Текущий токен:   сохранён"
[[ -n "$cur_chat_id" ]] && info "Текущий Chat ID: $cur_chat_id"
echo

ask_or_keep "Bot Token" bot_token "$cur_token" secret

# ── Определение Chat ID ───────────────────────────────────────────────────────
if [[ -n "$cur_chat_id" ]]; then
    ask_with_default "Chat ID" chat_id "$cur_chat_id"
else
    echo
    info "Чтобы определить Chat ID автоматически:"
    hint "Найди своего бота в Telegram и отправь ему любое сообщение, затем нажми Enter"
    read -r _dummy

    TMP_UPD=$(mktemp)
    export TMP_UPD
    chat_id=""

    if curl -sf --max-time 10 \
        "https://api.telegram.org/bot${bot_token}/getUpdates" \
        -o "$TMP_UPD" 2>/dev/null; then
        require_venv
        chat_id=$("$VENV/bin/python3" << 'PYEOF' || true
import json, os, sys
try:
    with open(os.environ["TMP_UPD"]) as f:
        data = json.load(f)
    for res in reversed(data.get("result", [])):
        for key in ("message", "channel_post", "edited_message"):
            if key in res:
                cid = res[key].get("chat", {}).get("id")
                if cid is not None:
                    print(cid)
                    sys.exit(0)
except Exception:
    pass
PYEOF
        )
    fi
    rm -f "$TMP_UPD"

    if [[ -n "$chat_id" ]]; then
        ok "Chat ID определён автоматически: $chat_id"
        ask_with_default "Chat ID" chat_id "$chat_id"
    else
        warn "Не удалось определить автоматически"
        hint "Напиши @userinfobot в Telegram — он покажет твой ID"
        ask_required "Chat ID (число, для группы — отрицательное)" chat_id
    fi
fi

# ── HTTP прокси для Bot API ───────────────────────────────────────────────────
echo
aiogram_proxy_url=""
if [[ -n "$cur_aiogram_proxy" ]]; then
    ok "HTTP прокси: $cur_aiogram_proxy"
    if confirm "Оставить текущий прокси?"; then
        aiogram_proxy_url="$cur_aiogram_proxy"
    fi
fi

if [[ -z "$aiogram_proxy_url" ]]; then
    info "Если api.telegram.org недоступен напрямую — укажи прокси."
    info "Формат: http://user:pass@host:port  или  socks5://user:pass@host:port"
    echo
    if confirm "Настроить HTTP прокси для Bot API?" n; then
        ask_required "URL прокси" aiogram_proxy_url
        ok "Прокси: $aiogram_proxy_url"
    else
        info "Прокси пропущен"
    fi
fi

set_env_var TELEGRAM_BOT_TOKEN "$bot_token"
set_env_var TELEGRAM_CHAT_ID   "$chat_id"
set_env_var AIOGRAM_PROXY_URL  "$aiogram_proxy_url"
ok ".env обновлён"

# ── Проверка ──────────────────────────────────────────────────────────────────
echo
info "Проверяю бота..."
echo

require_venv
"$VENV/bin/python3" - <<PYEOF
import asyncio, sys
sys.path.insert(0, '$PROJECT_DIR')
from aiogram import Bot

async def main():
    bot = Bot(token='$bot_token')
    try:
        me = await bot.get_me()
        print(f'\033[0;32m  ✓ Бот @{me.username} — токен верен\033[0m')
        chat_id = $chat_id
        await bot.send_message(chat_id, '✅ Twitch Alice Bot: Telegram-бот подключён успешно')
        print(f'\033[0;32m  ✓ Тестовое сообщение отправлено в чат {chat_id}\033[0m')
        sys.exit(0)
    except Exception as e:
        print(f'\033[0;31m  ✗ Ошибка: {e}\033[0m')
        sys.exit(1)
    finally:
        await bot.session.close()

asyncio.run(main())
PYEOF
