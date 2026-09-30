import logging
from datetime import datetime, timedelta

import httpx

from app.config import Settings
from app.models import HourlySlot, Weather, truncate
from app.wmo import describe

log = logging.getLogger("dashboard.weather")

URL = "https://api.open-meteo.com/v1/forecast"
SLOT_OFFSETS_H = (3, 6, 9, 12)


def _clamp(v, lo, hi) -> int:
    return max(lo, min(hi, round(v)))


def _hhmm(iso: str) -> str:
    return iso[11:16]


def parse_forecast(data: dict, location: str) -> Weather:
    """Convierte la respuesta de Open-Meteo (horas ya en la zona configurada) en el modelo Weather."""
    cur, hourly, daily = data["current"], data["hourly"], data["daily"]
    sun = {d: (rise, sset) for d, rise, sset in zip(daily["time"], daily["sunrise"], daily["sunset"])}

    def is_day_at(dt: datetime) -> bool:
        rise, sset = sun.get(dt.strftime("%Y-%m-%d"), (None, None))
        if not rise or not sset:
            return 6 <= dt.hour < 20
        return datetime.fromisoformat(rise) <= dt < datetime.fromisoformat(sset)

    icon, desc = describe(int(cur["weather_code"]), bool(cur.get("is_day", 1)))
    now_h = datetime.fromisoformat(cur["time"]).replace(minute=0, second=0, microsecond=0)
    idx = {t: i for i, t in enumerate(hourly["time"])}
    pops = hourly.get("precipitation_probability") or []
    slots = []
    for k in SLOT_OFFSETS_H:
        t = now_h + timedelta(hours=k)
        i = idx.get(t.strftime("%Y-%m-%dT%H:00"))
        if i is None or hourly["temperature_2m"][i] is None:
            continue
        s_icon, _ = describe(int(hourly["weather_code"][i]), is_day_at(t))
        pop = pops[i] if i < len(pops) else None
        slots.append(HourlySlot(
            time=t.strftime("%H:%M"), temp=_clamp(hourly["temperature_2m"][i], -60, 60),
            icon=s_icon, pop=None if pop is None else _clamp(pop, 0, 100),
        ))

    rise, sset = sun.get(daily["time"][0], (None, None))
    pop_max = daily["precipitation_probability_max"][0]
    wind = cur.get("wind_speed_10m")
    hum = cur.get("relative_humidity_2m")
    return Weather(
        location=truncate(location, 40),
        temp=_clamp(cur["temperature_2m"], -60, 60),
        feels_like=_clamp(cur["apparent_temperature"], -60, 60),
        t_min=_clamp(daily["temperature_2m_min"][0], -60, 60),
        t_max=_clamp(daily["temperature_2m_max"][0], -60, 60),
        code=int(cur["weather_code"]), icon=icon, desc=desc,
        pop=0 if pop_max is None else _clamp(pop_max, 0, 100),
        humidity=None if hum is None else _clamp(hum, 0, 100),
        wind_kmh=None if wind is None else _clamp(wind, 0, 300),
        sunrise=_hhmm(rise) if rise else None, sunset=_hhmm(sset) if sset else None,
        hourly=slots,
    )


class OpenMeteoAdapter:
    def __init__(self, settings: Settings, client: httpx.AsyncClient):
        self.settings, self.client = settings, client

    async def fetch(self) -> Weather:
        s = self.settings
        params = {
            "latitude": s.lat, "longitude": s.lon, "timezone": s.tz, "forecast_days": 2,
            "current": "temperature_2m,apparent_temperature,relative_humidity_2m,"
                       "weather_code,wind_speed_10m,is_day",
            "hourly": "temperature_2m,weather_code,precipitation_probability",
            "daily": "temperature_2m_max,temperature_2m_min,precipitation_probability_max,"
                     "sunrise,sunset",
        }
        for attempt in (1, 2):  # un reintento
            try:
                r = await self.client.get(URL, params=params, timeout=10)
                r.raise_for_status()
                return parse_forecast(r.json(), s.location_name)
            except (httpx.HTTPError, ValueError, KeyError) as e:
                if attempt == 2:
                    raise
                log.warning("open-meteo falló (%s), reintentando", type(e).__name__)
