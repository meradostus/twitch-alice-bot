import os
from dataclasses import dataclass, field
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
class Config:
    twitch_client_id: str
    twitch_client_secret: str
    telegram_bot_token: str
    telegram_chat_id: int
    yandex_token: str
    yandex_device_id: str
    yandex_platform: str
    db_path: str
    poll_interval: int
    email: EmailConfig


def load_config() -> Config:
    missing = []
    for key in ("TWITCH_CLIENT_ID", "TWITCH_CLIENT_SECRET",
                 "TELEGRAM_BOT_TOKEN", "TELEGRAM_CHAT_ID",
                 "YANDEX_TOKEN", "YANDEX_DEVICE_ID"):
        if not os.getenv(key):
            missing.append(key)
    if missing:
        raise RuntimeError(f"Отсутствуют обязательные переменные окружения: {', '.join(missing)}")

    return Config(
        twitch_client_id=os.environ["TWITCH_CLIENT_ID"],
        twitch_client_secret=os.environ["TWITCH_CLIENT_SECRET"],
        telegram_bot_token=os.environ["TELEGRAM_BOT_TOKEN"],
        telegram_chat_id=int(os.environ["TELEGRAM_CHAT_ID"]),
        yandex_token=os.environ["YANDEX_TOKEN"],
        yandex_device_id=os.environ["YANDEX_DEVICE_ID"],
        yandex_platform=os.getenv("YANDEX_PLATFORM", "yandexstation_2"),
        db_path=os.getenv("DB_PATH", "data/bot.db"),
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
