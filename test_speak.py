"""Тест отправки TTS-команды через разные эндпоинты."""
import asyncio
import os
import aiohttp
from dotenv import load_dotenv

load_dotenv()

TOKEN = os.environ["YANDEX_TOKEN"]
GLAGOL_ID = os.environ["YANDEX_DEVICE_ID"]   # M001H9G00618SK
PLATFORM = os.environ.get("YANDEX_PLATFORM", "yandexmini_2")
IOT_ID = "515a9789-bc6f-4c7f-87d4-536bf322582c"
TEXT = "тест"

TESTS = [
    {
        "name": "send_command / glagol ID / JSON body",
        "method": "POST",
        "url": "https://quasar.yandex.net/send_command",
        "json": {"device_id": GLAGOL_ID, "platform": PLATFORM,
                 "payload": {"command": "phrase_speak_it", "text": TEXT}},
    },
    {
        "name": "send_command / glagol ID / query params",
        "method": "POST",
        "url": "https://quasar.yandex.net/send_command",
        "params": {"device_id": GLAGOL_ID, "platform": PLATFORM},
        "json": {"payload": {"command": "phrase_speak_it", "text": TEXT}},
    },
    {
        "name": "send_command / IoT UUID / JSON body",
        "method": "POST",
        "url": "https://quasar.yandex.net/send_command",
        "json": {"device_id": IOT_ID, "platform": PLATFORM,
                 "payload": {"command": "phrase_speak_it", "text": TEXT}},
    },
    {
        "name": "IoT API actions",
        "method": "POST",
        "url": "https://api.iot.yandex.net/v1.0/devices/actions",
        "json": {"devices": [{"id": IOT_ID, "actions": [
            {"type": "devices.capabilities.quasar.server_action",
             "state": {"instance": "phrase_speak_it", "value": TEXT}}
        ]}]},
    },
]


async def main():
    headers = {"Authorization": f"OAuth {TOKEN}"}
    async with aiohttp.ClientSession(headers=headers,
                                     timeout=aiohttp.ClientTimeout(total=10)) as s:
        for t in TESTS:
            try:
                kwargs = {"json": t.get("json"), "params": t.get("params")}
                async with s.request(t["method"], t["url"], **kwargs) as resp:
                    body = await resp.text()
                    print(f"[{resp.status}] {t['name']}")
                    if resp.status != 200:
                        print(f"       {body[:120]}")
            except Exception as e:
                print(f"[ERR] {t['name']}: {e}")

asyncio.run(main())
