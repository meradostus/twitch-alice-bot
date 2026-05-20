import asyncio
import logging
import os
import re
import signal
from pathlib import Path
from typing import Optional
from urllib.parse import urlparse, parse_qs

from aiogram import Router
from aiogram.filters import Command
from aiogram.types import (
    CallbackQuery,
    InlineKeyboardButton,
    InlineKeyboardMarkup,
    Message,
)

from .alice import AliceClient
from .database import Database
from .twitch import TwitchClient

logger = logging.getLogger(__name__)
router = Router()

_ENV_PATH = Path(__file__).parent.parent / ".env"
_SESSION_PATH = Path(__file__).parent.parent / "data" / "telegram_user.session"

_LOGIN_HINT = (
    "\n\nЛогин — это часть URL канала на Twitch:\n"
    "<code>twitch.tv/<b>ninja</b></code> → логин: <code>ninja</code>"
)


# ── .env helpers ──────────────────────────────────────────────────────────────

def _read_env(key: str) -> str:
    if not _ENV_PATH.exists():
        return ""
    for line in _ENV_PATH.read_text().splitlines():
        m = re.match(rf"^{key}='?([^'\n]*)'?", line.strip())
        if m:
            return m.group(1)
    return ""


def _write_env(key: str, value: str) -> None:
    content = _ENV_PATH.read_text() if _ENV_PATH.exists() else ""
    new_line = f"{key}='{value}'"
    if re.search(rf"^{key}=", content, re.MULTILINE):
        content = re.sub(rf"^{key}=.*$", new_line, content, flags=re.MULTILINE)
    else:
        content += f"\n{new_line}\n"
    _ENV_PATH.write_text(content)


def _can_switch_to(target: str) -> tuple[bool, str]:
    if target == "twitch":
        if not _read_env("TWITCH_CLIENT_ID") or not _read_env("TWITCH_CLIENT_SECRET"):
            return False, "нет Twitch credentials — запусти <code>bash switch_mode.sh</code>"
        return True, ""
    if target == "telegram":
        if not _read_env("TELEGRAM_API_ID"):
            return False, "нет Telegram API credentials — запусти <code>bash switch_mode.sh</code>"
        if not _SESSION_PATH.exists():
            return False, "нет Telegram-сессии — запусти <code>bash switch_mode.sh</code>"
        return True, ""
    return False, "неизвестный режим"


# ── команды ───────────────────────────────────────────────────────────────────

_UPDATE_SCRIPT = Path(__file__).parent.parent / "update.sh"


COMMANDS_TEXT = (
    "/subscribe &lt;логин&gt; — подписаться на канал\n"
    "/unsubscribe &lt;логин&gt; — отписаться от канала\n"
    "/list — список отслеживаемых каналов\n"
    "/status — состояние сервисов\n"
    "/mode — режим мониторинга и переключение\n"
    "/speak &lt;текст&gt; — произнести текст через Алису\n"
    "/proxy — MTProto прокси для Telegram\n"
    "/update — обновить бот с GitHub и перезапустить\n"
    "/help — список всех команд"
)

_HELP_TEXT = (
    "👾 <b>Twitch-Alice Bot</b>\n\n"
    "<b>Подписки:</b>\n"
    "/subscribe &lt;логин&gt; — подписаться на канал\n"
    "/unsubscribe &lt;логин&gt; — отписаться от канала\n"
    "/list — список отслеживаемых каналов\n\n"
    "<b>Информация:</b>\n"
    "/status — состояние сервисов\n"
    "/mode — режим мониторинга и переключение\n\n"
    "<b>Алиса:</b>\n"
    "/speak &lt;текст&gt; — произнести текст через Алису\n\n"
    "<b>Обслуживание:</b>\n"
    "/proxy — просмотр и смена MTProto прокси\n"
    "/update — обновить бот с GitHub и перезапустить\n"
    "/help — список всех команд"
    + _LOGIN_HINT
)


@router.message(Command("start", "help"))
async def cmd_start(message: Message):
    await message.answer(_HELP_TEXT, parse_mode="HTML")


@router.message(Command("subscribe"))
async def cmd_subscribe(message: Message, db: Database, twitch: Optional[TwitchClient] = None):
    args = (message.text or "").split(maxsplit=1)
    if len(args) < 2 or not args[1].strip():
        await message.answer(
            "Укажи логин канала: /subscribe &lt;логин&gt;" + _LOGIN_HINT,
            parse_mode="HTML",
        )
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
        await message.answer(
            "Укажи логин канала: /unsubscribe &lt;логин&gt;" + _LOGIN_HINT,
            parse_mode="HTML",
        )
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
async def cmd_status(
    message: Message,
    db: Database,
    alice: AliceClient,
    monitor_mode: str = "twitch",
    twitch: Optional[TwitchClient] = None,
):
    alice_ok = await alice.check_connection()
    channels = await db.get_channels()
    lines = []
    if monitor_mode == "twitch" and twitch is not None:
        twitch_ok = await twitch.check_connection()
        lines.append(f"Twitch API: {'✅' if twitch_ok else '❌'}")
    else:
        lines.append("Источник:   ✅ @twiMonBot")
    lines += [
        f"Алиса:      {'✅' if alice_ok else '❌'}",
        f"Каналов:    {len(channels)}",
        f"Режим:      {monitor_mode}",
    ]
    await message.answer("\n".join(lines))


@router.message(Command("mode"))
async def cmd_mode(message: Message, monitor_mode: str = "twitch"):
    target = "telegram" if monitor_mode == "twitch" else "twitch"
    mode_desc = "Telegram (@twiMonBot)" if monitor_mode == "telegram" else "Twitch API"
    can_switch, reason = _can_switch_to(target)

    text = f"📡 <b>Режим мониторинга:</b> <code>{monitor_mode}</code>\n{mode_desc}"

    if can_switch:
        kb = InlineKeyboardMarkup(inline_keyboard=[[
            InlineKeyboardButton(
                text=f"🔄 Переключить на {target}",
                callback_data=f"switch_mode:{target}",
            )
        ]])
        await message.answer(text, parse_mode="HTML", reply_markup=kb)
    else:
        text += f"\n\n⚠️ Переключение на <code>{target}</code> недоступно:\n{reason}"
        await message.answer(text, parse_mode="HTML")


# ── callback: смена режима ────────────────────────────────────────────────────

@router.callback_query(lambda c: c.data and c.data.startswith("switch_mode:"))
async def cb_switch_mode(callback: CallbackQuery, monitor_mode: str = "twitch"):
    target = (callback.data or "").split(":", 1)[1]

    if target == monitor_mode:
        await callback.answer("Уже в этом режиме")
        return

    can_switch, reason = _can_switch_to(target)
    if not can_switch:
        await callback.answer("Невозможно переключить", show_alert=True)
        return

    _write_env("MONITOR_MODE", target)
    await callback.message.edit_text(
        f"✅ Режим изменён на <code>{target}</code>. Перезапуск...",
        parse_mode="HTML",
    )
    await callback.answer()
    await asyncio.sleep(1)
    os._exit(0)


# ── /speak ────────────────────────────────────────────────────────────────────

@router.message(Command("speak"))
async def cmd_speak(message: Message, alice: AliceClient, admin_chat_id: int):
    if message.chat.id != admin_chat_id:
        return
    args = (message.text or "").split(maxsplit=1)
    if len(args) < 2 or not args[1].strip():
        await message.answer("Укажи текст: /speak &lt;текст&gt;", parse_mode="HTML")
        return
    text = args[1].strip()
    error = await alice.speak(text)
    if error is None:
        await message.answer("✅ Алиса произносит текст")
    else:
        await message.answer(f"❌ Алиса недоступна: <code>{error}</code>", parse_mode="HTML")


# ── /proxy ────────────────────────────────────────────────────────────────────

def _parse_proxy_link(link: str) -> tuple[str, int, str] | None:
    """Парсит tg://proxy?server=...&port=...&secret=... → (server, port, secret)."""
    try:
        parsed = urlparse(link.strip())
        if parsed.scheme != "tg" or parsed.hostname != "proxy":
            return None
        p = parse_qs(parsed.query)
        server = p.get("server", [""])[0]
        secret = p.get("secret", [""])[0]
        port = int(p.get("port", ["443"])[0])
        if not server or not secret:
            return None
        return server, port, secret
    except Exception:
        return None


@router.message(Command("proxy"))
async def cmd_proxy(message: Message, admin_chat_id: int):
    if message.chat.id != admin_chat_id:
        return

    args = (message.text or "").split(maxsplit=1)

    if len(args) < 2:
        server = _read_env("TELEGRAM_PROXY_SERVER")
        if server:
            port = _read_env("TELEGRAM_PROXY_PORT") or "443"
            secret = _read_env("TELEGRAM_PROXY_SECRET")
            await message.answer(
                f"🌐 <b>MTProto прокси:</b>\n"
                f"Сервер: <code>{server}:{port}</code>\n"
                f"Секрет: <code>{secret[:8]}…</code>\n\n"
                f"Сменить: <code>/proxy tg://proxy?server=…</code>\n"
                f"Отключить: <code>/proxy off</code>",
                parse_mode="HTML",
            )
        else:
            await message.answer(
                "🌐 <b>MTProto прокси:</b> не настроен\n\n"
                "Настроить: <code>/proxy tg://proxy?server=…&port=…&secret=…</code>",
                parse_mode="HTML",
            )
        return

    arg = args[1].strip()

    if arg.lower() == "off":
        _write_env("TELEGRAM_PROXY_SERVER", "")
        _write_env("TELEGRAM_PROXY_PORT", "")
        _write_env("TELEGRAM_PROXY_SECRET", "")
        await message.answer("✅ Прокси отключён. Перезапуск...")
        await asyncio.sleep(1)
        os._exit(0)

    result = _parse_proxy_link(arg)
    if not result:
        await message.answer(
            "❌ Неверный формат. Ожидается ссылка вида:\n"
            "<code>tg://proxy?server=…&port=…&secret=…</code>",
            parse_mode="HTML",
        )
        return

    server, port, secret = result
    _write_env("TELEGRAM_PROXY_SERVER", server)
    _write_env("TELEGRAM_PROXY_PORT", str(port))
    _write_env("TELEGRAM_PROXY_SECRET", secret)
    await message.answer(
        f"✅ Прокси обновлён: <code>{server}:{port}</code>\nПерезапуск...",
        parse_mode="HTML",
    )
    await asyncio.sleep(1)
    os._exit(0)


# ── /update ───────────────────────────────────────────────────────────────────

@router.message(Command("update"))
async def cmd_update(message: Message, admin_chat_id: int):
    if message.chat.id != admin_chat_id:
        return

    status_msg = await message.answer("⏳ Получаю обновления...")

    proc = await asyncio.create_subprocess_exec(
        "bash", str(_UPDATE_SCRIPT),
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT,
    )
    stdout, _ = await proc.communicate()
    output = stdout.decode().strip() or "(нет вывода)"

    if proc.returncode != 0:
        await status_msg.edit_text(
            f"❌ Ошибка обновления:\n<code>{output[-1500:]}</code>",
            parse_mode="HTML",
        )
        return

    await status_msg.edit_text(
        f"✅ Обновлено:\n<code>{output[-1500:]}</code>\n\nПерезапускаю...",
        parse_mode="HTML",
    )
    await asyncio.sleep(1)
    os._exit(0)
