import logging
from typing import Optional

import aiohttp

logger = logging.getLogger(__name__)

_DEVICES_URL = "https://quasar.yandex.net/glagol/device_list"
_IOT_INFO_URL = "https://api.iot.yandex.net/v1.0/user/info"
_IOT_ACTIONS_URL = "https://api.iot.yandex.net/v1.0/devices/actions"


class AliceClient:
    def __init__(self, token: str, device_id: str, platform: str):
        self._token = token
        self._device_id = device_id
        self._platform = platform
        self._iot_id: Optional[str] = None
        self._session: Optional[aiohttp.ClientSession] = None

    async def start(self):
        self._session = aiohttp.ClientSession(
            headers={"Authorization": f"OAuth {self._token}"},
            timeout=aiohttp.ClientTimeout(total=10),
        )
        self._iot_id = await self._resolve_iot_id()
        if self._iot_id:
            logger.info("Alice IoT device ID: %s", self._iot_id)
        else:
            logger.warning("Не удалось определить IoT device ID для %s", self._device_id)

    async def close(self):
        if self._session:
            await self._session.close()

    async def speak(self, text: str) -> str | None:
        """None — успех, строка — сообщение об ошибке."""
        if not self._iot_id:
            return f"IoT device ID не определён для {self._device_id}"
        try:
            async with self._session.post(_IOT_ACTIONS_URL, json={
                "devices": [{
                    "id": self._iot_id,
                    "actions": [{
                        "type": "devices.capabilities.quasar.server_action",
                        "state": {
                            "instance": "phrase_speak_it",
                            "value": text,
                        },
                    }],
                }],
            }) as resp:
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

    async def _resolve_iot_id(self) -> Optional[str]:
        try:
            async with self._session.get(_IOT_INFO_URL) as resp:
                data = await resp.json()
            for d in data.get("devices", []):
                if d.get("external_id", "").startswith(self._device_id):
                    return d["id"]
        except Exception:
            logger.exception("Ошибка при определении IoT device ID")
        return None
