from datetime import date, datetime
from zoneinfo import ZoneInfo

import httpx
import respx
from icalendar import Calendar

from app.adapters.calendar_ics import IcsCalendarAdapter

TZ = ZoneInfo("America/Santiago")
DAY = date(2026, 9, 23)  # miércoles
MORNING = datetime(2026, 9, 23, 6, 0, tzinfo=TZ)


def cal(body: str, name: str | None = "Trabajo") -> Calendar:
    head = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//test//EN\r\n"
    if name:
        head += f"X-WR-CALNAME:{name}\r\n"
    return Calendar.from_ical((head + body + "END:VCALENDAR\r\n").replace("\n", "\r\n").replace("\r\r", "\r"))


def events(body, now=MORNING, name="Trabajo"):
    return IcsCalendarAdapter([], TZ, None).events_for_day([cal(body, name)], DAY, now)


def test_weekly_rrule_with_exdate():
    body = """BEGIN:VEVENT
UID:a
DTSTART;TZID=America/Santiago:20260909T140000
DTEND;TZID=America/Santiago:20260909T141500
RRULE:FREQ=WEEKLY
EXDATE;TZID=America/Santiago:20260930T140000
SUMMARY:Stand-up
END:VEVENT
"""
    got = events(body)
    assert [(e.title, e.start, e.end) for e in got] == [("Stand-up", "14:00", "14:15")]
    # la semana siguiente está excluida por EXDATE
    other = IcsCalendarAdapter([], TZ, None).events_for_day(
        [cal(body)], date(2026, 9, 30), datetime(2026, 9, 30, 6, tzinfo=TZ))
    assert other == []


def test_all_day_multi_day():
    body = """BEGIN:VEVENT
UID:b
DTSTART;VALUE=DATE:20260922
DTEND;VALUE=DATE:20260925
SUMMARY:Congreso
END:VEVENT
"""
    (e,) = events(body)
    assert e.all_day and e.start is None and e.end is None
    # el mismo evento no aparece el 25 (DTEND exclusivo)
    assert IcsCalendarAdapter([], TZ, None).events_for_day(
        [cal(body)], date(2026, 9, 25), datetime(2026, 9, 25, 6, tzinfo=TZ)) == []


def test_other_timezone_converted_to_configured_tz():
    # 15:00 en Madrid (CEST, UTC+2) = 13:00 UTC = 10:00 en Santiago (UTC-3)
    body = """BEGIN:VEVENT
UID:c
DTSTART;TZID=Europe/Madrid:20260909T150000
DTEND;TZID=Europe/Madrid:20260909T160000
RRULE:FREQ=WEEKLY
SUMMARY:Sync
END:VEVENT
"""
    (e,) = events(body)
    assert e.start == "10:00" and e.end == "11:00"


def test_midnight_crossing():
    body = """BEGIN:VEVENT
UID:d
DTSTART;TZID=America/Santiago:20260922T220000
DTEND;TZID=America/Santiago:20260923T020000
SUMMARY:Guardia
END:VEVENT
"""
    (e,) = events(body, now=datetime(2026, 9, 23, 0, 30, tzinfo=TZ))
    assert (e.start, e.end) == ("00:00", "02:00")
    body2 = body.replace("20260922T220000", "20260923T220000").replace("20260923T020000", "20260924T020000")
    (e2,) = events(body2)
    assert (e2.start, e2.end) == ("22:00", "24:00")


def test_cancelled_and_finished_are_dropped():
    body = """BEGIN:VEVENT
UID:e
DTSTART;TZID=America/Santiago:20260923T100000
DTEND;TZID=America/Santiago:20260923T110000
STATUS:CANCELLED
SUMMARY:Cancelado
END:VEVENT
BEGIN:VEVENT
UID:f
DTSTART;TZID=America/Santiago:20260923T080000
DTEND;TZID=America/Santiago:20260923T090000
SUMMARY:Terminado
END:VEVENT
BEGIN:VEVENT
UID:g
DTSTART;TZID=America/Santiago:20260923T180000
DTEND;TZID=America/Santiago:20260923T190000
SUMMARY:Pendiente
END:VEVENT
"""
    got = events(body, now=datetime(2026, 9, 23, 12, 0, tzinfo=TZ))
    assert [e.title for e in got] == ["Pendiente"]


def test_no_dtend_no_title_calname_and_ordering():
    body = """BEGIN:VEVENT
UID:h
DTSTART;TZID=America/Santiago:20260923T150000
LOCATION:Sala 1
END:VEVENT
BEGIN:VEVENT
UID:i
DTSTART;TZID=America/Santiago:20260923T090000
DTEND;TZID=America/Santiago:20260923T100000
SUMMARY:Temprano
END:VEVENT
BEGIN:VEVENT
UID:j
DTSTART;VALUE=DATE:20260923
SUMMARY:Feriado
END:VEVENT
"""
    got = events(body)
    assert [e.title for e in got] == ["Feriado", "Temprano", "(Sin título)"]
    sin_dtend = got[2]
    assert sin_dtend.start == "15:00" and sin_dtend.end == "15:00"
    assert sin_dtend.location == "Sala 1" and sin_dtend.cal == "Trabajo"


def test_titles_truncated_and_normalized():
    body = f"""BEGIN:VEVENT
UID:k
DTSTART;TZID=America/Santiago:20260923T150000
DTEND;TZID=America/Santiago:20260923T160000
SUMMARY:{"é" * 80}
END:VEVENT
"""
    (e,) = events(body)
    assert len(e.title) == 60 and e.title.endswith("…")


@respx.mock
async def test_fetch_parallel_with_partial_failure():
    ics = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:x\r\nEND:VCALENDAR\r\n"
    respx.get("https://a.example/cal.ics").mock(return_value=httpx.Response(200, text=ics))
    respx.get("https://b.example/cal.ics").mock(return_value=httpx.Response(404))
    async with httpx.AsyncClient() as c:
        res = await IcsCalendarAdapter(
            ["https://a.example/cal.ics", "https://b.example/cal.ics"], TZ, c).fetch()
    assert [r.ok for r in res] == [True, False]
