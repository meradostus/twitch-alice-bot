# Twitch Alice Bot

Мониторинг Twitch-каналов с голосовым оповещением через Яндекс Станцию.

**Репозиторий:** https://github.com/meradostus/twitch-alice-bot

## Схема оповещений

```
Стрим начался → 🔊 Алиса (TTS)
                └─ если Алиса недоступна → 📱 Telegram

Ошибка (Twitch/Алиса) → 📱 Telegram
                         └─ если Telegram недоступен → 📧 Email
```

## Быстрый старт

Одна команда на чистом VPS (Ubuntu/Debian):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/meradostus/twitch-alice-bot/main/install.sh)
```

Скрипт сам установит зависимости, проведёт через настройку всех токенов
с пошаговыми инструкциями и зарегистрирует systemd-сервис.

## Обновление / переустановка

```bash
git pull && bash install.sh
```

При переустановке скрипт предложит сохранить текущий `.env`.

## Клонирование вручную

```bash
git clone https://github.com/meradostus/twitch-alice-bot.git
cd twitch-alice-bot
bash install.sh
```

## Команды бота в Telegram

| Команда | Описание |
|---|---|
| `/subscribe <логин>` | Начать следить за каналом |
| `/unsubscribe <логин>` | Остановить слежение |
| `/list` | Список каналов и текущий статус |
| `/status` | Состояние Twitch API и Алисы |

**Логин** — часть URL канала на Twitch: `twitch.tv/ninja` → логин `ninja`.

## Управление сервисом

```bash
sudo systemctl status twitch-alice-bot      # статус
sudo systemctl restart twitch-alice-bot     # перезапуск
sudo journalctl -u twitch-alice-bot -f      # логи
```

После изменения `.env` — перезапустить сервис.

## Как работает мониторинг

Бот каждые `POLL_INTERVAL` секунд (по умолчанию 60) опрашивает Twitch API.
Когда канал переходит из offline в online — отправляет голосовое уведомление Алисе.
Текст уведомления: **«[Ник] начал стрим. Играет в [игра]»**.

## Структура проекта

```
twitch-alice-bot/
├── bot/
│   ├── alice.py            # Клиент Яндекс Quasar API (TTS)
│   ├── alice_discovery.py  # Утилита поиска device_id Станции
│   ├── config.py           # Конфигурация из .env
│   ├── database.py         # SQLite (aiosqlite)
│   ├── handlers.py         # Telegram-команды
│   ├── main.py             # Точка входа
│   ├── monitor.py          # Цикл опроса Twitch
│   ├── notifier.py         # Цепочка уведомлений: Telegram → Email
│   └── twitch.py           # Twitch Helix API клиент
├── data/                   # SQLite база (bot.db)
├── .env                    # Конфигурация (не коммитить!)
├── .env.example            # Шаблон конфигурации
├── install.sh              # Установщик
├── requirements.txt
└── twitch-alice-bot.service
```
