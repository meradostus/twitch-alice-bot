import asyncio
import logging
import os
import signal
from logging.handlers import TimedRotatingFileHandler

from aiogram import Bot, Dispatcher
from aiogram.client.session.aiohttp import AiohttpSession
from aiogram.types import BotCommand

from .alice import AliceClient
from .config import load_config
from .database import Database
from .handlers import router, COMMANDS_TEXT
from .notifier import Notifier

_LOG_FORMAT = "%(asctime)s %(levelname)-8s %(name)s: %(message)s"
_LOG_DATE = "%Y-%m-%d %H:%M:%S"

logging.basicConfig(
    level=logging.INFO,
    format=_LOG_FORMAT,
    datefmt=_LOG_DATE,
)

_log_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), "logs")
os.makedirs(_log_dir, exist_ok=True)
_file_handler = TimedRotatingFileHandler(
    os.path.join(_log_dir, "bot.log"),
    when="midnight",
    backupCount=7,
    encoding="utf-8",
)
_file_handler.setFormatter(logging.Formatter(_LOG_FORMAT, datefmt=_LOG_DATE))
logging.getLogger().addHandler(_file_handler)

logger = logging.getLogger(__name__)


async def main():
    cfg = load_config()
    os.makedirs(os.path.dirname(cfg.db_path) or ".", exist_ok=True)

    db = Database(cfg.db_path)
    await db.connect()

    alice = AliceClient(cfg.yandex_token, cfg.yandex_device_id, cfg.yandex_platform, cfg.yandex_device_ip)
    await alice.start()

    session = AiohttpSession(proxy=cfg.aiogram_proxy_url) if cfg.aiogram_proxy_url else None
    bot = Bot(token=cfg.telegram_bot_token, session=session) if session else Bot(token=cfg.telegram_bot_token)
    await bot.set_my_commands([
        BotCommand(command="subscribe",   description="Подписаться на канал"),
        BotCommand(command="unsubscribe", description="Отписаться от канала"),
        BotCommand(command="list",        description="Список отслеживаемых каналов"),
        BotCommand(command="status",      description="Состояние сервисов"),
        BotCommand(command="mode",        description="Режим мониторинга и переключение"),
        BotCommand(command="speak",       description="Произнести текст через Алису"),
        BotCommand(command="proxy",       description="MTProto прокси для Telegram"),
        BotCommand(command="update",      description="Обновить бот с GitHub и перезапустить"),
        BotCommand(command="help",        description="Список всех команд"),
    ])
    notifier = Notifier(bot, cfg.telegram_chat_id, cfg.email)

    dp = Dispatcher()
    dp["db"] = db
    dp["alice"] = alice
    dp["monitor_mode"] = cfg.monitor_mode
    dp["admin_chat_id"] = cfg.telegram_chat_id
    dp.include_router(router)

    stop_event = asyncio.Event()

    if cfg.monitor_mode == "telegram":
        from .telegram_monitor import TelegramMonitor
        monitor = TelegramMonitor(cfg, db, alice, notifier)
        logger.info("Режим мониторинга: Telegram (@twiMonBot)")
    else:
        from .twitch import TwitchClient
        from .monitor import Monitor
        twitch = TwitchClient(cfg.twitch_client_id, cfg.twitch_client_secret)
        await twitch.start()
        dp["twitch"] = twitch
        monitor = Monitor(db, twitch, alice, notifier, cfg.poll_interval)
        logger.info("Режим мониторинга: Twitch API (poll=%ds)", cfg.poll_interval)

    def handle_signal(sig: signal.Signals):
        logger.info("Сигнал %s — остановка", sig.name)
        stop_event.set()

    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, lambda s=sig: handle_signal(s))

    mode_label = "Telegram (@twiMonBot)" if cfg.monitor_mode == "telegram" else "Twitch API"
    await notifier.system(f"Бот запущен · {mode_label}\n\n{COMMANDS_TEXT}", parse_mode="HTML")
    logger.info("Бот запущен")

    try:
        async with asyncio.TaskGroup() as tg:
            tg.create_task(monitor.run(), name="monitor")
            tg.create_task(dp.start_polling(bot, handle_signals=False), name="telegram")
    except* asyncio.CancelledError:
        pass
    finally:
        await monitor.stop()
        await dp.storage.close()
        if cfg.monitor_mode == "twitch":
            await twitch.close()
        await alice.close()
        await notifier.system("Бот остановлен")
        logger.info("Бот остановлен")
        await bot.session.close()
        await db.close()


def run():
    asyncio.run(main())


if __name__ == "__main__":
    run()
