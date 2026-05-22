#!/usr/bin/env bash
# Настройка Telegram user-аккаунта (@twiMonBot), MTProto прокси и авторизация
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"
VENV="$PROJECT_DIR/.venv"

source "$SCRIPT_DIR/common.sh"
cd "$PROJECT_DIR"

require_venv

# ── Парсер tg://proxy ─────────────────────────────────────────────────────────
parse_proxy_link() {
    local link="$1"
    "$VENV/bin/python3" -c "
from urllib.parse import urlparse, parse_qs
link = '''$link'''.strip()
parsed = urlparse(link)
if parsed.scheme == 'tg' and parsed.hostname == 'proxy':
    p = parse_qs(parsed.query)
    server = p.get('server', [''])[0]
    secret = p.get('secret', [''])[0]
    port   = p.get('port', ['443'])[0]
    if server and secret:
        print(f'{server}|{port}|{secret}')
" 2>/dev/null || true
}

h1 "TELEGRAM USER-АККАУНТ"
cat << 'DOC'
  Нужен для режима мониторинга «telegram» — бот читает уведомления
  от @twiMonBot через твой личный аккаунт.
DOC
echo

cur_api_id="$(read_env TELEGRAM_API_ID)"
cur_api_hash="$(read_env TELEGRAM_API_HASH)"
cur_phone="$(read_env TELEGRAM_PHONE)"
cur_proxy_server="$(read_env TELEGRAM_PROXY_SERVER)"
cur_proxy_port="$(read_env TELEGRAM_PROXY_PORT)"
cur_proxy_secret="$(read_env TELEGRAM_PROXY_SECRET)"

[[ -n "$cur_api_id" ]]  && info "Текущий API ID:  $cur_api_id"
[[ -n "$cur_phone" ]]   && info "Текущий телефон: $cur_phone"
[[ -n "$cur_proxy_server" ]] && info "Текущий прокси:  $cur_proxy_server:${cur_proxy_port:-443}"
echo

_DEFAULT_API_ID="2040"
_DEFAULT_API_HASH="b18441a1ff607e10a989891a5462e627"

if confirm "Использовать встроенные API credentials (Telegram Desktop)?"; then
    api_id="$_DEFAULT_API_ID"
    api_hash="$_DEFAULT_API_HASH"
    ok "Встроенные credentials"
else
    cat << 'DOC'
  Как получить API_ID и API_HASH:
    1. Открой https://my.telegram.org → «API development tools»
    2. Заполни форму (App title и Short name — любые)
    3. Скопируй App api_id и App api_hash
DOC
    echo
    ask_or_keep "Telegram API ID (число)"    api_id    "$cur_api_id"
    ask_or_keep "Telegram API Hash (строка)" api_hash  "$cur_api_hash"
fi

echo
ask_or_keep "Номер телефона (+79001234567)" phone "$cur_phone"

# ── MTProto прокси ────────────────────────────────────────────────────────────
echo
h1 "MTProto ПРОКСИ (для российских серверов)"

proxy_server=""; proxy_port=""; proxy_secret=""

if [[ -n "$cur_proxy_server" ]]; then
    ok "Прокси: $cur_proxy_server:${cur_proxy_port:-443}"
    if confirm "Оставить текущий прокси?"; then
        proxy_server="$cur_proxy_server"
        proxy_port="$cur_proxy_port"
        proxy_secret="$cur_proxy_secret"
    fi
fi

if [[ -z "$proxy_server" ]]; then
    if confirm "Настроить MTProto-прокси?" n; then
        while true; do
            ask_required "Ссылка на прокси (tg://proxy?...)" _proxy_link
            _parsed="$(parse_proxy_link "$_proxy_link")"
            if [[ -n "$_parsed" ]]; then
                proxy_server="${_parsed%%|*}"; _rest="${_parsed#*|}"
                proxy_port="${_rest%%|*}";    proxy_secret="${_rest#*|}"
                ok "Прокси: $proxy_server:$proxy_port"
                break
            else
                warn "Неверный формат. Ожидается: tg://proxy?server=...&port=...&secret=..."
            fi
        done
    else
        info "Прокси не настроен"
    fi
fi

set_env_var TELEGRAM_API_ID      "$api_id"
set_env_var TELEGRAM_API_HASH    "$api_hash"
set_env_var TELEGRAM_PHONE       "$phone"
set_env_var TELEGRAM_PROXY_SERVER "$proxy_server"
set_env_var TELEGRAM_PROXY_PORT   "$proxy_port"
set_env_var TELEGRAM_PROXY_SECRET "$proxy_secret"
ok ".env обновлён"

# ── Авторизация ───────────────────────────────────────────────────────────────
echo
h1 "АВТОРИЗАЦИЯ"

mkdir -p "$PROJECT_DIR/data"

if [[ -f "$PROJECT_DIR/data/telegram_user.session" ]]; then
    ok "Сессия уже существует"
    if ! confirm "Переавторизоваться (перезаписать сессию)?"; then
        echo
        info "Пропущено — используется существующая сессия"
        exit 0
    fi
    rm -f "$PROJECT_DIR/data/telegram_user.session"
fi

if [[ -n "$proxy_server" ]]; then
    info "Авторизуюсь через MTProto прокси ($proxy_server:$proxy_port)..."
else
    info "Авторизуюсь напрямую. На телефон придёт код подтверждения..."
fi
echo

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
    api_id       = int(sys.argv[1])
    api_hash     = sys.argv[2]
    phone        = normalize_phone(sys.argv[3])
    session      = sys.argv[4]
    proxy_server = sys.argv[5] if len(sys.argv) > 5 else ""
    proxy_port   = int(sys.argv[6]) if len(sys.argv) > 6 and sys.argv[6] else 443
    proxy_secret = sys.argv[7] if len(sys.argv) > 7 else ""

    proxy = ("mtproto", proxy_server, proxy_port, proxy_secret) if proxy_server else None

    print(f"  Номер: {phone}")
    client = TelegramClient(session, api_id, api_hash, proxy=proxy)
    await client.start(phone=phone)
    me = await client.get_me()
    name = me.first_name or ""
    if me.last_name:
        name += f" {me.last_name}"
    print(f"\033[0;32m  ✓ Авторизован как: {name} (@{me.username or me.phone})\033[0m")
    await client.disconnect()

asyncio.run(main())
PYEOF

if "$VENV/bin/python3" "$TMPAUTH" \
        "$api_id" "$api_hash" "$phone" \
        "$PROJECT_DIR/data/telegram_user" \
        "$proxy_server" "$proxy_port" "$proxy_secret"; then
    ok "Сессия сохранена"
else
    rm -f "$TMPAUTH"
    die "Авторизация не удалась — проверь API_ID, API_HASH и номер телефона"
fi
rm -f "$TMPAUTH"
