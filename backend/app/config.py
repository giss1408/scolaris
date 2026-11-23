import base64
from functools import lru_cache
from typing import Literal

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict
from regisse_kit.db_url import to_asyncpg_url


class Settings(BaseSettings):
    """Everything comes from the environment (`.env.platform` on the platform, `.env` locally)."""

    model_config = SettingsConfigDict(env_file=".env", env_prefix="SCO_", extra="ignore")

    env: Literal["dev", "test", "staging", "prod"] = "dev"
    database_url: str = "postgresql+asyncpg://scolaris:scolaris@localhost:5440/scolaris"
    cors_origins: list[str] = []
    allow_test_numbers: bool | None = None  # +49 numbers outside production only

    # Crypto: base64 of 32 random bytes each. Parents' phone numbers are encrypted at rest (minors' data).
    field_encryption_key: str
    hash_key: str

    # SSO: tokens of the platform `auth` service are verified locally with its JWKS.
    sso_issuer: str = ""
    sso_jwks_url: str = ""
    sso_audience: str = "scolaris"
    # Calls back to auth (enrol / remove staff, live session check) with this product's service key.
    auth_url: str = ""
    service_key: str = ""
    # Re-proof of the password required for sensitive money actions (cancel a payment, grant a discount).
    step_up_seconds: int = 300
    metrics_token: str = ""

    @field_validator("field_encryption_key", "hash_key")
    @classmethod
    def _key32(cls, v: str) -> str:
        """base64 of 32 bytes, or 64 hex characters (what make-product-env.sh generates for `@random`)."""
        v = v.strip()
        if len(v) == 64 and all(c in "0123456789abcdefABCDEF" for c in v):
            return base64.b64encode(bytes.fromhex(v)).decode()
        if len(base64.b64decode(v)) != 32:
            raise ValueError("must be 32 random bytes (base64) or 64 hex characters")
        return v

    @field_validator("database_url")
    @classmethod
    def _asyncpg(cls, v: str) -> str:
        return to_asyncpg_url(v)

    @property
    def test_numbers(self) -> bool:
        return self.allow_test_numbers if self.allow_test_numbers is not None else self.env != "prod"


@lru_cache
def get_settings() -> Settings:
    return Settings()  # type: ignore[call-arg]
