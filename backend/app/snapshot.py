"""Snapshot en memoria: refreshers de upstreams, degradación y ensamblado del DTO (design D6)."""

import asyncio
import hashlib
import json
import logging
from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime

from app.config import Settings
from app.models import DashboardDTO, Weather, to_payload

log = logging.getLogger("dashboard.snapshot")

MAX_BYTES = 2048
STALE_NULL_AFTER_S = 6 * 3600  # pasado este tiempo la sección se entrega como null
MAX_BACKOFF_S = 1800
REBUILD_EVERY_S = 60


def _dumps(dto: DashboardDTO) -> bytes:
    return json.dumps(to_payload(dto), separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def serialize(dto: DashboardDTO, max_events: int) -> bytes:
    """Serializa a ≤ 2048 B. Recorta: lugares → hourly a 2 → eventos del final. events_total no cambia."""
    events = None if dto.events is None else dto.events[:max_events]
    dto = dto.model_copy(update={"events": events})
    body = _dumps(dto)
    if len(body) <= MAX_BYTES:
        return body
    if events:
        events = [e.model_copy(update={"location": None}) for e in events]
        dto = dto.model_copy(update={"events": events})
        body = _dumps(dto)
    if len(body) > MAX_BYTES and dto.weather and len(dto.weather.hourly) > 2:
        w = dto.weather.model_copy(update={"hourly": dto.weather.hourly[:2]})
        dto = dto.model_copy(update={"weather": w})
        body = _dumps(dto)
    while len(body) > MAX_BYTES and events:
        events = events[:-1]
        dto = dto.model_copy(update={"events": events})
        body = _dumps(dto)
    return body


def make_etag(body: bytes) -> str:
    return 'W/"' + hashlib.sha1(body).hexdigest()[:12] + '"'


@dataclass
class _Feed:
    cal: object | None = None
    at: datetime | None = None
    failed: bool = False


class SnapshotStore:
    def __init__(self, settings: Settings, weather, calendar, clock: Callable[[], datetime] | None = None):
        """`weather` y `calendar` son los adapters (o fakes con la misma interfaz)."""
        self.settings, self.weather_adapter, self.calendar_adapter = settings, weather, calendar
        self._clock = clock or (lambda: datetime.now(settings.zone))
        self.weather: Weather | None = None
        self.weather_at: datetime | None = None
        self.weather_failed = False
        self.feeds = [_Feed() for _ in settings.ics_url_list]
        self._bodies: dict[int, tuple[bytes, str]] = {}
        self._content_key: str | None = None

    # --- lectura -------------------------------------------------------------------------

    def get(self, max_events: int) -> tuple[bytes, str] | None:
        return self._bodies.get(max_events)

    def ages(self, now: datetime | None = None) -> tuple[int | None, int | None]:
        now = now or self._clock()
        w = None if self.weather_at is None else int((now - self.weather_at).total_seconds())
        cal_times = [f.at for f in self.feeds if f.at]
        c = int((now - max(cal_times)).total_seconds()) if cal_times else None
        return w, c

    def degraded(self) -> bool:
        w, c = self.ages()
        return (
            w is None or self.weather_failed
            or (bool(self.feeds) and (c is None or any(f.failed for f in self.feeds)))
        )

    # --- refreshers ----------------------------------------------------------------------

    async def refresh_weather(self) -> bool:
        try:
            self.weather = await self.weather_adapter.fetch()
            self.weather_at, self.weather_failed = self._clock(), False
        except Exception as e:  # noqa: BLE001 - un upstream caído no debe tumbar el refresher
            self.weather_failed = True
            log.warning("refresco de clima falló (%s)", type(e).__name__)
        self.rebuild()
        return not self.weather_failed

    async def refresh_calendar(self) -> bool:
        try:
            results = await self.calendar_adapter.fetch()
        except Exception as e:  # noqa: BLE001 - un upstream caído no debe tumbar el refresher
            log.warning("refresco de calendario falló (%s)", type(e).__name__)
            results = []
        now = self._clock()
        for feed, res in zip(self.feeds, results):
            if res.ok:
                feed.cal, feed.at, feed.failed = res.calendar, now, False
            else:
                feed.failed = True
        if not results:
            for feed in self.feeds:
                feed.failed = True
        self.rebuild()
        return not self.feeds or any(not f.failed for f in self.feeds)

    async def _loop(self, refresh, base_s: int):
        fails = 0
        while True:
            ok = await refresh()
            fails = 0 if ok else fails + 1
            await asyncio.sleep(base_s if ok else min(base_s * 2**fails, MAX_BACKOFF_S))

    async def _rebuild_loop(self):
        while True:
            await asyncio.sleep(REBUILD_EVERY_S)
            self.rebuild()

    async def run_refreshers(self) -> None:
        s = self.settings
        tasks = [
            self._loop(self.refresh_weather, s.weather_refresh_s),
            self._rebuild_loop(),
        ]
        if self.feeds:
            tasks.append(self._loop(self.refresh_calendar, s.calendar_refresh_s))
        await asyncio.gather(*tasks)

    # --- ensamblado ----------------------------------------------------------------------

    def rebuild(self, now: datetime | None = None) -> None:
        """Reensambla el snapshot. No llama a los upstreams; sólo usa lo último bueno."""
        now = now or self._clock()
        have_weather = self.weather is not None or self.weather_failed
        have_calendar = any(f.cal is not None for f in self.feeds)
        if self.weather is None and not have_calendar:
            return  # nunca hubo datos: el endpoint responde 503

        def age(t: datetime | None) -> float:
            return float("inf") if t is None else (now - t).total_seconds()

        warnings: list[str] = []
        weather = self.weather if age(self.weather_at) <= STALE_NULL_AFTER_S else None
        if self.weather_failed and have_weather:
            warnings.append("WEATHER_STALE")

        events = None
        total = 0
        if self.feeds:
            usable = [f.cal for f in self.feeds if f.cal is not None and age(f.at) <= STALE_NULL_AFTER_S]
            failed = [f for f in self.feeds if f.failed]
            if failed:
                warnings.append("CALENDAR_STALE" if len(failed) == len(self.feeds) else "CALENDAR_PARTIAL")
            if usable:
                events = self.calendar_adapter.events_for_day(usable, now.date(), now)
                total = len(events)

        dto = DashboardDTO(
            v=1, source="backend", generated_at=now.isoformat(timespec="seconds"),
            generated_ts=int(now.timestamp()), ttl_s=self.settings.weather_refresh_s,
            tz=self.settings.tz, date=now.date().isoformat(), weekday=now.isoweekday(),
            weather=weather, events=(events or [])[:8] if events is not None else None,
            events_total=total, warnings=warnings,
        )
        # Si el contenido no cambió, se conserva el cuerpo (y el ETag) anterior: sin esto,
        # generated_at cambiaría cada minuto y ningún cliente vería un 304.
        key = hashlib.sha1(json.dumps(
            {k: v for k, v in to_payload(dto).items() if not k.startswith("generated_")},
            sort_keys=True).encode()).hexdigest()
        if key == self._content_key and self._bodies:
            return
        self._content_key = key
        bodies = {}
        for n in range(1, 9):
            body = serialize(dto, n)
            bodies[n] = (body, make_etag(body))
        self._bodies = bodies
