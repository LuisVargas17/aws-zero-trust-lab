from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Configuration supplied through environment variables, never source code."""

    database_url: str = "sqlite:///./zero_trust.db"
    jwt_secret_key: str = ""  # Must be supplied outside development.
    jwt_issuer: str = "zero-trust-lab"
    jwt_audience: str = "zero-trust-frontend"
    jwt_access_token_minutes: int = 15
    frontend_proxy_ip: str = "10.10.1.10"

    model_config = SettingsConfigDict(env_file=None, case_sensitive=False, extra="ignore")


settings = Settings()

if not settings.jwt_secret_key and __name__ != "__main__":
    # App startup fails closed rather than silently using a known development secret.
    import os

    if os.getenv("ENVIRONMENT", "production").lower() != "test":
        raise RuntimeError("JWT_SECRET_KEY must be set in the environment")
