import asyncio
import logging

from .alice import AliceClient
from .database import Database
from .notifier import Notifier
from .twitch import TwitchClient

logger = logging.getLogger(__name__)


class Monitor:
    def __init__(
        self,
        db: Database,
        twitch: TwitchClient,
        alice: AliceClient,
        notifier: Notifier,
        poll_interval: int,
    ):
        self._db = db
        self._twitch = twitch
        self._alice = alice
        self._notifier = notifier
        self._interval = poll_interval
        self._running = False

    async def run(self):
        self._running = True
        logger.info("Мониторинг запущен (интервал %ds)", self._interval)
        while self._running:
            try:
                await self._tick()
            except Exception as exc:
                logger.exception("Ошибка в цикле мониторинга")
                await self._notifier.error(f"Внутренняя ошибка мониторинга: {exc}")
            await asyncio.sleep(self._interval)

    def stop(self):
        self._running = False

    async def _tick(self):
        channels = await self._db.get_channels()
        if not channels:
            return

        logins = [ch["login"] for ch in channels]
        prev = {ch["login"]: bool(ch["is_live"]) for ch in channels}

        try:
            live_streams = await self._twitch.get_live_streams(logins)
        except Exception as exc:
            logger.error("Twitch API недоступен: %s", exc)
            await self._notifier.error(f"Twitch API недоступен: {exc}")
            return

        live_now = {s["user_login"].lower(): s for s in live_streams}

        for login in logins:
            was_live = prev[login]
            stream = live_now.get(login)
            is_live = stream is not None

            display = stream["user_name"] if stream else None
            await self._db.set_live(login, is_live, display)

            if not was_live and is_live:
                await self._on_stream_start(login, stream)

    async def _on_stream_start(self, login: str, stream: dict):
        display = stream.get("user_name", login)
        game = stream.get("game_name", "")
        title = stream.get("title", "")

        tts = f"{display} начал стрим"
        if game:
            tts += f". Играет в {game}"

        alice_ok = await self._alice.speak(tts)
        if not alice_ok:
            logger.warning("Алиса недоступна, отправляем в Telegram")
            await self._notifier.error("Алиса недоступна")
            fallback = f"{display} начал стрим"
            if game:
                fallback += f"\n🎮 {game}"
            if title:
                fallback += f"\n📺 {title}"
            fallback += f"\n🔗 twitch.tv/{login}"
            await self._notifier.stream_fallback(fallback)
