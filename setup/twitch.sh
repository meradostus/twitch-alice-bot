#!/usr/bin/env bash
# Настройка Twitch API credentials и проверка подключения
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"
VENV="$PROJECT_DIR/.venv"

source "$SCRIPT_DIR/common.sh"
cd "$PROJECT_DIR"

h1 "TWITCH API"
cat << 'DOC'
  Twitch Client ID и Client Secret — доступ к Twitch API.

  Как получить:
    1. Открой https://dev.twitch.tv/console/apps
    2. «Register Your Application» → Name: любое, Redirect: http://localhost, Category: Chat Bot
    3. «New Secret» — секрет показывается один раз, сразу скопируй
DOC
echo

cur_id="$(read_env TWITCH_CLIENT_ID)"
cur_secret="$(read_env TWITCH_CLIENT_SECRET)"

[[ -n "$cur_id" ]]     && info "Текущий Client ID:     ${cur_id:0:12}…"
[[ -n "$cur_secret" ]] && info "Текущий Client Secret: сохранён"
echo

ask_or_keep "Twitch Client ID"     client_id     "$cur_id"
ask_or_keep "Twitch Client Secret" client_secret "$cur_secret" secret

set_env_var TWITCH_CLIENT_ID     "$client_id"
set_env_var TWITCH_CLIENT_SECRET "$client_secret"
ok ".env обновлён"

# ── Проверка ──────────────────────────────────────────────────────────────────
echo
info "Проверяю подключение к Twitch API..."
echo

require_venv
"$VENV/bin/python3" - <<PYEOF
import asyncio, sys
sys.path.insert(0, '$PROJECT_DIR')
from bot.twitch import TwitchClient

async def main():
    t = TwitchClient('$client_id', '$client_secret')
    try:
        await t.start()
        ok = await t.check_connection()
        await t.close()
        if ok:
            print('\033[0;32m  ✓ Twitch API доступен — credentials верны\033[0m')
            sys.exit(0)
        else:
            print('\033[0;31m  ✗ Twitch API недоступен\033[0m')
            sys.exit(1)
    except Exception as e:
        await t.close()
        print(f'\033[0;31m  ✗ Ошибка: {e}\033[0m')
        sys.exit(1)

asyncio.run(main())
PYEOF
