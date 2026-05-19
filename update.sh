#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

REPO_URL="https://github.com/meradostus/twitch-alice-bot.git"

if ! git rev-parse --git-dir &>/dev/null 2>&1; then
    echo "Директория не является git-репозиторием — инициализирую..."
    git init
    git remote add origin "$REPO_URL"
    git fetch --depth=1 origin main
    git checkout -B main FETCH_HEAD
    git branch --set-upstream-to=origin/main main
    echo "Репозиторий инициализирован"
else
    git pull --ff-only
fi

"$SCRIPT_DIR/.venv/bin/pip" install -r requirements.txt -q
