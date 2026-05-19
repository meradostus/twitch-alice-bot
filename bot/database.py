import aiosqlite
from typing import Optional


class Database:
    def __init__(self, path: str):
        self.path = path
        self._db: Optional[aiosqlite.Connection] = None

    async def connect(self):
        self._db = await aiosqlite.connect(self.path)
        self._db.row_factory = aiosqlite.Row
        await self._migrate()

    async def close(self):
        if self._db:
            await self._db.close()

    async def _migrate(self):
        await self._db.executescript("""
            CREATE TABLE IF NOT EXISTS channels (
                id           INTEGER PRIMARY KEY AUTOINCREMENT,
                login        TEXT    UNIQUE NOT NULL COLLATE NOCASE,
                display_name TEXT,
                is_live      INTEGER NOT NULL DEFAULT 0,
                added_at     TEXT    NOT NULL DEFAULT (datetime('now'))
            );
        """)
        await self._db.commit()

    # --- channels ---

    async def add_channel(self, login: str) -> bool:
        """Returns True if added, False if already exists."""
        try:
            await self._db.execute(
                "INSERT INTO channels (login) VALUES (?)",
                (login.lower(),),
            )
            await self._db.commit()
            return True
        except aiosqlite.IntegrityError:
            return False

    async def remove_channel(self, login: str) -> bool:
        """Returns True if removed, False if not found."""
        cur = await self._db.execute(
            "DELETE FROM channels WHERE login = ?",
            (login.lower(),),
        )
        await self._db.commit()
        return cur.rowcount > 0

    async def get_channels(self) -> list[dict]:
        cur = await self._db.execute(
            "SELECT login, display_name, is_live FROM channels ORDER BY login"
        )
        rows = await cur.fetchall()
        return [dict(r) for r in rows]

    async def set_live(self, login: str, is_live: bool, display_name: str | None = None):
        if display_name:
            await self._db.execute(
                "UPDATE channels SET is_live = ?, display_name = ? WHERE login = ?",
                (1 if is_live else 0, display_name, login.lower()),
            )
        else:
            await self._db.execute(
                "UPDATE channels SET is_live = ? WHERE login = ?",
                (1 if is_live else 0, login.lower()),
            )
        await self._db.commit()
