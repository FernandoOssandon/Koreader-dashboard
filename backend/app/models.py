"""Modelos del DTO v1 (design D13). Fuente de verdad del schema."""

from typing import Annotated, Literal

from pydantic import BaseModel, Field, StringConstraints

HHMM = Annotated[str, StringConstraints(pattern=r"^([01][0-9]|2[0-4]):[0-5][0-9]$")]
Icon = Literal[
    "clear_day", "clear_night", "partly_cloudy_day", "partly_cloudy_night", "cloudy", "fog",
    "drizzle", "rain", "heavy_rain", "snow", "showers", "thunderstorm", "unknown",
]
Temp = Annotated[int, Field(ge=-60, le=60)]
Pct = Annotated[int, Field(ge=0, le=100)]


class HourlySlot(BaseModel):
    time: HHMM
    temp: Temp
    icon: Icon
    pop: Pct | None = None


class Weather(BaseModel):
    location: str = Field(max_length=40)
    temp: Temp
    feels_like: Temp
    t_min: Temp
    t_max: Temp
    code: int = Field(ge=0, le=99)
    icon: Icon
    desc: str = Field(max_length=32)
    pop: Pct
    humidity: Pct | None = None
    wind_kmh: int | None = Field(None, ge=0, le=300)
    sunrise: HHMM | None = None
    sunset: HHMM | None = None
    hourly: list[HourlySlot] = Field(max_length=4)


class CalendarEvent(BaseModel):
    title: str = Field(min_length=1, max_length=60)
    all_day: bool
    start: HHMM | None
    end: HHMM | None
    start_ts: int
    end_ts: int
    location: str | None = Field(None, max_length=40)
    cal: str | None = Field(None, max_length=20)


class DashboardDTO(BaseModel):
    v: Literal[1]
    source: Literal["backend", "direct"]
    generated_at: str
    generated_ts: int = Field(ge=0)
    ttl_s: int = Field(ge=60)
    tz: str = Field(max_length=40)
    date: str = Field(pattern=r"^\d{4}-\d{2}-\d{2}$")
    weekday: int = Field(ge=1, le=7)
    weather: Weather | None
    events: list[CalendarEvent] | None = Field(max_length=8)
    events_total: int = Field(ge=0)
    warnings: list[Annotated[str, Field(max_length=32)]] = Field(max_length=5)


# Claves que se omiten del JSON cuando valen None (ahorra bytes; el schema las marca opcionales).
_OPTIONAL_KEYS = {"pop", "humidity", "wind_kmh", "sunrise", "sunset", "location", "cal"}


def _strip(o):
    if isinstance(o, dict):
        return {k: _strip(v) for k, v in o.items() if not (k in _OPTIONAL_KEYS and v is None)}
    if isinstance(o, list):
        return [_strip(v) for v in o]
    return o


def to_payload(dto: DashboardDTO) -> dict:
    return _strip(dto.model_dump(mode="json"))


def truncate(s: str, max_chars: int) -> str:
    """Colapsa espacios y recorta a max_chars caracteres terminando en '…'."""
    s = " ".join(s.split())
    return s if len(s) <= max_chars else s[: max_chars - 1].rstrip() + "…"
