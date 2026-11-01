import os
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlsplit
from cryptography.fernet import Fernet, MultiFernet

def secret(name, default=""):
    file = os.getenv(name + "_FILE")
    return Path(file).read_text().strip() if file else os.getenv(name, default)

@dataclass
class Settings:
    data_dir: Path
    public_url: str
    encryption_keys: str
    bootstrap_token: str = ""
    strava_client_id: str = ""
    strava_client_secret: str = ""
    worker_interval: float = 5
    sync_interval: int = 21600
    session_seconds: int = 900

    smtp_host: str = ""
    smtp_port: int = 587
    smtp_security: str = "starttls"
    smtp_username: str = ""
    smtp_password: str = ""
    smtp_from: str = ""
    ors_api_key: str = ""

    @property
    def smtp_ready(self):
        return bool(self.smtp_host and self.smtp_from)

    @classmethod
    def environment(cls):
        result = cls(Path(os.getenv("VELO_DATA_DIR", "/data")), os.getenv("VELO_PUBLIC_URL", "").rstrip("/"), secret("VELO_ENCRYPTION_KEYS"), secret("VELO_BOOTSTRAP_TOKEN"), os.getenv("STRAVA_CLIENT_ID", ""), secret("STRAVA_CLIENT_SECRET"))
        result.smtp_host = os.getenv('SMTP_HOST', '')
        result.smtp_port = int(os.getenv('SMTP_PORT', '587'))
        result.smtp_security = os.getenv('SMTP_SECURITY', 'starttls')
        result.smtp_username = os.getenv('SMTP_USERNAME', '')
        result.smtp_password = secret('SMTP_PASSWORD')
        result.smtp_from = os.getenv('SMTP_FROM', '')
        result.ors_api_key = secret('ORS_API_KEY')
        result.validate()
        return result

    def validate(self):
        url = urlsplit(self.public_url)
        if url.scheme != "https" or not url.hostname or url.username or url.query or url.fragment or url.path not in ("", "/"):
            raise ValueError("VELO_PUBLIC_URL must be an HTTPS origin without credentials or path")
        if self.smtp_security not in ("starttls", "ssl"):
            raise ValueError("SMTP_SECURITY must be starttls or ssl")
        self.cipher()  # Fail startup rather than silently storing plaintext.
        if self.bootstrap_token and len(self.bootstrap_token) < 32:
            raise ValueError("VELO_BOOTSTRAP_TOKEN must have at least 32 characters")

    def cipher(self):
        return MultiFernet([Fernet(k.strip().encode()) for k in self.encryption_keys.split(",") if k.strip()])

    @property
    def strava_ready(self):
        return bool(self.strava_client_id.isdigit() and self.strava_client_secret)
