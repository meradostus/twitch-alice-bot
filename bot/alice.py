import logging
from typing import Optional

import aiohttp

logger = logging.getLogger(__name__)

_SEND_URL = "https://quasar.yandex.ru/send_command"
_DEVICES_URL = "https://quasar.yandex.net/glagol/device_list"


class AliceClient:
    def __init__(self, token: str, device_id: str, platform: str):
        self._token = token
        self._device_id = device_id
        self._platform = platform
        self._session: Optional[aiohttp.ClientSession] = None

    async def start(self):
        self._session = aiohttp.ClientSession(
            headers={"Authorization": f"OAuth {self._token}"},
            timeout=aiohttp.ClientTimeout(total=10),
        )

    async def close(self):
        if self._session:
            await self._session.close()

    async def speak(self, text: str) -> str | None:
        """None — успех, строка — сообщение об ошибке."""
        try:
            async with self._session.post(
                _SEND_URL,
                params={"device_id": self._device_id, "platform": self._platform},
                json={"payload": {"command": "phrase_speak_it", "text": text}},
            ) as resp:
                if resp.status == 200:
                    return None
                body = await resp.text()
                error = f"HTTP {resp.status}: {body}"
                logger.warning("Алиса вернула %s", error)
                return error
        except Exception as exc:
            logger.exception("Алиса недоступна")
            return str(exc)

    async def check_connection(self) -> bool:
        try:
            async with self._session.get(_DEVICES_URL) as resp:
                return resp.status == 200
        except Exception:
            return False

    async def list_devices(self) -> list[dict]:
        """Utility: return all Yandex devices (for discovering device_id)."""
        async with self._session.get(_DEVICES_URL) as resp:
            resp.raise_for_status()
            data = await resp.json()
            return data.get("devices", [])
