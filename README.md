# Twitch Alice Bot

Мониторинг Twitch-каналов с голосовым оповещением через Яндекс Станцию.

## Схема оповещений

```
Стрим начался → 🔊 Алиса (TTS)
                └─ если Алиса недоступна → 📱 Telegram

Ошибка (Twitch/Алиса) → 📱 Telegram
                         └─ если Telegram недоступен → 📧 Email
```

## Установка

```bash
bash install.sh
```

Скрипт сам установит зависимости, проведёт через настройку всех токенов
с пошаговыми инструкциями и зарегистрирует systemd-сервис.

## Команды бота в Telegram

| Команда | Описание |
|---|---|
| `/subscribe <логин>` | Начать следить за каналом |
| `/unsubscribe <логин>` | Остановить слежение |
| `/list` | Список каналов и текущий статус |
| `/status` | Состояние Twitch API и Алисы |

## Управление сервисом

```bash
sudo systemctl status twitch-alice-bot      # статус
sudo systemctl restart twitch-alice-bot     # перезапуск
sudo journalctl -u twitch-alice-bot -f      # логи
```

После изменения `.env` — перезапустить сервис.

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
├── install.sh              # Установщик
├── requirements.txt
└── twitch-alice-bot.service
```
