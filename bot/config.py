import os
from dataclasses import dataclass
from dotenv import load_dotenv

load_dotenv()


@dataclass(frozen=True)
class EmailConfig:
    smtp_host: str
    smtp_port: int
    username: str
    password: str
    from_addr: str
    to_addr: str

    @property
    def enabled(self) -> bool:
        return bool(self.smtp_host and self.username and self.to_addr)


@dataclass(frozen=True)
class MtProtoProxy:
    server: str
    port: int
    secret: str


@dataclass(frozen=True)
class Config:
    monitor_mode: str  # "twitch" | "telegram"
    # Twitch API (только для режима twitch)
    twitch_client_id: str
    twitch_client_secret: str
    # Telegram-бот (всегда)
    telegram_bot_token: str
    telegram_chat_id: int
    # Telegram user-аккаунт (только для режима telegram)
    telegram_api_id: int
    telegram_api_hash: str
    telegram_phone: str
    telegram_session_path: str
    # MTProto-прокси для Telethon (опционально)
    telegram_proxy: MtProtoProxy | None
    # Яндекс Алиса
    yandex_token: str
    yandex_device_id: str
    yandex_platform: str
    yandex_device_ip: str  # IP Станции в локальной сети (для Glagol WebSocket)
    # Общие
    db_path: str
    poll_interval: int
    email: EmailConfig


def load_config() -> Config:
    mode = os.getenv("MONITOR_MODE", "twitch").lower()
    if mode not in ("twitch", "telegram"):
        raise RuntimeError(f"MONITOR_MODE должен быть 'twitch' или 'telegram', получено: '{mode}'")

    missing = []
    always_required = ("TELEGRAM_BOT_TOKEN", "TELEGRAM_CHAT_ID", "YANDEX_TOKEN", "YANDEX_DEVICE_ID")
    for key in always_required:
        if not os.getenv(key):
            missing.append(key)

    if mode == "twitch":
        for key in ("TWITCH_CLIENT_ID", "TWITCH_CLIENT_SECRET"):
            if not os.getenv(key):
                missing.append(key)
    else:
        for key in ("TELEGRAM_API_ID", "TELEGRAM_API_HASH", "TELEGRAM_PHONE"):
            if not os.getenv(key):
                missing.append(key)

    if missing:
        raise RuntimeError(f"Отсутствуют обязательные переменные окружения: {', '.join(missing)}")

    db_path = os.getenv("DB_PATH", "data/bot.db")

    proxy_server = os.getenv("TELEGRAM_PROXY_SERVER", "")
    proxy: MtProtoProxy | None = None
    if proxy_server:
        proxy = MtProtoProxy(
            server=proxy_server,
            port=int(os.getenv("TELEGRAM_PROXY_PORT", "443")),
            secret=os.getenv("TELEGRAM_PROXY_SECRET", ""),
        )

    return Config(
        monitor_mode=mode,
        twitch_client_id=os.getenv("TWITCH_CLIENT_ID", ""),
        twitch_client_secret=os.getenv("TWITCH_CLIENT_SECRET", ""),
        telegram_bot_token=os.environ["TELEGRAM_BOT_TOKEN"],
        telegram_chat_id=int(os.environ["TELEGRAM_CHAT_ID"]),
        telegram_api_id=int(os.getenv("TELEGRAM_API_ID", "0")),
        telegram_api_hash=os.getenv("TELEGRAM_API_HASH", ""),
        telegram_phone=os.getenv("TELEGRAM_PHONE", ""),
        telegram_session_path=os.path.join(os.path.dirname(db_path), "telegram_user"),
        telegram_proxy=proxy,
        yandex_token=os.environ["YANDEX_TOKEN"],
        yandex_device_id=os.environ["YANDEX_DEVICE_ID"],
        yandex_platform=os.getenv("YANDEX_PLATFORM", "yandexstation_2"),
        yandex_device_ip=os.getenv("YANDEX_DEVICE_IP", ""),
        db_path=db_path,
        poll_interval=max(30, int(os.getenv("POLL_INTERVAL", "60"))),
        email=EmailConfig(
            smtp_host=os.getenv("EMAIL_SMTP_HOST", ""),
            smtp_port=int(os.getenv("EMAIL_SMTP_PORT", "587")),
            username=os.getenv("EMAIL_USERNAME", ""),
            password=os.getenv("EMAIL_PASSWORD", ""),
            from_addr=os.getenv("EMAIL_FROM", ""),
            to_addr=os.getenv("EMAIL_TO", ""),
        ),
    )
