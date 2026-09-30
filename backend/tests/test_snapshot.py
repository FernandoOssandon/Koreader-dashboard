import json
from datetime import datetime, timedelta

from helpers import TZ, Clock, make_cal, make_store, vevent

from app.models import CalendarEvent, DashboardDTO, HourlySlot, Weather
from app.snapshot import MAX_BYTES, _dumps, serialize


def body_of(store, n=8):
    return json.loads(store.get(n)[0])


async def test_midnight_rebuild_without_calling_upstreams():
    day1 = vevent("a", "20260923T100000", "20260923T110000", "Hoy")
    day2 = vevent("b", "20260924T100000", "20260924T110000", "Mañana")
    clock = Clock(datetime(2026, 9, 23, 23, 59, tzinfo=TZ))
    store, weather, cal, _, _ = make_store([make_cal(day1 + day2)], clock)
    await store.refresh_weather()
    await store.refresh_calendar()
    assert body_of(store)["date"] == "2026-09-23"

    clock.dt = datetime(2026, 9, 24, 0, 1, tzinfo=TZ)
    store.rebuild()
    b = body_of(store)
    assert b["date"] == "2026-09-24"
    assert [e["title"] for e in b["events"]] == ["Mañana"]
    assert weather.calls == 1 and cal.calls == 1  # no se volvió a llamar a los upstreams


async def test_unchanged_content_keeps_etag():
    ev = vevent("a", "20260923T180000", "20260923T190000", "Tarde")
    clock = Clock(datetime(2026, 9, 23, 6, 0, tzinfo=TZ))
    store, *_ = make_store([make_cal(ev)], clock)
    await store.refresh_weather()
    await store.refresh_calendar()
    etag = store.get(8)[1]
    clock.dt += timedelta(minutes=1)
    store.rebuild()
    assert store.get(8)[1] == etag
    clock.dt = datetime(2026, 9, 23, 19, 5, tzinfo=TZ)  # el evento terminó
    store.rebuild()
    assert store.get(8)[1] != etag


async def test_no_snapshot_until_first_data():
    store, *_ = make_store([])
    assert store.get(8) is None
    store.rebuild()
    assert store.get(8) is None


async def test_weather_down_2h_serves_last_good_with_warning():
    clock = Clock(datetime(2026, 9, 23, 6, 0, tzinfo=TZ))
    store, weather, *_ = make_store([], clock)
    await store.refresh_weather()
    weather.fail = True
    clock.dt += timedelta(hours=2)
    await store.refresh_weather()
    b = body_of(store)
    assert b["weather"] is not None and "WEATHER_STALE" in b["warnings"]


async def test_weather_down_7h_is_null():
    clock = Clock(datetime(2026, 9, 23, 6, 0, tzinfo=TZ))
    store, weather, *_ = make_store([make_cal(vevent("a", "20260923T230000", "20260923T235000", "x"))], clock)
    await store.refresh_weather()
    await store.refresh_calendar()
    weather.fail = True
    clock.dt += timedelta(hours=7)
    await store.refresh_weather()
    b = body_of(store)
    assert b["weather"] is None and "WEATHER_STALE" in b["warnings"]


async def test_one_of_two_feeds_down_is_partial():
    ok = make_cal(vevent("a", "20260923T180000", "20260923T190000", "Del feed sano"))
    store, *_ = make_store([ok, None])
    await store.refresh_weather()
    await store.refresh_calendar()
    b = body_of(store)
    assert [e["title"] for e in b["events"]] == ["Del feed sano"]
    assert "CALENDAR_PARTIAL" in b["warnings"] and "CALENDAR_STALE" not in b["warnings"]


async def test_all_feeds_down_keeps_stale_then_nulls_after_6h():
    ev = make_cal(vevent("a", "20260923T180000", "20260923T190000", "Cena"))
    clock = Clock(datetime(2026, 9, 23, 6, 0, tzinfo=TZ))
    store, _, cal, _, _ = make_store([ev], clock)
    await store.refresh_weather()
    await store.refresh_calendar()
    cal.feeds = [None]
    clock.dt += timedelta(hours=2)
    await store.refresh_calendar()
    b = body_of(store)
    assert [e["title"] for e in b["events"]] == ["Cena"] and "CALENDAR_STALE" in b["warnings"]
    clock.dt += timedelta(hours=5)  # 7 h desde el último éxito
    await store.refresh_calendar()
    assert body_of(store)["events"] is None


# --- 3.3 ensamblado y recorte -------------------------------------------------------------


def _dto(n_events: int, title: str, location: str, cal: str = "Trabajo") -> DashboardDTO:
    events = [
        CalendarEvent(title=title, all_day=False, start="14:00", end="15:00", start_ts=1790182800 + i,
                      end_ts=1790186400 + i, location=location, cal=cal)
        for i in range(n_events)
    ]
    weather = Weather(
        location="Santiago", temp=18, feels_like=17, t_min=9, t_max=22, code=2, icon="partly_cloudy_day",
        desc="Parcialmente nublado", pop=10, humidity=45, wind_kmh=12, sunrise="07:12", sunset="19:31",
        hourly=[HourlySlot(time=f"{h}:00", temp=20, icon="clear_day", pop=5) for h in (16, 19, 22, 10)],
    )
    return DashboardDTO(
        v=1, source="backend", generated_at="2026-09-23T13:40:00-03:00", generated_ts=1790181600,
        ttl_s=900, tz="America/Santiago", date="2026-09-23", weekday=3, weather=weather,
        events=events, events_total=n_events + 2, warnings=[],
    )


def test_worst_case_fits_in_2048_bytes():
    dto = _dto(8, "é" * 60, "ñ" * 40)
    body = serialize(dto, 8)
    assert len(body) <= MAX_BYTES
    out = json.loads(body)
    assert out["events_total"] == 10
    assert b"\\u00" not in body  # UTF-8 real, sin escapes
    # orden de recorte: si se perdieron eventos, antes se quitaron lugares y franjas
    if len(out["events"]) < 8:
        assert all("location" not in e for e in out["events"]) and len(out["weather"]["hourly"]) == 2


def test_trim_order_locations_first():
    # sin lugares cabe: se conservan los 8 eventos y las 4 franjas
    dto = _dto(8, "é" * 25, "ñ" * 40, cal="C")
    no_loc = dto.model_copy(update={"events": [e.model_copy(update={"location": None}) for e in dto.events]})
    assert len(_dumps(dto)) > MAX_BYTES >= len(_dumps(no_loc))  # el recorte de lugares basta
    out = json.loads(serialize(dto, 8))
    assert len(out["events"]) == 8 and len(out["weather"]["hourly"]) == 4
    assert all("location" not in e for e in out["events"])


def test_small_payload_untouched():
    dto = _dto(2, "Reunión", "Sala")
    out = json.loads(serialize(dto, 8))
    assert out["events"][0]["location"] == "Sala" and len(out["weather"]["hourly"]) == 4


def test_max_events_slices_but_keeps_total():
    out = json.loads(serialize(_dto(5, "x", "y"), 3))
    assert len(out["events"]) == 3 and out["events_total"] == 7
