import logging

from aiogram import Router
from aiogram.filters import Command
from aiogram.types import Message

from .alice import AliceClient
from .database import Database
from .twitch import TwitchClient

logger = logging.getLogger(__name__)
router = Router()


@router.message(Command("start"))
async def cmd_start(message: Message):
    await message.answer(
        "👾 <b>Twitch-Alice Bot</b>\n\n"
        "/subscribe &lt;канал&gt; — подписаться на канал\n"
        "/unsubscribe &lt;канал&gt; — отписаться\n"
        "/list — список отслеживаемых каналов\n"
        "/status — состояние сервисов",
        parse_mode="HTML",
    )


@router.message(Command("subscribe"))
async def cmd_subscribe(message: Message, db: Database, twitch: TwitchClient):
    args = (message.text or "").split(maxsplit=1)
    if len(args) < 2 or not args[1].strip():
        await message.answer("Укажи логин: /subscribe &lt;канал&gt;", parse_mode="HTML")
        return

    login = args[1].strip().lower().lstrip("@").split("/")[-1]
    added = await db.add_channel(login)
    if added:
        await message.answer(f"✅ <b>{login}</b> добавлен в мониторинг", parse_mode="HTML")
    else:
        await message.answer(f"ℹ️ <b>{login}</b> уже отслеживается", parse_mode="HTML")


@router.message(Command("unsubscribe"))
async def cmd_unsubscribe(message: Message, db: Database):
    args = (message.text or "").split(maxsplit=1)
    if len(args) < 2 or not args[1].strip():
        await message.answer("Укажи логин: /unsubscribe &lt;канал&gt;", parse_mode="HTML")
        return

    login = args[1].strip().lower().lstrip("@").split("/")[-1]
    removed = await db.remove_channel(login)
    if removed:
        await message.answer(f"✅ <b>{login}</b> удалён из мониторинга", parse_mode="HTML")
    else:
        await message.answer(f"ℹ️ <b>{login}</b> не найден в списке", parse_mode="HTML")


@router.message(Command("list"))
async def cmd_list(message: Message, db: Database):
    channels = await db.get_channels()
    if not channels:
        await message.answer(
            "Список пуст. Добавь каналы через /subscribe &lt;канал&gt;", parse_mode="HTML"
        )
        return

    lines = []
    for ch in channels:
        name = ch["display_name"] or ch["login"]
        status = "🔴 Live" if ch["is_live"] else "⚫ Offline"
        lines.append(f"{status} <b>{name}</b>")

    await message.answer("\n".join(lines), parse_mode="HTML")


@router.message(Command("status"))
async def cmd_status(message: Message, db: Database, twitch: TwitchClient, alice: AliceClient):
    twitch_ok = await twitch.check_connection()
    alice_ok = await alice.check_connection()
    channels = await db.get_channels()

    lines = [
        f"Twitch API: {'✅' if twitch_ok else '❌'}",
        f"Алиса:      {'✅' if alice_ok else '❌'}",
        f"Каналов:    {len(channels)}",
    ]
    await message.answer("\n".join(lines))
