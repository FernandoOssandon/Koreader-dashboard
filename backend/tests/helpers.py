import json
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

from icalendar import Calendar

from app.adapters.calendar_ics import FeedResult, IcsCalendarAdapter
from app.adapters.weather_openmeteo import parse_forecast
from app.config import Settings
from app.snapshot import SnapshotStore

TZ = ZoneInfo("America/Santiago")
FIXTURE = json.loads((Path(__file__).parent / "fixtures" / "openmeteo.json").read_text("utf-8"))


def make_cal(body: str, name: str = "Trabajo") -> Calendar:
    head = f"BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//t//EN\r\nX-WR-CALNAME:{name}\r\n"
    return Calendar.from_ical((head + body + "END:VCALENDAR\r\n").replace("\r\n", "\n").replace("\n", "\r\n"))


def vevent(uid: str, start: str, end: str, summary: str, extra: str = "") -> str:
    return (
        f"BEGIN:VEVENT\nUID:{uid}\nDTSTART;TZID=America/Santiago:{start}\n"
        f"DTEND;TZID=America/Santiago:{end}\nSUMMARY:{summary}\n{extra}END:VEVENT\n"
    )


class FakeWeather:
    def __init__(self):
        self.fail, self.calls = False, 0

    async def fetch(self):
        self.calls += 1
        if self.fail:
            raise RuntimeError("upstream caído")
        return parse_forecast(FIXTURE, "Santiago")


class FakeCalendar(IcsCalendarAdapter):
    """Adapter real (para events_for_day) con fetch controlado. `feeds` = lista de Calendar | None."""

    def __init__(self, feeds):
        super().__init__([], TZ, None)
        self.feeds, self.calls = feeds, 0

    async def fetch(self):
        self.calls += 1
        return [FeedResult(i, c) for i, c in enumerate(self.feeds)]


class Clock:
    def __init__(self, dt: datetime):
        self.dt = dt

    def __call__(self):
        return self.dt


def make_store(feeds=None, clock=None, weather=None):
    feeds = feeds if feeds is not None else []
    urls = ",".join(f"https://cal{i}.example/x.ics" for i in range(len(feeds)))
    settings = Settings(token="test-token", ics_urls=urls)
    clock = clock or Clock(datetime(2026, 9, 23, 6, 0, tzinfo=TZ))
    w, c = weather or FakeWeather(), FakeCalendar(feeds)
    return SnapshotStore(settings, w, c, clock), w, c, clock, settings
