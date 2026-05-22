#!/usr/bin/env bash
# Настройка резервного Email-канала и проверка SMTP-подключения
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"
VENV="$PROJECT_DIR/.venv"

source "$SCRIPT_DIR/common.sh"
cd "$PROJECT_DIR"

require_venv

h1 "EMAIL — резервный канал для ошибок"
cat << 'DOC'
  Email используется ТОЛЬКО если одновременно недоступны и Алиса, и Telegram.

  Gmail:    smtp.gmail.com:587  (нужен App Password, не обычный пароль)
  Яндекс:   smtp.yandex.ru:587
  Mail.ru:  smtp.mail.ru:587

  Для Gmail App Password:
    https://myaccount.google.com/apppasswords
DOC
echo

cur_host="$(read_env EMAIL_SMTP_HOST)"
cur_port="$(read_env EMAIL_SMTP_PORT)"
cur_user="$(read_env EMAIL_USERNAME)"
cur_pass="$(read_env EMAIL_PASSWORD)"
cur_from="$(read_env EMAIL_FROM)"
cur_to="$(read_env EMAIL_TO)"

[[ -n "$cur_host" ]] && info "Текущие настройки: $cur_user → $cur_host:${cur_port:-587}"
echo

ask_or_keep     "SMTP хост (напр. smtp.gmail.com)" smtp_host "$cur_host"
ask_with_default "SMTP порт"                        smtp_port "${cur_port:-587}"
ask_or_keep     "Email отправителя"                 smtp_user "$cur_user"
ask_or_keep     "Пароль / App Password"             smtp_pass "$cur_pass" secret
smtp_from="$smtp_user"
ask_or_keep     "Email получателя"                  email_to  "$cur_to"

set_env_var EMAIL_SMTP_HOST "$smtp_host"
set_env_var EMAIL_SMTP_PORT "$smtp_port"
set_env_var EMAIL_USERNAME  "$smtp_user"
set_env_var EMAIL_PASSWORD  "$smtp_pass"
set_env_var EMAIL_FROM      "$smtp_from"
set_env_var EMAIL_TO        "$email_to"
ok ".env обновлён"

# ── Проверка ──────────────────────────────────────────────────────────────────
echo
info "Проверяю SMTP-подключение..."
echo

"$VENV/bin/python3" - <<PYEOF
import smtplib, ssl, sys

host    = '$smtp_host'
port    = int('${smtp_port:-587}')
user    = '$smtp_user'
password = '$smtp_pass'
to_addr = '$email_to'

try:
    ctx = ssl.create_default_context()
    with smtplib.SMTP(host, port, timeout=10) as s:
        s.ehlo()
        s.starttls(context=ctx)
        s.login(user, password)
        print('\033[0;32m  ✓ SMTP: подключение и авторизация успешны\033[0m')
except Exception as e:
    print(f'\033[0;31m  ✗ SMTP ошибка: {e}\033[0m')
    sys.exit(1)
PYEOF

echo
if confirm "Отправить тестовое письмо на $email_to?" n; then
    "$VENV/bin/python3" - <<PYEOF
import smtplib, ssl, sys
from email.mime.text import MIMEText

msg = MIMEText('Тестовое письмо от Twitch Alice Bot. Если ты видишь это — Email-канал работает.')
msg['Subject'] = 'Twitch Alice Bot — тест Email'
msg['From']    = '$smtp_from'
msg['To']      = '$email_to'

try:
    ctx = ssl.create_default_context()
    with smtplib.SMTP('$smtp_host', int('${smtp_port:-587}'), timeout=10) as s:
        s.ehlo(); s.starttls(context=ctx)
        s.login('$smtp_user', '$smtp_pass')
        s.sendmail('$smtp_from', '$email_to', msg.as_string())
    print('\033[0;32m  ✓ Письмо отправлено\033[0m')
except Exception as e:
    print(f'\033[0;31m  ✗ Ошибка отправки: {e}\033[0m')
    sys.exit(1)
PYEOF
fi
