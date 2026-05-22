#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Twitch Alice Bot — Удаление
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Цвета ────────────────────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'
C='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

hr()  { printf "${B}${BOLD}%s${RESET}\n" "$(printf '%55s' | tr ' ' '━')"; }
h1()  { echo; hr; printf "${BOLD}${C}  ★  %s${RESET}\n" "$1"; hr; echo; }
ok()  { printf "${G}  ✓ %s${RESET}\n" "$1"; }
warn(){ printf "${Y}  ⚠ %s${RESET}\n" "$1"; }
info(){ printf "${DIM}    %s${RESET}\n" "$1"; }
hint(){ printf "${C}    → %s${RESET}\n" "$1"; }

confirm() {
    local msg="$1" default="${2:-y}" ans
    if [[ "$default" == y ]]; then
        printf "${BOLD}  %s${RESET} [Y/n]: " "$msg"
    else
        printf "${BOLD}  %s${RESET} [y/N]: " "$msg"
    fi
    read -r ans
    ans="${ans#"${ans%%[![:space:]]*}"}"
    ans="${ans%"${ans##*[![:space:]]}"}"
    [[ "${ans:-$default}" =~ ^[Yy]$ ]]
}

SERVICE_NAME="twitch-alice-bot"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# ─────────────────────────────────────────────────────────────────────────────
# БАННЕР
# ─────────────────────────────────────────────────────────────────────────────
clear
echo
printf "${BOLD}${R}"
cat << 'BANNER'
  ╔══════════════════════════════════════════════════╗
  ║        Twitch Alice Bot — Удаление               ║
  ╚══════════════════════════════════════════════════╝
BANNER
printf "${RESET}"
echo
warn "Этот скрипт остановит и удалит бота с этого сервера."
echo
printf "${DIM}  Директория проекта: %s${RESET}\n" "$PROJECT_DIR"
echo

if ! confirm "Продолжить удаление?"; then
    echo
    info "Отменено."
    exit 0
fi


# ─────────────────────────────────────────────────────────────────────────────
# Шаг 1: Остановка и отключение сервиса
# ─────────────────────────────────────────────────────────────────────────────
h1 "Сервис systemd"

if systemctl list-unit-files --quiet "${SERVICE_NAME}.service" 2>/dev/null | grep -q "${SERVICE_NAME}"; then
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        info "Останавливаю сервис..."
        sudo systemctl stop "$SERVICE_NAME"
        ok "Сервис остановлен"
    else
        info "Сервис уже не запущен"
    fi

    info "Отключаю автозапуск..."
    sudo systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    ok "Автозапуск отключён"

    if [[ -f "$SERVICE_FILE" ]]; then
        sudo rm -f "$SERVICE_FILE"
        sudo systemctl daemon-reload
        ok "Unit-файл удалён: $SERVICE_FILE"
    fi
else
    info "Сервис ${SERVICE_NAME} не зарегистрирован в systemd"
fi


# ─────────────────────────────────────────────────────────────────────────────
# Шаг 2: Резервная копия .env
# ─────────────────────────────────────────────────────────────────────────────
h1 "Конфигурация (.env)"

ENV_FILE="$PROJECT_DIR/.env"
if [[ -f "$ENV_FILE" ]]; then
    BACKUP="$HOME/twitch-alice-bot.env.backup"
    if confirm "Сохранить .env в $BACKUP перед удалением?"; then
        cp "$ENV_FILE" "$BACKUP"
        chmod 600 "$BACKUP"
        ok "Сохранено: $BACKUP"
        hint "Пригодится при переустановке на другом сервере"
    else
        warn ".env будет удалён вместе с проектом (без резервной копии)"
    fi
else
    info ".env не найден — пропускаю"
fi


# ─────────────────────────────────────────────────────────────────────────────
# Шаг 3: Удаление файлов проекта
# ─────────────────────────────────────────────────────────────────────────────
h1 "Файлы проекта"

printf "${DIM}  Будет удалено: %s${RESET}\n" "$PROJECT_DIR"
echo

if confirm "Удалить директорию проекта целиком?"; then
    rm -rf "$PROJECT_DIR"
    ok "Удалено: $PROJECT_DIR"
else
    info "Директория оставлена: $PROJECT_DIR"
    hint "Вручную: rm -rf $PROJECT_DIR"
fi


# ─────────────────────────────────────────────────────────────────────────────
# Шаг 4: Tailscale (опционально)
# ─────────────────────────────────────────────────────────────────────────────
h1 "Tailscale (удалённый доступ)"

if command -v tailscale &>/dev/null; then
    if confirm "Удалить Tailscale с этого устройства?" n; then
        sudo tailscale down 2>/dev/null || true
        if command -v apt-get &>/dev/null; then
            sudo apt-get remove -y tailscale 2>/dev/null && ok "Tailscale удалён"
        else
            warn "Удали Tailscale вручную (пакетный менеджер не определён)"
        fi
    else
        info "Tailscale оставлен"
    fi
else
    info "Tailscale не установлен — пропускаю"
fi


# ─────────────────────────────────────────────────────────────────────────────
# ГОТОВО
# ─────────────────────────────────────────────────────────────────────────────
h1 "УДАЛЕНИЕ ЗАВЕРШЕНО"

echo
ok "Twitch Alice Bot удалён с этого сервера"
echo

if [[ -f "$HOME/twitch-alice-bot.env.backup" ]]; then
    info "Резервная копия .env:"
    hint "$HOME/twitch-alice-bot.env.backup"
    echo
fi

info "Установить бота заново на другом сервере:"
hint "bash <(curl -fsSL https://raw.githubusercontent.com/meradostus/twitch-alice-bot/main/install.sh)"
echo
