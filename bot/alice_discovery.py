"""
Утилита для обнаружения device_id Яндекс Станции.
Запуск: python -m bot.alice_discovery
         python -m bot.alice_discovery --json   (для скриптов)
"""
import asyncio
import json
import os
import sys

from dotenv import load_dotenv

load_dotenv()


async def get_devices(token: str) -> list[dict]:
    import aiohttp
    async with aiohttp.ClientSession(
        headers={"Authorization": f"OAuth {token}"},
        timeout=aiohttp.ClientTimeout(total=10),
    ) as session:
        async with session.get("https://quasar.yandex.net/glagol/device_list") as resp:
            if resp.status != 200:
                raise RuntimeError(f"HTTP {resp.status}: {await resp.text()}")
            data = await resp.json()
    return data.get("devices", [])


async def main():
    token = os.environ.get("YANDEX_TOKEN")
    if not token:
        msg = "Переменная YANDEX_TOKEN не задана"
        if "--json" in sys.argv:
            print(json.dumps({"error": msg}))
        else:
            print(f"Ошибка: {msg}")
        sys.exit(1)

    as_json = "--json" in sys.argv

    try:
        devices = await get_devices(token)
    except Exception as e:
        if as_json:
            print(json.dumps({"error": str(e)}))
        else:
            print(f"Ошибка API: {e}")
        sys.exit(1)

    if as_json:
        print(json.dumps([
            {"name": d.get("name", ""), "id": d.get("id", ""), "platform": d.get("platform", "")}
            for d in devices
        ]))
        return

    if not devices:
        print("Устройства не найдены. Убедитесь, что токен корректный.")
        return

    print(f"Найдено устройств: {len(devices)}\n")
    for d in devices:
        print(f"  Имя:       {d.get('name', '—')}")
        print(f"  device_id: {d.get('id', '—')}   ← YANDEX_DEVICE_ID")
        print(f"  platform:  {d.get('platform', '—')}   ← YANDEX_PLATFORM")
        print()


if __name__ == "__main__":
    asyncio.run(main())
