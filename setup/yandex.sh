#!/usr/bin/env bash
# Настройка Яндекс Алисы (OAuth токен, устройство, локальный IP) и проверка
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"
VENV="$PROJECT_DIR/.venv"

source "$SCRIPT_DIR/common.sh"
cd "$PROJECT_DIR"

require_venv

h1 "ЯНДЕКС АЛИСА"
cat << 'DOC'
  Как получить OAuth-токен (войди в браузере под нужным аккаунтом):

    https://oauth.yandex.ru/authorize?response_type=token&client_id=23cabbbdc6cd418abb4b39c32c41195d

  Нажми «Разрешить», скопируй access_token из адресной строки.
DOC
echo

cur_token="$(read_env YANDEX_TOKEN)"
cur_device_id="$(read_env YANDEX_DEVICE_ID)"
cur_platform="$(read_env YANDEX_PLATFORM)"
cur_device_ip="$(read_env YANDEX_DEVICE_IP)"

[[ -n "$cur_token" ]]     && info "Текущий токен:    сохранён"
[[ -n "$cur_device_id" ]] && info "Текущий device:   $cur_device_id ($cur_platform)"
[[ -n "$cur_device_ip" ]] && info "Текущий IP:       $cur_device_ip"
echo

ask_or_keep "Yandex OAuth Token" yandex_token "$cur_token" secret

# ── Выбор устройства ──────────────────────────────────────────────────────────
echo
yandex_device_id=""
yandex_platform=""

if [[ -n "$cur_device_id" && -n "$cur_platform" ]]; then
    ok "Устройство: $cur_device_id ($cur_platform)"
    if confirm "Оставить текущее устройство?"; then
        yandex_device_id="$cur_device_id"
        yandex_platform="$cur_platform"
    fi
fi

if [[ -z "$yandex_device_id" ]]; then
    info "Получаю список устройств Яндекс..."
    echo

    TMPDEV=$(mktemp)
    YANDEX_TOKEN="$yandex_token" "$VENV/bin/python3" -m bot.alice_discovery --json \
        > "$TMPDEV" 2>/dev/null || echo '[]' > "$TMPDEV"

    DEVICE_COUNT=$("$VENV/bin/python3" -c "
import json
try:
    d = json.load(open('$TMPDEV'))
    print(len(d) if isinstance(d, list) else 0)
except Exception:
    print(0)
")

    if [[ "$DEVICE_COUNT" -eq 0 ]]; then
        warn "Устройства не найдены или токен неверный"
        echo
        info "Введи device_id и platform вручную."
        hint "Запусти позже: .venv/bin/python -m bot.alice_discovery"
        echo
        ask_required "YANDEX_DEVICE_ID (GUID устройства)" yandex_device_id
        echo
        cat << 'DOC'
  Допустимые значения YANDEX_PLATFORM:
    yandexstation      yandexstation_2    yandexmini
    yandexmini_2       yandexmicro
DOC
        echo
        ask_required "YANDEX_PLATFORM" yandex_platform

    elif [[ "$DEVICE_COUNT" -eq 1 ]]; then
        yandex_device_id=$("$VENV/bin/python3" -c "import json; d=json.load(open('$TMPDEV')); print(d[0]['id'])")
        yandex_platform=$("$VENV/bin/python3" -c "import json; d=json.load(open('$TMPDEV')); print(d[0]['platform'])")
        device_name=$("$VENV/bin/python3" -c "import json; d=json.load(open('$TMPDEV')); print(d[0].get('name','—'))")
        ok "Устройство: $device_name ($yandex_device_id)"

    else
        printf "${BOLD}  Найдено устройств: %d${RESET}\n\n" "$DEVICE_COUNT"
        "$VENV/bin/python3" - <<PYEOF
import json
with open('$TMPDEV') as f:
    devices = json.load(f)
for i, d in enumerate(devices, 1):
    print(f"  {i}. \033[1m{d.get('name','—')}\033[0m  {d.get('id','—')}  ({d.get('platform','—')})")
PYEOF
        echo
        while true; do
            printf "${BOLD}  Введи номер устройства (1–%d)${RESET}: " "$DEVICE_COUNT"
            read -r dev_num
            dev_num="$(trim "$dev_num")"
            if [[ "$dev_num" =~ ^[0-9]+$ ]] && \
               [[ "$dev_num" -ge 1 ]] && \
               [[ "$dev_num" -le "$DEVICE_COUNT" ]]; then
                idx=$((dev_num - 1))
                yandex_device_id=$("$VENV/bin/python3" -c "import json; d=json.load(open('$TMPDEV')); print(d[$idx]['id'])")
                yandex_platform=$("$VENV/bin/python3" -c "import json; d=json.load(open('$TMPDEV')); print(d[$idx]['platform'])")
                ok "Выбрано: $yandex_device_id ($yandex_platform)"
                break
            fi
            warn "Введи число от 1 до $DEVICE_COUNT"
        done
    fi
    rm -f "$TMPDEV"
fi

# ── IP Станции (локальный режим) ──────────────────────────────────────────────
echo
yandex_device_ip=""

if [[ -n "$cur_device_ip" ]]; then
    ok "IP Станции: $cur_device_ip"
    if confirm "Оставить текущий IP?"; then
        yandex_device_ip="$cur_device_ip"
    fi
fi

if [[ -z "$yandex_device_ip" ]]; then
    echo
    info "IP Станции нужен для TTS через локальную сеть (Glagol WebSocket)."
    info "Если бот на удалённом VPS — пропусти."
    echo
    if confirm "Указать IP Станции для локального режима?" n; then
        ask_required "IP-адрес Яндекс Станции (напр. 192.168.1.50)" yandex_device_ip
        ok "IP: $yandex_device_ip"
    else
        info "Локальный режим пропущен — облачный API"
    fi
fi

set_env_var YANDEX_TOKEN     "$yandex_token"
set_env_var YANDEX_DEVICE_ID "$yandex_device_id"
set_env_var YANDEX_PLATFORM  "$yandex_platform"
set_env_var YANDEX_DEVICE_IP "$yandex_device_ip"
ok ".env обновлён"

# ── Проверка ──────────────────────────────────────────────────────────────────
echo
info "Проверяю подключение к Яндекс..."
echo

"$VENV/bin/python3" - <<PYEOF
import asyncio, sys
sys.path.insert(0, '$PROJECT_DIR')
from bot.alice import AliceClient

async def main():
    a = AliceClient('$yandex_token', '$yandex_device_id', '$yandex_platform', '$yandex_device_ip')
    try:
        await a.start()
        ok = await a.check_connection()
        await a.close()
        if ok:
            print('\033[0;32m  ✓ Яндекс API доступен — токен верен\033[0m')
            sys.exit(0)
        else:
            print('\033[0;31m  ✗ Яндекс API недоступен (токен неверен или истёк)\033[0m')
            sys.exit(1)
    except Exception as e:
        await a.close()
        print(f'\033[0;31m  ✗ Ошибка: {e}\033[0m')
        sys.exit(1)

asyncio.run(main())
PYEOF
