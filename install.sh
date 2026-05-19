#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Twitch Alice Bot — Мастер установки
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# При bash <(curl ...) BASH_SOURCE[0] указывает на пайп (/dev/fd/NN),
# а не на обычный файл — это надёжный признак запуска через pipe.
if [[ ! -f "${BASH_SOURCE[0]:-}" ]]; then
    _dest="${TWITCH_BOT_DIR:-$HOME/twitch-alice-bot}"
    echo "Клонирование репозитория в $_dest ..."
    if [[ -d "$_dest/.git" ]]; then
        git -C "$_dest" pull --ff-only
    else
        git clone https://github.com/meradostus/twitch-alice-bot.git "$_dest"
    fi
    exec bash "$_dest/install.sh" "$@"
fi

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

# ── Цвета ────────────────────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'
C='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

# ── Вспомогательные функции ──────────────────────────────────────────────────

hr()  { printf "${B}${BOLD}%s${RESET}\n" "$(printf '%55s' | tr ' ' '━')"; }
h1()  { echo; hr; printf "${BOLD}${C}  ★  %s${RESET}\n" "$1"; hr; echo; }
ok()  { printf "${G}  ✓ %s${RESET}\n" "$1"; }
warn(){ printf "${Y}  ⚠ %s${RESET}\n" "$1"; }
info(){ printf "${DIM}    %s${RESET}\n" "$1"; }
hint(){ printf "${C}    → %s${RESET}\n" "$1"; }
die() { printf "${R}  ✗ %s${RESET}\n" "$1" >&2; exit 1; }

step_hdr() {
    echo
    printf "${BOLD}${Y}  ══════════════════════════════════════════════════${RESET}\n"
    printf "${BOLD}${Y}  Шаг %d: %s${RESET}\n" "$1" "$2"
    printf "${BOLD}${Y}  ══════════════════════════════════════════════════${RESET}\n"
    echo
}

trim() {
    local s="$*"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

# Обязательный ввод (повторяет, пока не введут)
ask_required() {
    local prompt="$1" vn="$2" secret="${3:-}" val=""
    while [[ -z "$val" ]]; do
        if [[ "$secret" == secret ]]; then
            printf "${BOLD}  %s${RESET}: " "$prompt"
            read -rs val; echo
        else
            printf "${BOLD}  %s${RESET}: " "$prompt"
            read -r val
        fi
        val="$(trim "$val")"
        [[ -z "$val" ]] && warn "Поле не может быть пустым"
    done
    printf -v "$vn" '%s' "$val"
}

# Ввод с дефолтным значением
ask_with_default() {
    local prompt="$1" vn="$2" default="$3" secret="${4:-}" val=""
    if [[ "$secret" == secret ]]; then
        printf "${BOLD}  %s${RESET} [Enter = ••••••••]: " "$prompt"
        read -rs val; echo
    else
        printf "${BOLD}  %s${RESET} [Enter = %s]: " "$prompt" "$default"
        read -r val
    fi
    val="$(trim "$val")"
    [[ -z "$val" ]] && val="$default"
    printf -v "$vn" '%s' "$val"
}

# Необязательный ввод
ask_optional() {
    local prompt="$1" vn="$2" secret="${3:-}" val=""
    if [[ "$secret" == secret ]]; then
        printf "${BOLD}  %s${RESET} [Enter = пропустить]: " "$prompt"
        read -rs val; echo
    else
        printf "${BOLD}  %s${RESET} [Enter = пропустить]: " "$prompt"
        read -r val
    fi
    printf -v "$vn" '%s' "$(trim "$val")"
}

# Подтверждение Y/N
confirm() {
    local msg="$1" default="${2:-y}" ans
    if [[ "$default" == y ]]; then
        printf "${BOLD}  %s${RESET} [Y/n]: " "$msg"
    else
        printf "${BOLD}  %s${RESET} [y/N]: " "$msg"
    fi
    read -r ans
    ans="$(trim "$ans")"
    [[ "${ans:-$default}" =~ ^[Yy]$ ]]
}

# Запись строки в .env
write_env_var() { printf '%s=%s\n' "$1" "'$2'"; }

# ─────────────────────────────────────────────────────────────────────────────
# БАННЕР
# ─────────────────────────────────────────────────────────────────────────────
clear
echo
printf "${BOLD}${C}"
cat << 'BANNER'
  ████████╗██╗    ██╗██╗████████╗ ██████╗██╗  ██╗
     ██╔══╝██║    ██║██║╚══██╔══╝██╔════╝██║  ██║
     ██║   ██║ █╗ ██║██║   ██║   ██║     ███████║
     ██║   ██║███╗██║██║   ██║   ██║     ██╔══██║
     ██║   ╚███╔███╔╝██║   ██║   ╚██████╗██║  ██║
     ╚═╝    ╚══╝╚══╝ ╚═╝   ╚═╝    ╚═════╝╚═╝  ╚═╝
BANNER
printf "${RESET}"
printf "${BOLD}         Twitch Alice Bot — Мастер установки${RESET}\n"
echo


# ─────────────────────────────────────────────────────────────────────────────
# ШАГ 1: Проверка системы
# ─────────────────────────────────────────────────────────────────────────────
step_hdr 1 "Проверка системы"

PYTHON=$(command -v python3 2>/dev/null) || die "python3 не найден. Установи: sudo apt install python3"

PY_VER=$("$PYTHON" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
PY_MAJOR="${PY_VER%%.*}"
PY_MINOR="${PY_VER##*.}"

if [[ "$PY_MAJOR" -lt 3 || ( "$PY_MAJOR" -eq 3 && "$PY_MINOR" -lt 11 ) ]]; then
    die "Нужен Python 3.11+, обнаружен $PY_VER"
fi
ok "Python $PY_VER"

if ! command -v sudo &>/dev/null; then
    die "sudo не найден"
fi
ok "sudo доступен"


# ─────────────────────────────────────────────────────────────────────────────
# ШАГ 2: Системные зависимости
# ─────────────────────────────────────────────────────────────────────────────
step_hdr 2 "Системные зависимости"

NEED_APT=()
"$PYTHON" -c "import ensurepip" &>/dev/null 2>&1 || NEED_APT+=("python${PY_VER}-venv")
command -v curl &>/dev/null || NEED_APT+=("curl")

if [[ ${#NEED_APT[@]} -gt 0 ]]; then
    warn "Отсутствуют пакеты: ${NEED_APT[*]}"
    info "Запускаю: sudo apt-get install -y ${NEED_APT[*]}"
    sudo apt-get install -y "${NEED_APT[@]}"
    ok "Пакеты установлены"
else
    ok "Системные зависимости в порядке"
fi


# ─────────────────────────────────────────────────────────────────────────────
# ШАГ 3: Python-окружение
# ─────────────────────────────────────────────────────────────────────────────
step_hdr 3 "Python-окружение"

VENV="$PROJECT_DIR/.venv"
if [[ -d "$VENV" ]]; then
    info "Виртуальное окружение уже существует — обновляю зависимости"
else
    info "Создаю виртуальное окружение..."
    "$PYTHON" -m venv "$VENV"
    ok "Создано: $VENV"
fi

info "Устанавливаю зависимости (это займёт ~30 секунд)..."
"$VENV/bin/pip" install -q --upgrade pip
"$VENV/bin/pip" install -q -r "$PROJECT_DIR/requirements.txt"
ok "Зависимости установлены"


# ─────────────────────────────────────────────────────────────────────────────
# ШАГ 4: Конфигурация
# ─────────────────────────────────────────────────────────────────────────────
step_hdr 4 "Конфигурация"

ENV_FILE="$PROJECT_DIR/.env"
SKIP_CONFIG=false

if [[ -f "$ENV_FILE" ]]; then
    warn "Файл .env уже существует"
    if ! confirm "Перезаписать конфигурацию?"; then
        ok "Конфигурация оставлена без изменений"
        SKIP_CONFIG=true
    fi
fi


if [[ "$SKIP_CONFIG" == false ]]; then

# ═════════════════════════════════════════════════════════════════════════════
h1 "РЕЖИМ МОНИТОРИНГА"
cat << 'DOC'
  Бот поддерживает два режима отслеживания Twitch-каналов:

  1. Twitch API — бот сам опрашивает Twitch API каждые N секунд.
     Требуется приложение на dev.twitch.tv/console/apps.

  2. Telegram (@twiMonBot) — бот слушает уведомления от @twiMonBot.
     Не требует доступа к Twitch API. Нужен Telegram-аккаунт (не бот),
     подключённый к @twiMonBot.
DOC
echo

monitor_mode_value=""
while [[ "$monitor_mode_value" != "twitch" && "$monitor_mode_value" != "telegram" ]]; do
    printf "${BOLD}  Выбери режим:${RESET}\n"
    printf "    1) Twitch API\n"
    printf "    2) Telegram (@twiMonBot)\n"
    printf "${BOLD}  Вариант (1/2)${RESET}: "
    read -r _mode_choice
    case "$(trim "$_mode_choice")" in
        1) monitor_mode_value="twitch"   ; ok "Режим: Twitch API" ;;
        2) monitor_mode_value="telegram" ; ok "Режим: Telegram (@twiMonBot)" ;;
        *) warn "Введи 1 или 2" ;;
    esac
done

# ── Twitch (только для режима twitch) ────────────────────────────────────────
twitch_client_id=""; twitch_client_secret=""
if [[ "$monitor_mode_value" == "twitch" ]]; then

# ═════════════════════════════════════════════════════════════════════════════
h1 "TWITCH"
cat << 'DOC'
  Twitch Client ID и Client Secret — доступ к Twitch API.
  Бот опрашивает API каждые N секунд: онлайн ли нужные каналы.

  Бот использует Client Credentials Flow — это серверная аутентификация
  без участия пользователя. Redirect URL при этом НИКОГДА не вызывается,
  он нужен лишь потому, что консоль Twitch обязывает заполнить это поле.

  КАК ПОЛУЧИТЬ:
  ─────────────────────────────────────────────────────────
  1. Открой https://dev.twitch.tv/console/apps
     (войди под своим аккаунтом Twitch)

  2. Нажми "Register Your Application" (или "+  Application")

  3. Заполни форму:
       Name:                 любое имя, напр. MyAliceBot
       OAuth Redirect URLs:  http://localhost  ← формальность, не используется
       Category:             Chat Bot          ← просто метка, на доступ не влияет

  4. Нажми "Create"

  5. На странице приложения нажми "New Secret"
     ⚠ Секрет показывается ОДИН РАЗ — сразу скопируй его

  6. Скопируй Client ID и Client Secret
  ─────────────────────────────────────────────────────────
DOC
echo

ask_required "Twitch Client ID"     twitch_client_id
ask_required "Twitch Client Secret" twitch_client_secret secret

fi  # конец блока twitch

# ── Telegram user-аккаунт (только для режима telegram) ───────────────────────
tg_api_id=""; tg_api_hash=""; tg_phone=""
if [[ "$monitor_mode_value" == "telegram" ]]; then

# ═════════════════════════════════════════════════════════════════════════════
h1 "TELEGRAM USER-АККАУНТ (@twiMonBot)"
cat << 'DOC'
  Для чтения сообщений от @twiMonBot нужен доступ к Telegram-аккаунту
  пользователя (не бот-токен, а настоящий аккаунт).

  Для этого нужны API_ID и API_HASH. Их можно получить на my.telegram.org,
  или использовать встроенные (Telegram Desktop) — если my.telegram.org
  недоступен или возвращает ошибку.
DOC
echo

_DEFAULT_API_ID="2040"
_DEFAULT_API_HASH="b18441a1ff607e10a989891a5462e627"

if confirm "Использовать встроенные API credentials (Telegram Desktop)?"; then
    tg_api_id="$_DEFAULT_API_ID"
    tg_api_hash="$_DEFAULT_API_HASH"
    ok "Используем встроенные credentials"
else
    cat << 'DOC'

  КАК ПОЛУЧИТЬ API_ID и API_HASH:
  ─────────────────────────────────────────────────────────
  1. Открой https://my.telegram.org и войди под своим аккаунтом
  2. Перейди в раздел "API development tools"
  3. Заполни форму (App title и Short name — любые)
  4. Скопируй App api_id (число) и App api_hash (строка)
  ─────────────────────────────────────────────────────────
DOC
    echo
    ask_required "Telegram API ID (число)"    tg_api_id
    ask_required "Telegram API Hash (строка)" tg_api_hash secret
fi

cat << 'DOC'

  Номер телефона — того аккаунта, которым ты подключён к @twiMonBot.
  Формат: +79001234567 (с кодом страны, без пробелов)
DOC
echo

ask_required "Номер телефона" tg_phone

echo
info "Авторизуюсь в Telegram. На твой телефон придёт код подтверждения..."
echo

mkdir -p "$PROJECT_DIR/data"
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
    api_id   = int(sys.argv[1])
    api_hash = sys.argv[2]
    phone    = normalize_phone(sys.argv[3])
    session  = sys.argv[4]
    print(f"  Номер: {phone}")
    client = TelegramClient(session, api_id, api_hash)
    await client.start(phone=phone)
    me = await client.get_me()
    name = me.first_name or ""
    if me.last_name:
        name += f" {me.last_name}"
    print(f"  Авторизован как: {name} (@{me.username or me.phone})")
    await client.disconnect()

asyncio.run(main())
PYEOF

if "$VENV/bin/python3" "$TMPAUTH" \
        "$tg_api_id" "$tg_api_hash" "$tg_phone" \
        "$PROJECT_DIR/data/telegram_user"; then
    ok "Telegram-сессия сохранена"
else
    die "Авторизация Telegram не удалась — проверь API_ID, API_HASH и номер телефона"
fi
rm -f "$TMPAUTH"

fi  # конец блока telegram


# ═════════════════════════════════════════════════════════════════════════════
h1 "TELEGRAM BOT"
cat << 'DOC'
  Telegram-бот используется для:
  • команд (/subscribe, /unsubscribe, /list, /status)
  • уведомлений об ошибках (Twitch недоступен, Алиса упала)
  • резервного канала, если Алиса недоступна

  КАК СОЗДАТЬ БОТА:
  ─────────────────────────────────────────────────────────
  1. Открой Telegram → найди @BotFather
  2. Отправь /newbot
  3. Придумай имя (отображаемое) и username (должен заканчиваться на bot)
  4. BotFather пришлёт токен вида: 1234567890:AABB-ccDDee...
  ─────────────────────────────────────────────────────────
DOC
echo

ask_required "Bot Token" tg_token

# ── Авто-определение Chat ID ─────────────────────────────────────────────────
echo
cat << 'DOC'
  Теперь нужен Chat ID — числовой идентификатор чата, куда бот
  будет слать уведомления. Скрипт определит его автоматически.

  Сделай прямо сейчас:
    1. Найди своего бота в Telegram по username, который ты задал
    2. Нажми "Start" или отправь любое сообщение боту
    3. Вернись сюда и нажми Enter
DOC

read -r _dummy

TMP_UPD=$(mktemp)
export TMP_UPD
chat_id_auto=""

if curl -sf --max-time 10 \
    "https://api.telegram.org/bot${tg_token}/getUpdates" \
    -o "$TMP_UPD" 2>/dev/null; then

    chat_id_auto=$("$VENV/bin/python3" << 'PYEOF' || true
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

if [[ -n "$chat_id_auto" ]]; then
    ok "Chat ID определён автоматически: $chat_id_auto"
    ask_with_default "Chat ID" tg_chat_id "$chat_id_auto"
else
    cat << 'DOC'

  Не удалось определить автоматически.
  Возможные причины:
    • ты не написал боту в Telegram перед тем как нажать Enter
    • токен введён с ошибкой

  Как узнать Chat ID вручную:
  ─────────────────────────────────────────────────────────
  Найди в Telegram бота @userinfobot и отправь ему /start.
  Он ответит твоим ID — это и есть нужное число.

  Если хочешь получать уведомления в группу (а не в личку):
    1. Добавь своего бота в группу и назначь его администратором
    2. Добавь @userinfobot в ту же группу
    3. @userinfobot ответит ID группы (отрицательное число, напр. -1001234567890)
    4. После этого можно удалить @userinfobot из группы
  ─────────────────────────────────────────────────────────
DOC
    ask_required "Chat ID (число, для группы — отрицательное)" tg_chat_id
fi


# ═════════════════════════════════════════════════════════════════════════════
h1 "ЯНДЕКС АЛИСА (Яндекс Станция)"
cat << 'DOC'
  OAuth-токен Яндекса нужен для отправки голосовых команд на Станцию
  через Quasar API (официальный, но не публично задокументированный).

  ⚠ ВАЖНО: открывай ссылку ниже в браузере, будучи залогиненным
    в тот аккаунт Яндекс, к которому привязана твоя Станция!

  КАК ПОЛУЧИТЬ ТОКЕН:
  ─────────────────────────────────────────────────────────
  1. Скопируй и открой в браузере эту ссылку:

     https://oauth.yandex.ru/authorize?response_type=token&client_id=23cabbbdc6cd418abb4b39c32c41195d

  2. Нажми "Разрешить"

  3. Браузер перенаправит на страницу с ошибкой — это НОРМАЛЬНО

  4. В адресной строке найди параметр access_token=...

     Пример:
     http://localhost/#access_token=AQAAAABmSY9p...&token_type=bearer
                                   ^^^^^^^^^^^^^^^^
                                   Скопируй этот токен

  5. Токен заканчивается на символ перед & (или концом строки)
  ─────────────────────────────────────────────────────────
DOC
echo

ask_required "Yandex OAuth Token" yandex_token secret

# ── Авто-определение устройства ──────────────────────────────────────────────
echo
info "Получаю список устройств Яндекс..."
echo

TMPDEV=$(mktemp)
YANDEX_TOKEN="$yandex_token" "$VENV/bin/python" -m bot.alice_discovery --json \
    > "$TMPDEV" 2>/dev/null || echo '[]' > "$TMPDEV"

DEVICE_COUNT=$("$VENV/bin/python3" << PYEOF
import json
try:
    d = json.load(open("$TMPDEV"))
    print(len(d) if isinstance(d, list) else 0)
except Exception:
    print(0)
PYEOF
)

if [[ "$DEVICE_COUNT" -eq 0 ]]; then
    warn "Устройства не найдены или токен неверный"
    echo
    info "Введи device_id и platform вручную."
    info "Запусти позже: .venv/bin/python -m bot.alice_discovery"
    echo
    ask_required "YANDEX_DEVICE_ID (GUID устройства)" yandex_device_id
    echo
    cat << 'DOC'
  Допустимые значения YANDEX_PLATFORM:
    yandexstation      — Яндекс Станция (оригинал, 2019)
    yandexstation_2    — Яндекс Станция 2 / Макс
    yandexmini         — Яндекс Мини (без экрана)
    yandexmini_2       — Яндекс Мини 2 / с часами
    yandexmicro        — Яндекс Микро
DOC
    echo
    ask_required "YANDEX_PLATFORM" yandex_platform

elif [[ "$DEVICE_COUNT" -eq 1 ]]; then
    # Единственное устройство — берём автоматически
    yandex_device_id=$("$VENV/bin/python3" << PYEOF
import json
d = json.load(open("$TMPDEV"))
print(d[0]["id"])
PYEOF
    )
    yandex_platform=$("$VENV/bin/python3" << PYEOF
import json
d = json.load(open("$TMPDEV"))
print(d[0]["platform"])
PYEOF
    )
    device_name=$("$VENV/bin/python3" << PYEOF
import json
d = json.load(open("$TMPDEV"))
print(d[0].get("name", "—"))
PYEOF
    )
    ok "Устройство: $device_name"
    ok "device_id:  $yandex_device_id"
    ok "platform:   $yandex_platform"

else
    # Несколько устройств — предлагаем выбор
    printf "${BOLD}  Найдено устройств: %d${RESET}\n\n" "$DEVICE_COUNT"

    "$VENV/bin/python3" << PYEOF
import json
with open("$TMPDEV") as f:
    devices = json.load(f)
for i, d in enumerate(devices, 1):
    print(f"  {i}. \033[1m{d.get('name', '—')}\033[0m")
    print(f"     device_id: {d.get('id', '—')}")
    print(f"     platform:  {d.get('platform', '—')}")
    print()
PYEOF

    while true; do
        printf "${BOLD}  Введи номер устройства (1–%d)${RESET}: " "$DEVICE_COUNT"
        read -r dev_num
        dev_num="$(trim "$dev_num")"
        if [[ "$dev_num" =~ ^[0-9]+$ ]] && \
           [[ "$dev_num" -ge 1 ]] && \
           [[ "$dev_num" -le "$DEVICE_COUNT" ]]; then
            idx=$((dev_num - 1))
            yandex_device_id=$("$VENV/bin/python3" << PYEOF
import json
d = json.load(open("$TMPDEV"))
print(d[$idx]["id"])
PYEOF
            )
            yandex_platform=$("$VENV/bin/python3" << PYEOF
import json
d = json.load(open("$TMPDEV"))
print(d[$idx]["platform"])
PYEOF
            )
            ok "Выбрано: $yandex_device_id ($yandex_platform)"
            break
        fi
        warn "Введи число от 1 до $DEVICE_COUNT"
    done
fi
rm -f "$TMPDEV"


# ═════════════════════════════════════════════════════════════════════════════
h1 "EMAIL — резервный канал для ошибок"
cat << 'DOC'
  Email — крайний резерв: используется ТОЛЬКО при недоступности
  и Алисы, и Telegram одновременно.

  Поддерживаются любые SMTP-серверы:
  ─────────────────────────────────────────────────────────
  Gmail:      smtp.gmail.com:587
    ⚠ Нужен App Password (не обычный пароль):
      1. Включи двухфакторную аутентификацию Google
      2. Открой https://myaccount.google.com/apppasswords
      3. Создай пароль для приложения "Почта"
      4. Используй его вместо обычного пароля ниже

  Яндекс:    smtp.yandex.ru:587
    (обычный пароль, если не включена 2FA)

  Mail.ru:   smtp.mail.ru:587
  ─────────────────────────────────────────────────────────
DOC
echo

if confirm "Настроить резервные уведомления по email?" n; then
    ask_required     "SMTP хост (напр. smtp.gmail.com)" email_smtp_host
    ask_with_default "SMTP порт"                        email_smtp_port "587"
    ask_required     "Email отправителя"                email_username
    ask_required     "Пароль / App Password"            email_password secret
    email_from="$email_username"
    ask_required     "Email получателя (куда слать)"    email_to
else
    email_smtp_host=""; email_smtp_port="587"
    email_username=""; email_password=""
    email_from=""; email_to=""
    info "Email пропущен"
fi


# ═════════════════════════════════════════════════════════════════════════════
poll_interval=60
if [[ "$monitor_mode_value" == "twitch" ]]; then
h1 "ПАРАМЕТРЫ МОНИТОРИНГА"
cat << 'DOC'
  Интервал опроса — как часто бот проверяет Twitch API.

  Рекомендуется: 60 секунд.
  Минимум:       30 секунд (более частые запросы нарушают rate limits).
DOC
echo

ask_with_default "Интервал опроса (секунды)" poll_interval "60"
if [[ ! "$poll_interval" =~ ^[0-9]+$ ]] || [[ "$poll_interval" -lt 30 ]]; then
    warn "Установлено минимальное значение: 30"
    poll_interval=30
fi
fi


# ═════════════════════════════════════════════════════════════════════════════
# Записываем .env
# ═════════════════════════════════════════════════════════════════════════════
h1 "ЗАПИСЬ КОНФИГУРАЦИИ"

cat > "$ENV_FILE" << EOF
# Режим мониторинга
$(write_env_var MONITOR_MODE "$monitor_mode_value")

# Twitch (только для MONITOR_MODE=twitch)
$(write_env_var TWITCH_CLIENT_ID     "$twitch_client_id")
$(write_env_var TWITCH_CLIENT_SECRET "$twitch_client_secret")

# Telegram-бот
$(write_env_var TELEGRAM_BOT_TOKEN "$tg_token")
$(write_env_var TELEGRAM_CHAT_ID   "$tg_chat_id")

# Telegram user-аккаунт (только для MONITOR_MODE=telegram)
$(write_env_var TELEGRAM_API_ID   "$tg_api_id")
$(write_env_var TELEGRAM_API_HASH "$tg_api_hash")
$(write_env_var TELEGRAM_PHONE    "$tg_phone")

# Яндекс Алиса
$(write_env_var YANDEX_TOKEN     "$yandex_token")
$(write_env_var YANDEX_DEVICE_ID "$yandex_device_id")
$(write_env_var YANDEX_PLATFORM  "$yandex_platform")

# Email (резервный канал — оставьте пустым чтобы отключить)
$(write_env_var EMAIL_SMTP_HOST "$email_smtp_host")
$(write_env_var EMAIL_SMTP_PORT "$email_smtp_port")
$(write_env_var EMAIL_USERNAME  "$email_username")
$(write_env_var EMAIL_PASSWORD  "$email_password")
$(write_env_var EMAIL_FROM      "$email_from")
$(write_env_var EMAIL_TO        "$email_to")

# Мониторинг
$(write_env_var POLL_INTERVAL "$poll_interval")
$(write_env_var DB_PATH       "data/bot.db")
EOF

chmod 600 "$ENV_FILE"
ok "Файл .env сохранён (права 600 — читает только владелец)"

fi  # конец блока SKIP_CONFIG


# ─────────────────────────────────────────────────────────────────────────────
# ШАГ 5: Тест подключений
# ─────────────────────────────────────────────────────────────────────────────
step_hdr 5 "Тест подключений"

if confirm "Проверить подключения?"; then
    echo
    "$VENV/bin/python3" << PYEOF
import asyncio, sys

MONITOR_MODE = "$monitor_mode_value"

async def main():
    try:
        from bot.config import load_config
        cfg = load_config()
    except Exception as e:
        print(f"  \033[0;31m✗\033[0m Ошибка конфигурации: {e}")
        sys.exit(1)

    results = {}

    if MONITOR_MODE == "twitch":
        from bot.twitch import TwitchClient
        t = TwitchClient(cfg.twitch_client_id, cfg.twitch_client_secret)
        try:
            await t.start()
            results["Twitch API   "] = await t.check_connection()
        except Exception:
            results["Twitch API   "] = False
        finally:
            await t.close()

    from bot.alice import AliceClient
    a = AliceClient(cfg.yandex_token, cfg.yandex_device_id, cfg.yandex_platform)
    try:
        await a.start()
        results["Яндекс Алиса"] = await a.check_connection()
    except Exception:
        results["Яндекс Алиса"] = False
    finally:
        await a.close()

    from aiogram import Bot
    bot = Bot(token=cfg.telegram_bot_token)
    try:
        me = await bot.get_me()
        results[f"Telegram @{me.username:<5}"] = True
    except Exception:
        results["Telegram     "] = False
    finally:
        await bot.session.close()

    ok   = "\033[0;32m  ✓\033[0m"
    fail = "\033[0;31m  ✗\033[0m"
    all_ok = True
    for name, status in results.items():
        print(f"{ok if status else fail} {name}")
        if not status:
            all_ok = False

    if not all_ok:
        print()
        print("  \033[1;33m⚠ Часть сервисов недоступна. Проверь токены в .env\033[0m")
        sys.exit(1)
    else:
        print()
        print("  \033[0;32mВсё подключено!\033[0m")

asyncio.run(main())
PYEOF

fi


# ─────────────────────────────────────────────────────────────────────────────
# ШАГ 6: Systemd — автозапуск
# ─────────────────────────────────────────────────────────────────────────────
step_hdr 6 "Автозапуск (systemd)"

CURRENT_USER="${SUDO_USER:-$USER}"
SERVICE_SRC="$PROJECT_DIR/twitch-alice-bot.service"
SERVICE_DST="/etc/systemd/system/twitch-alice-bot.service"

if confirm "Установить как системный сервис (запуск при загрузке ОС)?"; then
    # Подставляем текущего пользователя в unit-файл
    sed \
        -e "s|__USER__|$CURRENT_USER|g" \
        -e "s|__PROJECT_DIR__|$PROJECT_DIR|g" \
        "$SERVICE_SRC" | sudo tee "$SERVICE_DST" > /dev/null
    sudo systemctl daemon-reload
    sudo systemctl enable twitch-alice-bot
    sudo systemctl restart twitch-alice-bot
    sleep 2
    if systemctl is-active --quiet twitch-alice-bot; then
        ok "Сервис запущен и добавлен в автозапуск"
    else
        warn "Сервис установлен, но не запустился — проверь логи:"
        hint "sudo journalctl -u twitch-alice-bot -n 50"
    fi
else
    info "Пропущено. Ручные команды:"
    hint "$VENV/bin/python -m bot.main                          # запуск напрямую"
    echo
    info "Установка сервиса позже:"
    hint "sudo cp $SERVICE_SRC $SERVICE_DST"
    hint "sudo systemctl enable --now twitch-alice-bot"
fi


# ─────────────────────────────────────────────────────────────────────────────
# ГОТОВО
# ─────────────────────────────────────────────────────────────────────────────
h1 "УСТАНОВКА ЗАВЕРШЕНА"

cat << DOC
  Команды бота в Telegram:
  ────────────────────────────────────────
  /subscribe <логин>   начать следить за каналом
  /unsubscribe <логин> остановить слежение
  /list                список каналов и текущий статус
  /status              состояние Twitch API и Алисы

  Управление сервисом:
  ────────────────────────────────────────
  Логи:         sudo journalctl -u twitch-alice-bot -f
  Перезапуск:   sudo systemctl restart twitch-alice-bot
  Остановка:    sudo systemctl stop twitch-alice-bot

  Конфиг:       $ENV_FILE
                (после изменений → sudo systemctl restart twitch-alice-bot)

DOC
