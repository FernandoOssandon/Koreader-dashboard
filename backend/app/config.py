from zoneinfo import ZoneInfo

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="DASH_", extra="ignore")

    token: str = Field(min_length=1)
    tz: str = "America/Santiago"
    lat: float = -33.45
    lon: float = -70.66
    location_name: str = "Santiago"
    ics_urls: str = ""  # separadas por coma
    weather_refresh_s: int = Field(900, ge=60)
    calendar_refresh_s: int = Field(300, ge=60)
    max_events: int = Field(8, ge=1, le=8)
    port: int = 8080

    @field_validator("tz")
    @classmethod
    def _valid_tz(cls, v: str) -> str:
        try:
            ZoneInfo(v)
        except Exception as e:
            raise ValueError(f"zona horaria IANA desconocida: {v}") from e
        return v

    @property
    def zone(self) -> ZoneInfo:
        return ZoneInfo(self.tz)

    @property
    def ics_url_list(self) -> list[str]:
        return [u.strip() for u in self.ics_urls.split(",") if u.strip()]
