import json, os, subprocess, sys
sys.path.insert(0, "/root/twitch-alice-bot")
from dotenv import load_dotenv
load_dotenv("/root/twitch-alice-bot/.env")

token = os.environ["YANDEX_TOKEN"]
result = subprocess.run(
    ["curl", "-s", "https://api.iot.yandex.net/v1.0/user/info",
     "-H", f"Authorization: OAuth {token}"],
    capture_output=True, text=True
)
data = json.loads(result.stdout)
for d in data.get("devices", []):
    if "M001H9" in str(d.get("external_id", "")):
        print("id:         ", d.get("id"))
        print("name:       ", d.get("name"))
        print("external_id:", d.get("external_id"))
