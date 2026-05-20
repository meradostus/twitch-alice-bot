import asyncio
import json
import logging
import ssl
import time
import uuid
from typing import Optional

import aiohttp

logger = logging.getLogger(__name__)

_GLAGOL_TOKEN_URL = "https://quasar.yandex.net/glagol/token"
_DEVICES_URL = "https://quasar.yandex.net/glagol/device_list"
_IOT_INFO_URL = "https://api.iot.yandex.net/v1.0/user/info"
_IOT_ACTIONS_URL = "https://api.iot.yandex.net/v1.0/devices/actions"

# SSL-контекст для Glagol WebSocket (самоподписанный сертификат на устройстве)
_SSL_CTX = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
_SSL_CTX.check_hostname = False
_SSL_CTX.verify_mode = ssl.CERT_NONE


class AliceClient:
    def __init__(self, token: str, device_id: str, platform: str, device_ip: str = ""):
        self._token = token
        self._device_id = device_id
        self._platform = platform
        self._device_ip = device_ip
        self._iot_id: Optional[str] = None
        self._session: Optional[aiohttp.ClientSession] = None

    async def start(self):
        self._session = aiohttp.ClientSession(
            headers={"Authorization": f"OAuth {self._token}"},
            timeout=aiohttp.ClientTimeout(total=10),
        )
        if self._device_ip:
            logger.info("Алиса: локальный режим (Glagol WebSocket) → %s", self._device_ip)
        else:
            self._iot_id = await self._resolve_iot_id()
            if self._iot_id:
                logger.info("Алиса: облачный режим (IoT API), id=%s", self._iot_id)
            else:
                logger.warning("Алиса: IoT device ID не определён для %s", self._device_id)

    async def close(self):
        if self._session:
            await self._session.close()

    async def speak(self, text: str) -> str | None:
        """None — успех, строка — сообщение об ошибке."""
        if self._device_ip:
            return await self._speak_local(text)
        return await self._speak_cloud(text)

    async def _speak_local(self, text: str) -> str | None:
        """TTS через Glagol WebSocket (локальная сеть)."""
        import websockets

        try:
            async with self._session.get(
                _GLAGOL_TOKEN_URL,
                params={"device_id": self._device_id, "platform": self._platform},
            ) as resp:
                if resp.status != 200:
                    body = await resp.text()
                    return f"Glagol token HTTP {resp.status}: {body}"
                data = await resp.json()
                glagol_token = data.get("token")
                if not glagol_token:
                    return f"Glagol: токен не получен: {data}"

            msg = json.dumps({
                "conversationToken": glagol_token,
                "id": str(uuid.uuid4()),
                "sentTime": int(time.time() * 1000),
                "payload": {"command": "phrase_speak_it", "text": text},
            })

            async with websockets.connect(
                f"wss://{self._device_ip}:1961",
                ssl=_SSL_CTX,
                open_timeout=5,
                close_timeout=3,
            ) as ws:
                await ws.send(msg)
                # Ждём подтверждение до 5 секунд
                try:
                    await asyncio.wait_for(ws.recv(), timeout=5)
                except asyncio.TimeoutError:
                    pass  # некоторые устройства не отвечают — это нормально
            return None

        except Exception as exc:
            logger.exception("Ошибка Glagol WebSocket")
            return str(exc)

    async def _speak_cloud(self, text: str) -> str | None:
        """TTS через IoT cloud API."""
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
