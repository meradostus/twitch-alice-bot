import asyncio
import logging
import os
import signal

from aiogram import Bot, Dispatcher
from aiogram.types import BotCommand

from .alice import AliceClient
from .config import load_config
from .database import Database
from .handlers import router
from .notifier import Notifier

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)-8s %(name)s: %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)


async def main():
    cfg = load_config()
    os.makedirs(os.path.dirname(cfg.db_path) or ".", exist_ok=True)

    db = Database(cfg.db_path)
    await db.connect()

    alice = AliceClient(cfg.yandex_token, cfg.yandex_device_id, cfg.yandex_platform)
    await alice.start()

    bot = Bot(token=cfg.telegram_bot_token)
    await bot.set_my_commands([
        BotCommand(command="subscribe",   description="Подписаться на канал"),
        BotCommand(command="unsubscribe", description="Отписаться от канала"),
        BotCommand(command="list",        description="Список отслеживаемых каналов"),
        BotCommand(command="status",      description="Состояние сервисов"),
        BotCommand(command="mode",        description="Режим мониторинга и переключение"),
    ])
    notifier = Notifier(bot, cfg.telegram_chat_id, cfg.email)

    dp = Dispatcher()
    dp["db"] = db
    dp["alice"] = alice
    dp["monitor_mode"] = cfg.monitor_mode
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
        await bot.session.close()
        await db.close()
        logger.info("Бот остановлен")


def run():
    asyncio.run(main())


if __name__ == "__main__":
    run()
