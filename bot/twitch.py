import logging
from typing import Optional

import aiohttp

logger = logging.getLogger(__name__)

_AUTH_URL = "https://id.twitch.tv/oauth2/token"
_API_URL = "https://api.twitch.tv/helix"


class TwitchClient:
    def __init__(self, client_id: str, client_secret: str):
        self._client_id = client_id
        self._client_secret = client_secret
        self._token: Optional[str] = None
        self._session: Optional[aiohttp.ClientSession] = None

    async def start(self):
        self._session = aiohttp.ClientSession(
            timeout=aiohttp.ClientTimeout(total=15)
        )
        await self._refresh_token()

    async def close(self):
        if self._session:
            await self._session.close()

    async def _refresh_token(self):
        async with self._session.post(_AUTH_URL, params={
            "client_id": self._client_id,
            "client_secret": self._client_secret,
            "grant_type": "client_credentials",
        }) as resp:
            resp.raise_for_status()
            data = await resp.json()
            self._token = data["access_token"]
            logger.info("Twitch: токен обновлён")

    def _headers(self) -> dict:
        return {
            "Client-ID": self._client_id,
            "Authorization": f"Bearer {self._token}",
        }

    async def get_live_streams(self, logins: list[str]) -> list[dict]:
        """Returns list of stream objects for currently live channels."""
        if not logins:
            return []

        result: list[dict] = []
        for i in range(0, len(logins), 100):
            batch = logins[i : i + 100]
            params = [("user_login", login) for login in batch]
            data = await self._request_streams(params)
            result.extend(data)
        return result

    async def _request_streams(self, params: list[tuple], *, retry: bool = True) -> list[dict]:
        async with self._session.get(
            f"{_API_URL}/streams", headers=self._headers(), params=params
        ) as resp:
            if resp.status == 401 and retry:
                await self._refresh_token()
                return await self._request_streams(params, retry=False)
            resp.raise_for_status()
            data = await resp.json()
            return data.get("data", [])

    async def check_connection(self) -> bool:
        try:
            await self._request_streams([("user_login", "twitch")])
            return True
        except Exception:
            return False
