#!/usr/bin/env bash
# Переключение режима мониторинга: twitch ↔ telegram
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
VENV="$SCRIPT_DIR/.venv"
SERVICE="twitch-alice-bot"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'
BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

ok()   { printf "${G}  ✓ %s${RESET}\n" "$1"; }
warn() { printf "${Y}  ⚠ %s${RESET}\n" "$1"; }
info() { printf "${DIM}    %s${RESET}\n" "$1"; }
die()  { printf "${R}  ✗ %s${RESET}\n" "$1" >&2; exit 1; }

trim() {
    local s="$*"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

ask_required() {
    local prompt="$1" vn="$2" secret="${3:-}" val=""
    while [[ -z "$val" ]]; do
        if [[ "$secret" == secret ]]; then
            printf "${BOLD}  %s${RESET}: " "$prompt"; read -rs val; echo
        else
            printf "${BOLD}  %s${RESET}: " "$prompt"; read -r val
        fi
        val="$(trim "$val")"
        [[ -z "$val" ]] && warn "Поле не может быть пустым"
    done
    printf -v "$vn" '%s' "$val"
}

get_env() { grep "^${1}=" "$ENV_FILE" 2>/dev/null | cut -d= -f2- || true; }

set_env() {
    local key="$1" val="$2"
    if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${val}|" "$ENV_FILE"
    else
        printf '\n%s=%s\n' "$key" "$val" >> "$ENV_FILE"
    fi
}

[[ -f "$ENV_FILE" ]] || die ".env не найден — сначала запусти install.sh"
[[ -d "$VENV" ]]     || die "Виртуальное окружение не найдено — сначала запусти install.sh"

current_mode="$(get_env MONITOR_MODE)"
current_mode="${current_mode:-twitch}"

echo
printf "${BOLD}${C}  Текущий режим: %s${RESET}\n" "$current_mode"
echo

if [[ "$current_mode" == "twitch" ]]; then
    new_mode="telegram"
    printf "  Переключить на ${BOLD}telegram${RESET} (@twiMonBot)? [y/N] "
else
    new_mode="twitch"
    printf "  Переключить на ${BOLD}twitch${RESET} (Twitch API)? [y/N] "
fi

read -r _answer
[[ "$(trim "$_answer")" =~ ^[yYдД]$ ]] || { info "Отмена"; exit 0; }
echo

# ── Twitch ────────────────────────────────────────────────────────────────────
if [[ "$new_mode" == "twitch" ]]; then
    client_id="$(get_env TWITCH_CLIENT_ID)"
    client_secret="$(get_env TWITCH_CLIENT_SECRET)"

    if [[ -z "$client_id" || -z "$client_secret" ]]; then
        printf "${BOLD}  Twitch API credentials${RESET}\n"
        info "Создать приложение: https://dev.twitch.tv/console/apps"
        echo
        [[ -z "$client_id" ]]     && ask_required "Twitch Client ID"     client_id
        [[ -z "$client_secret" ]] && ask_required "Twitch Client Secret" client_secret
        set_env TWITCH_CLIENT_ID     "$client_id"
        set_env TWITCH_CLIENT_SECRET "$client_secret"
        ok "Twitch credentials сохранены"
    else
        ok "Twitch credentials уже есть в .env"
    fi
fi

# ── Telegram user-аккаунт ─────────────────────────────────────────────────────
_DEFAULT_API_ID="2040"
_DEFAULT_API_HASH="b18441a1ff607e10a989891a5462e627"

if [[ "$new_mode" == "telegram" ]]; then
    api_id="$(get_env TELEGRAM_API_ID)"
    api_hash="$(get_env TELEGRAM_API_HASH)"
    tg_phone="$(get_env TELEGRAM_PHONE)"

    if [[ -z "$api_id" || -z "$api_hash" ]]; then
        printf "${BOLD}  Telegram API credentials${RESET}\n"
        info "Если my.telegram.org недоступен — используй встроенные (Telegram Desktop)"
        echo
        printf "  Использовать встроенные API credentials (Telegram Desktop)? [Y/n] "
        read -r _cred_choice
        if [[ ! "$(trim "$_cred_choice")" =~ ^[nNнН]$ ]]; then
            api_id="$_DEFAULT_API_ID"
            api_hash="$_DEFAULT_API_HASH"
            ok "Используем встроенные credentials"
        else
            ask_required "Telegram API ID (число)"    api_id
            ask_required "Telegram API Hash"           api_hash
        fi
        set_env TELEGRAM_API_ID   "$api_id"
        set_env TELEGRAM_API_HASH "$api_hash"
    else
        ok "Telegram API credentials уже есть в .env"
    fi

    if [[ -z "$tg_phone" ]]; then
        echo
        ask_required "Номер телефона (+79001234567)" tg_phone
        set_env TELEGRAM_PHONE "$tg_phone"
    else
        ok "Номер телефона уже есть в .env"
    fi

    echo
    info "Авторизуюсь в Telegram (на телефон придёт код)..."
    echo

    mkdir -p "$SCRIPT_DIR/data"
    TMPAUTH=$(mktemp /tmp/tg_auth_XXXXXX.py)
    cat > "$TMPAUTH" << 'PYEOF'
import sys, re, asyncio
from telethon import TelegramClient

def normalize_phone(p):
    p = re.sub(r'[\s\-\(\)]+', '', p)
    if not p.startswith('+'):
        p = '+' + p
    return p

async def main():
    phone = normalize_phone(sys.argv[3])
    print(f"  Номер: {phone}")
    client = TelegramClient(sys.argv[4], int(sys.argv[1]), sys.argv[2])
    await client.start(phone=phone)
    me = await client.get_me()
    name = (me.first_name or "") + (" " + me.last_name if me.last_name else "")
    print(f"  Авторизован как: {name.strip()} (@{me.username or me.phone})")
    await client.disconnect()

asyncio.run(main())
PYEOF

    if "$VENV/bin/python3" "$TMPAUTH" \
            "$api_id" "$api_hash" "$tg_phone" \
            "$SCRIPT_DIR/data/telegram_user"; then
        ok "Telegram-сессия активна"
    else
        rm -f "$TMPAUTH"
        die "Авторизация не удалась — проверь API_ID, API_HASH и номер телефона"
    fi
    rm -f "$TMPAUTH"
fi

# ── Сохраняем новый режим ─────────────────────────────────────────────────────
set_env MONITOR_MODE "$new_mode"
ok "MONITOR_MODE=${new_mode} сохранён"

# ── Перезапуск сервиса ────────────────────────────────────────────────────────
echo
if systemctl is-active --quiet "$SERVICE" 2>/dev/null || \
   systemctl is-enabled --quiet "$SERVICE" 2>/dev/null; then
    printf "  Перезапускаю сервис %s...\n" "$SERVICE"
    sudo systemctl restart "$SERVICE"
    sleep 2
    if systemctl is-active --quiet "$SERVICE"; then
        ok "Сервис перезапущен и работает"
    else
        warn "Сервис не запустился — проверь логи:"
        printf "    sudo journalctl -u %s -n 30\n" "$SERVICE"
    fi
else
    info "Сервис $SERVICE не зарегистрирован в systemd."
    info "Запусти вручную: bash $SCRIPT_DIR/install.sh"
fi
echo
