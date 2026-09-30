import asyncio
import logging
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from zoneinfo import ZoneInfo

import httpx
import recurring_ical_events
from icalendar import Calendar

from app.models import CalendarEvent, truncate

log = logging.getLogger("dashboard.calendar")


@dataclass
class FeedResult:
    index: int
    calendar: Calendar | None  # None si la descarga o el parseo fallaron

    @property
    def ok(self) -> bool:
        return self.calendar is not None


class IcsCalendarAdapter:
    def __init__(self, urls: list[str], tz: ZoneInfo, client: httpx.AsyncClient):
        self.urls, self.tz, self.client = urls, tz, client

    async def _fetch_one(self, i: int, url: str) -> FeedResult:
        try:
            r = await self.client.get(url, timeout=10, follow_redirects=True)
            r.raise_for_status()
            cal = await asyncio.to_thread(Calendar.from_ical, r.content)
            return FeedResult(i, cal)
        except Exception as e:  # noqa: BLE001 - un upstream caído no debe tumbar el refresher
            # sólo el tipo: el mensaje de httpx incluye la URL, que es secreta
            log.warning("feed %d falló (%s)", i, type(e).__name__)
            return FeedResult(i, None)

    async def fetch(self) -> list[FeedResult]:
        return list(await asyncio.gather(*(self._fetch_one(i, u) for i, u in enumerate(self.urls))))

    def events_for_day(self, cals: list[Calendar], day: date, now: datetime) -> list[CalendarEvent]:
        tz = self.tz
        day_start = datetime.combine(day, time.min, tzinfo=tz)
        day_end = datetime.combine(day + timedelta(days=1), time.min, tzinfo=tz)
        out: list[CalendarEvent] = []
        for cal in cals:
            cal_name = truncate(str(cal.get("X-WR-CALNAME", "")), 20) or None
            for ev in recurring_ical_events.of(cal).between(day_start, day_end):
                if str(ev.get("STATUS", "")).upper() == "CANCELLED":
                    continue
                item = self._convert(ev, cal_name, day_start, day_end, now)
                if item:
                    out.append(item)
        out.sort(key=lambda e: (not e.all_day, e.start_ts, e.title))
        return out

    def _convert(self, ev, cal_name, day_start, day_end, now) -> CalendarEvent | None:
        tz = self.tz
        start, end = ev.start, ev.end
        all_day = not isinstance(start, datetime)
        if all_day:  # DTEND de un evento de todo el día es exclusivo
            s = datetime.combine(start, time.min, tzinfo=tz)
            e = datetime.combine(end, time.min, tzinfo=tz)
        else:  # los flotantes (sin zona) se interpretan en la zona configurada
            s = start.astimezone(tz) if start.tzinfo else start.replace(tzinfo=tz)
            e = end.astimezone(tz) if end.tzinfo else end.replace(tzinfo=tz)
        if not (s < day_end and e > day_start) or e <= now:
            return None

        title = truncate(str(ev.get("SUMMARY", "")), 60) or "(Sin título)"
        location = truncate(str(ev.get("LOCATION", "")), 40) or None
        return CalendarEvent(
            title=title, all_day=all_day,
            start=None if all_day else ("00:00" if s < day_start else s.strftime("%H:%M")),
            end=None if all_day else ("24:00" if e >= day_end else e.strftime("%H:%M")),
            start_ts=int(s.timestamp()), end_ts=int(e.timestamp()),
            location=location, cal=cal_name,
        )
