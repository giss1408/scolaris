import base64
from functools import lru_cache
from typing import Literal

from pydantic import field_validator, model_validator
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

    @model_validator(mode="after")
    def _fail_closed_outside_dev(self) -> "Settings":
        """prod and staging refuse to start on dev defaults or weak secrets (all problems reported at once). The issuer and test-number rules
        are prod only: the local rehearsal stack runs as staging on http://localhost."""
        if self.env not in ("prod", "staging"):
            return self
        bad: list[str] = []
        if "scolaris:scolaris@" in self.database_url or "localhost" in self.database_url:
            bad.append("database_url still has dev defaults")
        for name in ("field_encryption_key", "hash_key"):
            if len(set(base64.b64decode(getattr(self, name)))) < 8:
                bad.append(f"{name} must be 32 random bytes (this one is repetitive)")
        if self.field_encryption_key == self.hash_key:
            bad.append("hash_key must differ from field_encryption_key")
        if len(self.service_key) < 32:
            bad.append("service_key must be at least 32 characters (add-service-key.sh generates one)")
        if self.metrics_token and len(self.metrics_token) < 32:
            bad.append("metrics_token must be at least 32 characters (or empty to disable /metrics)")
        if self.env == "prod":
            if not self.sso_issuer.startswith("https://") or "localhost" in self.sso_issuer:
                bad.append("sso_issuer must be a public https URL")
            if self.allow_test_numbers:
                bad.append("allow_test_numbers must not be on")
        if bad:
            raise ValueError("unsafe " + self.env + " configuration: " + "; ".join(bad))
        return self

    @property
    def test_numbers(self) -> bool:
        return self.allow_test_numbers if self.allow_test_numbers is not None else self.env != "prod"


@lru_cache
def get_settings() -> Settings:
    return Settings()  # type: ignore[call-arg]
