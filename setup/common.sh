#!/usr/bin/env bash
# Общие хелперы для setup-скриптов. Подключать через: source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
# Перед подключением должны быть определены: PROJECT_DIR, ENV_FILE, VENV

# ── Цвета ────────────────────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'
C='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

hr()  { printf "${B}${BOLD}%s${RESET}\n" "$(printf '%55s' | tr ' ' '━')"; }
h1()  { echo; hr; printf "${BOLD}${C}  ★  %s${RESET}\n" "$1"; hr; echo; }
ok()  { printf "${G}  ✓ %s${RESET}\n" "$1"; }
warn(){ printf "${Y}  ⚠ %s${RESET}\n" "$1"; }
info(){ printf "${DIM}    %s${RESET}\n" "$1"; }
hint(){ printf "${C}    → %s${RESET}\n" "$1"; }
die() { printf "${R}  ✗ %s${RESET}\n" "$1" >&2; exit 1; }

trim() {
    local s="$*"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

confirm() {
    local msg="$1" default="${2:-y}" ans
    if [[ "$default" == y ]]; then
        printf "${BOLD}  %s${RESET} [Y/n]: " "$msg"
    else
        printf "${BOLD}  %s${RESET} [y/N]: " "$msg"
    fi
    read -r ans || true
    ans="${ans%$'\r'}"
    ans="${ans:0:1}"
    [[ "${ans:-$default}" =~ ^[Yy]$ ]]
}

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

ask_or_keep() {
    local prompt="$1" vn="$2" current="$3" secret="${4:-}" val=""
    if [[ -n "$current" ]]; then
        if [[ "$secret" == secret ]]; then
            printf "${BOLD}  %s${RESET} [${DIM}сохранён — Enter чтобы оставить${RESET}]: " "$prompt"
            read -rs val; echo
        else
            local disp="$current"
            [[ "${#current}" -gt 28 ]] && disp="${current:0:12}…${current: -4}"
            printf "${BOLD}  %s${RESET} [${DIM}%s${RESET}]: " "$prompt" "$disp"
            read -r val
        fi
        val="$(trim "$val")"
        printf -v "$vn" '%s' "${val:-$current}"
    else
        ask_required "$prompt" "$vn" "$secret"
    fi
}

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

# Читает значение переменной из .env
read_env() { grep "^${1}=" "$ENV_FILE" 2>/dev/null | cut -d= -f2- | tr -d "'\""; }

# Обновляет или добавляет переменную в .env
set_env_var() {
    local key="$1" value="$2"
    local new_line="${key}='${value}'"
    if [[ ! -f "$ENV_FILE" ]]; then
        echo "$new_line" > "$ENV_FILE"
        chmod 600 "$ENV_FILE"
        return
    fi
    if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
        local tmp; tmp=$(mktemp)
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" =~ ^${key}= ]]; then echo "$new_line"
            else echo "$line"; fi
        done < "$ENV_FILE" > "$tmp"
        mv "$tmp" "$ENV_FILE"
    else
        echo "$new_line" >> "$ENV_FILE"
    fi
    chmod 600 "$ENV_FILE"
}

require_venv() {
    [[ -d "$VENV" ]] || die "Python venv не найден: $VENV — сначала запусти bash install.sh"
}
