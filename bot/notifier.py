"""
Цепочка уведомлений об ошибках:
  Telegram → Email (если Telegram недоступен)

Уведомления о стриме:
  Алиса → Telegram (если Алиса недоступна)
"""
import asyncio
import logging
import smtplib
import ssl
from email.message import EmailMessage
from typing import Optional

from aiogram import Bot
from aiogram.exceptions import TelegramAPIError

from .config import EmailConfig

logger = logging.getLogger(__name__)


class Notifier:
    def __init__(self, bot: Bot, chat_id: int, email_cfg: EmailConfig):
        self._bot = bot
        self._chat_id = chat_id
        self._email_cfg = email_cfg

    # --- public API ---

    async def error(self, text: str):
        """Отправить сообщение об ошибке: Telegram → Email."""
        tg_ok = await self._telegram(f"⚠️ {text}")
        if not tg_ok and self._email_cfg.enabled:
            await self._email(f"[twitch-alice-bot] Ошибка", text)

    async def stream_fallback(self, text: str):
        """Telegram-фолбэк когда Алиса недоступна."""
        await self._telegram(f"🔴 {text}")

    # --- internals ---

    async def _telegram(self, text: str) -> bool:
        try:
            await self._bot.send_message(self._chat_id, text)
            return True
        except TelegramAPIError as exc:
            logger.error("Telegram недоступен: %s", exc)
            return False
        except Exception as exc:
            logger.error("Telegram ошибка: %s", exc)
            return False

    async def _email(self, subject: str, body: str):
        cfg = self._email_cfg
        try:
            await asyncio.get_event_loop().run_in_executor(
                None, self._send_email_sync, cfg, subject, body
            )
            logger.info("Email отправлен на %s", cfg.to_addr)
        except Exception as exc:
            logger.error("Email ошибка: %s", exc)

    @staticmethod
    def _send_email_sync(cfg: EmailConfig, subject: str, body: str):
        msg = EmailMessage()
        msg["Subject"] = subject
        msg["From"] = cfg.from_addr
        msg["To"] = cfg.to_addr
        msg.set_content(body)

        ctx = ssl.create_default_context()
        with smtplib.SMTP(cfg.smtp_host, cfg.smtp_port) as smtp:
            smtp.ehlo()
            smtp.starttls(context=ctx)
            smtp.login(cfg.username, cfg.password)
            smtp.send_message(msg)
