#!/usr/bin/env bash
# Диагностика Яндекс IoT API — проверяет устройства и их capabilities
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VENV="$PROJECT_DIR/.venv"

cd "$PROJECT_DIR"

ENV_FILE="$PROJECT_DIR/.env" "$VENV/bin/python3" - << 'PYEOF'
import asyncio, aiohttp, os, sys, json
from dotenv import load_dotenv
load_dotenv(os.environ["ENV_FILE"])

async def main():
    token     = os.getenv("YANDEX_TOKEN", "")
    device_id = os.getenv("YANDEX_DEVICE_ID", "")
    iot_id    = os.getenv("YANDEX_IOT_ID", "")  # если был сохранён отдельно

    if not token:
        print("✗ YANDEX_TOKEN не задан в .env")
        sys.exit(1)

    headers = {"Authorization": f"OAuth {token}"}

    async with aiohttp.ClientSession(headers=headers, timeout=aiohttp.ClientTimeout(total=10)) as s:

        # 1. Glagol device list
        print("=== Glagol устройства (quasar.yandex.net) ===")
        async with s.get("https://quasar.yandex.net/glagol/device_list") as r:
            data = await r.json()
        for d in data.get("devices", []):
            print(f"  id={d.get('id')}  platform={d.get('platform')}  name={d.get('name')}")
        print()

        # 2. IoT user info
        print("=== IoT устройства (api.iot.yandex.net) ===")
        async with s.get("https://api.iot.yandex.net/v1.0/user/info") as r:
            data = await r.json()
        devices = data.get("devices", [])
        if not devices:
            print("  (пусто — устройств в Smart Home нет)")
        for d in devices:
            caps = [c["type"] for c in d.get("capabilities", [])]
            ext  = d.get("external_id", "")
            match = "  ← MATCH" if device_id and ext.startswith(device_id) else ""
            print(f"  id={d['id']}")
            print(f"  external_id={ext}{match}")
            print(f"  capabilities={caps or '[]'}")
            print()

        # 3. Тест TTS если нашли IoT id
        print("=== Тест TTS (phrase_speak_it) ===")
        iot_device_id = None
        for d in data.get("devices", []):
            if device_id and d.get("external_id", "").startswith(device_id):
                iot_device_id = d["id"]
                break

        if not iot_device_id:
            print("  Устройство не найдено в IoT API")
            print(f"  YANDEX_DEVICE_ID = {device_id!r}")
            print("  → TTS через облако недоступен, нужен Glagol (локальный IP)")
        else:
            print(f"  Найден IoT id: {iot_device_id}")
            payload = {"devices": [{"id": iot_device_id, "actions": [{"type": "devices.capabilities.quasar.server_action", "state": {"instance": "phrase_speak_it", "value": "тест"}}]}]}
            async with s.post("https://api.iot.yandex.net/v1.0/devices/actions", json=payload) as r:
                body = await r.text()
                if r.status == 200:
                    print(f"  ✓ TTS OK (HTTP 200)")
                else:
                    print(f"  ✗ TTS failed: HTTP {r.status}")
                    print(f"  body: {body}")

asyncio.run(main())
PYEOF
