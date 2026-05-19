import asyncio
import logging
import os
import signal

from aiogram import Bot, Dispatcher

from .alice import AliceClient
from .config import load_config
from .database import Database
from .handlers import router
from .monitor import Monitor
from .notifier import Notifier
from .twitch import TwitchClient

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

    twitch = TwitchClient(cfg.twitch_client_id, cfg.twitch_client_secret)
    await twitch.start()

    alice = AliceClient(cfg.yandex_token, cfg.yandex_device_id, cfg.yandex_platform)
    await alice.start()

    bot = Bot(token=cfg.telegram_bot_token)
    notifier = Notifier(bot, cfg.telegram_chat_id, cfg.email)

    dp = Dispatcher()
    # aiogram 3.x DI: данные доступны как параметры хендлеров
    dp["db"] = db
    dp["twitch"] = twitch
    dp["alice"] = alice
    dp.include_router(router)

    monitor = Monitor(db, twitch, alice, notifier, cfg.poll_interval)

    stop_event = asyncio.Event()

    def handle_signal(sig: signal.Signals):
        logger.info("Сигнал %s — остановка", sig.name)
        monitor.stop()
        stop_event.set()

    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, lambda s=sig: handle_signal(s))

    logger.info("Бот запущен (poll=%ds)", cfg.poll_interval)

    try:
        async with asyncio.TaskGroup() as tg:
            tg.create_task(monitor.run(), name="monitor")
            tg.create_task(dp.start_polling(bot, handle_signals=False), name="telegram")
    except* asyncio.CancelledError:
        pass
    finally:
        monitor.stop()
        await dp.storage.close()
        await twitch.close()
        await alice.close()
        await bot.session.close()
        await db.close()
        logger.info("Бот остановлен")


def run():
    asyncio.run(main())


if __name__ == "__main__":
    run()
