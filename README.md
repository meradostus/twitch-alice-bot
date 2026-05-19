# Twitch Alice Bot

Мониторинг Twitch-каналов с голосовым оповещением через Яндекс Станцию.

**Репозиторий:** https://github.com/meradostus/twitch-alice-bot

## Схема оповещений

```
Стрим начался → 🔊 Алиса (TTS)
                └─ если Алиса недоступна → 📱 Telegram

Ошибка → 📱 Telegram
          └─ если Telegram недоступен → 📧 Email
```

## Режимы мониторинга

| Режим | Как работает | Требования |
|---|---|---|
| `twitch` | Опрашивает Twitch API каждые N секунд | Приложение на dev.twitch.tv |
| `telegram` | Слушает уведомления от @twiMonBot | Telegram-аккаунт + @twiMonBot |

Режим выбирается при установке. Сменить после установки: командой `/mode` в боте или `bash switch_mode.sh`.

## Быстрый старт

Одна команда на чистом VPS (Ubuntu/Debian):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/meradostus/twitch-alice-bot/main/install.sh)
```

Скрипт установит зависимости, проведёт через настройку всех токенов и зарегистрирует systemd-сервис.

## Клонирование вручную

```bash
git clone https://github.com/meradostus/twitch-alice-bot.git
cd twitch-alice-bot
bash install.sh
```

## Команды бота в Telegram

| Команда | Описание |
|---|---|
| `/subscribe <логин>` | Подписаться на канал |
| `/unsubscribe <логин>` | Отписаться от канала |
| `/list` | Список каналов и текущий статус |
| `/status` | Состояние сервисов |
| `/mode` | Текущий режим мониторинга и переключение |
| `/update` | Обновить бот с GitHub и перезапустить |
| `/help` | Список всех команд |

**Логин** — часть URL канала на Twitch: `twitch.tv/ninja` → логин `ninja`.

## Обновление бота

Через Telegram — отправь боту `/update`. Бот сделает `git pull`, обновит зависимости и перезапустится автоматически.

Или вручную на сервере:

```bash
bash update.sh
sudo systemctl restart twitch-alice-bot
```

## Переустановка / смена параметров

```bash
bash install.sh
```

При повторном запуске скрипт предложит сохранить уже введённые данные.

## Смена режима мониторинга

Через Telegram: команда `/mode` → кнопка «Переключить». Бот перезапустится автоматически.

Или на сервере:

```bash
bash switch_mode.sh
```

## Управление сервисом

```bash
sudo systemctl status twitch-alice-bot      # статус
sudo systemctl restart twitch-alice-bot     # перезапуск
sudo journalctl -u twitch-alice-bot -f      # логи
```

После изменения `.env` вручную — перезапустить сервис.

## Структура проекта

```
twitch-alice-bot/
├── bot/
│   ├── alice.py              # Клиент Яндекс Quasar API (TTS)
│   ├── alice_discovery.py    # Утилита поиска device_id Станции
│   ├── config.py             # Конфигурация из .env
│   ├── database.py           # SQLite (aiosqlite)
│   ├── handlers.py           # Telegram-команды
│   ├── main.py               # Точка входа
│   ├── monitor.py            # Мониторинг через Twitch API
│   ├── telegram_monitor.py   # Мониторинг через @twiMonBot
│   ├── notifier.py           # Цепочка уведомлений: Telegram → Email
│   └── twitch.py             # Twitch Helix API клиент
├── data/                     # SQLite база и сессии (не коммитить)
├── .env                      # Конфигурация (не коммитить!)
├── .env.example              # Шаблон конфигурации
├── install.sh                # Установщик
├── update.sh                 # Обновление бота
├── switch_mode.sh            # Смена режима мониторинга
├── requirements.txt
└── twitch-alice-bot.service
```
