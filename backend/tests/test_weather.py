import json
from pathlib import Path

import httpx
import pytest
import respx

from app.adapters.weather_openmeteo import URL, OpenMeteoAdapter, parse_forecast
from app.config import Settings

FIXTURE = json.loads((Path(__file__).parent / "fixtures" / "openmeteo.json").read_text("utf-8"))


def _data(current_time: str) -> dict:
    d = json.loads(json.dumps(FIXTURE))
    d["current"]["time"] = current_time
    return d


def test_parse_fixture():
    w = parse_forecast(FIXTURE, "Santiago")
    assert w.location == "Santiago"
    assert -60 <= w.temp <= 60 and w.t_min <= w.t_max
    assert w.icon != "unknown"
    assert len(w.hourly) == 4
    assert w.sunrise and w.sunset


def test_slots_are_3_6_9_12_hours_ahead():
    w = parse_forecast(_data("2026-09-29T13:40"), "Santiago")
    assert [h.time for h in w.hourly] == ["16:00", "19:00", "22:00", "01:00"]


def test_slots_cross_midnight():
    w = parse_forecast(_data("2026-09-29T22:15"), "Santiago")
    assert [h.time for h in w.hourly] == ["01:00", "04:00", "07:00", "10:00"]


def test_slot_icons_follow_daylight():
    # franjas 12/15/18/21 h; el atardecer de Santiago es ~19:20
    d = _data("2026-09-29T09:00")
    d["hourly"]["weather_code"] = [0] * len(d["hourly"]["time"])
    w = parse_forecast(d, "Santiago")
    assert [h.time for h in w.hourly] == ["12:00", "15:00", "18:00", "21:00"]
    assert [h.icon for h in w.hourly] == ["clear_day", "clear_day", "clear_day", "clear_night"]


def _settings():
    return Settings(token="t", lat=-33.45, lon=-70.66)


@respx.mock
async def test_fetch_ok():
    route = respx.get(URL).mock(return_value=httpx.Response(200, json=FIXTURE))
    async with httpx.AsyncClient() as c:
        w = await OpenMeteoAdapter(_settings(), c).fetch()
    assert route.call_count == 1 and w.hourly


@respx.mock
async def test_fetch_retries_once_then_succeeds():
    route = respx.get(URL).mock(side_effect=[httpx.Response(500), httpx.Response(200, json=FIXTURE)])
    async with httpx.AsyncClient() as c:
        await OpenMeteoAdapter(_settings(), c).fetch()
    assert route.call_count == 2


@respx.mock
async def test_fetch_fails_after_retry():
    route = respx.get(URL).mock(return_value=httpx.Response(503))
    async with httpx.AsyncClient() as c:
        with pytest.raises(httpx.HTTPStatusError):
            await OpenMeteoAdapter(_settings(), c).fetch()
    assert route.call_count == 2
