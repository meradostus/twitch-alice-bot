import logging
import re

from telethon import TelegramClient, events

from .alice import AliceClient
from .config import Config
from .database import Database
from .notifier import Notifier

logger = logging.getLogger(__name__)

_TWIMON = "twiMonBot"
_URL_RE = re.compile(r'https?://twitch\.tv/(\w+)', re.IGNORECASE)
_EMOJI_RE = re.compile(r'^[\U00010000-\U0010ffff☀-➿\s]+')


class TelegramMonitor:
    def __init__(self, cfg: Config, db: Database, alice: AliceClient, notifier: Notifier):
        self._cfg = cfg
        self._db = db
        self._alice = alice
        self._notifier = notifier
        self._client: TelegramClient | None = None

    async def run(self):
        proxy = self._cfg.telegram_proxy
        self._client = TelegramClient(
            self._cfg.telegram_session_path,
            self._cfg.telegram_api_id,
            self._cfg.telegram_api_hash,
            proxy=("mtproto", proxy.server, proxy.port, proxy.secret) if proxy else None,
        )
        if proxy:
            logger.info("Telegram-монитор: MTProto прокси %s:%d", proxy.server, proxy.port)
        await self._client.start(phone=self._cfg.telegram_phone)
        logger.info("Telegram-монитор запущен, слежу за @%s", _TWIMON)

        twimon = await self._client.get_entity(_TWIMON)

        @self._client.on(events.NewMessage(from_users=twimon))
        async def handler(event):
            try:
                await self._handle(event.message.text or "")
            except Exception as exc:
                logger.exception("Ошибка обработки сообщения twiMonBot: %s", exc)

        await self._client.run_until_disconnected()

    async def stop(self):
        if self._client and self._client.is_connected():
            await self._client.disconnect()

    async def _handle(self, text: str):
        lines = [line.strip() for line in text.strip().splitlines() if line.strip()]
        if len(lines) < 2:
            return

        url_match = _URL_RE.search(lines[-1])
        if not url_match:
            return

        login = url_match.group(1).lower()

        channels = await self._db.get_channels()
        if login not in {ch["login"] for ch in channels}:
            logger.debug("Канал %s не в подписках, пропускаем", login)
            return

        first_line = _EMOJI_RE.sub("", lines[0]).strip()
        parts = first_line.rsplit(" — ", 1)
        title = parts[0].strip()
        category = parts[1].strip() if len(parts) == 2 else ""

        ch_map = {ch["login"]: ch for ch in channels}
        display = ch_map[login].get("display_name") or login

        await self._db.set_live(login, True, display)
        await self._on_stream_start(login, display, title, category)

    async def _on_stream_start(self, login: str, display: str, title: str, category: str):
        tts = f"{display} начал стрим"
        if category:
            tts += f". Категория: {category}"

        alice_error = await self._alice.speak(tts)
        if alice_error is not None:
            logger.warning("Алиса недоступна (%s), уведомление в Telegram", alice_error)
            fallback = f"{display} начал стрим"
            if category:
                fallback += f"\n🎮 {category}"
            if title:
                fallback += f"\n📺 {title}"
            fallback += f"\n🔗 twitch.tv/{login}"
            await self._notifier.stream_fallback(fallback)
