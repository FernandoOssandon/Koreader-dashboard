import json
import logging
from pathlib import Path

import jsonschema
import pytest
from fastapi.testclient import TestClient
from helpers import make_cal, make_store, vevent

from app.main import JsonFormatter, create_app
from app.models import CalendarEvent, DashboardDTO, HourlySlot, Weather

TOKEN = "test-token"
AUTH = {"Authorization": f"Bearer {TOKEN}"}
SCHEMA = json.loads((Path(__file__).parent / "schema" / "dashboard-v1.json").read_text("utf-8"))


async def _client(events_body: str = "", feeds=True):
    cals = [make_cal(events_body)] if feeds else []
    store, _, _, _, settings = make_store(cals)
    await store.refresh_weather()
    if feeds:
        await store.refresh_calendar()
    return TestClient(create_app(settings, store)), store


async def test_200_headers_and_body():
    body = vevent("a", "20260923T100000", "20260923T110000", "Reunión de diseño")
    c, _ = await _client(body)
    r = c.get("/api/dashboard", headers=AUTH)
    assert r.status_code == 200
    assert r.headers["content-type"] == "application/json; charset=utf-8"
    assert "content-encoding" not in r.headers
    assert r.headers["etag"].startswith('W/"')
    assert "Reunión de diseño".encode() in r.content and b"\\u00f3" not in r.content
    assert b": " not in r.content and b", " not in r.content  # minificado
    assert len(r.content) <= 2048


async def test_304_and_changed_etag():
    c, _ = await _client(vevent("a", "20260923T100000", "20260923T110000", "x"))
    etag = c.get("/api/dashboard", headers=AUTH).headers["etag"]
    r = c.get("/api/dashboard", headers={**AUTH, "If-None-Match": etag})
    assert r.status_code == 304 and r.content == b""
    r = c.get("/api/dashboard", headers={**AUTH, "If-None-Match": 'W/"viejo"'})
    assert r.status_code == 200 and r.headers["etag"] == etag


async def test_401_variants():
    c, _ = await _client()
    for headers in ({}, {"Authorization": "Bearer mal"}, {"Authorization": TOKEN}, {"Authorization": "Basic x"}):
        r = c.get("/api/dashboard", headers=headers)
        assert r.status_code == 401 and r.content == b'{"error":"unauthorized"}'


async def test_503_without_snapshot():
    store, _, _, _, settings = make_store([])
    c = TestClient(create_app(settings, store))
    r = c.get("/api/dashboard", headers=AUTH)
    assert r.status_code == 503 and r.content == b'{"error":"no_snapshot"}'
    assert "retry-after" in r.headers


async def test_max_events():
    body = "".join(vevent(f"e{i}", f"20260923T{10 + i}0000", f"20260923T{10 + i}3000", f"Ev {i}") for i in range(5))
    c, _ = await _client(body)
    out = c.get("/api/dashboard?max_events=3", headers=AUTH).json()
    assert len(out["events"]) == 3 and out["events_total"] == 5
    assert len(c.get("/api/dashboard", headers=AUTH).json()["events"]) == 5
    assert c.get("/api/dashboard?max_events=9", headers=AUTH).status_code == 422


async def test_healthz_without_auth():
    c, _ = await _client()
    r = c.get("/healthz")
    assert r.status_code == 200
    j = r.json()
    assert j["status"] == "ok" and j["weather_age_s"] == 0 and j["calendar_age_s"] == 0
    assert set(j) == {"status", "weather_age_s", "calendar_age_s"}


async def test_healthz_degraded_when_no_data():
    store, _, _, _, settings = make_store([])
    j = TestClient(create_app(settings, store)).get("/healthz").json()
    assert j["status"] == "degraded" and j["weather_age_s"] is None


async def test_logs_are_structured_and_never_contain_the_token(caplog):
    c, _ = await _client()
    with caplog.at_level(logging.INFO):
        c.get("/api/dashboard", headers=AUTH)
        c.get("/api/dashboard", headers={"Authorization": "Bearer otro-secreto"})
    text = "\n".join(JsonFormatter().format(r) for r in caplog.records)
    assert TOKEN not in text and "otro-secreto" not in text
    recs = [json.loads(JsonFormatter().format(r)) for r in caplog.records if r.name == "dashboard.access"]
    assert [r["status"] for r in recs] == [200, 401]
    assert all({"request_id", "latency_ms", "etag_hit"} <= set(r) for r in recs)


# --- 3.7 contrato ---------------------------------------------------------------------------


async def test_real_response_matches_json_schema():
    body = vevent("a", "20260923T100000", "20260923T110000", "Reunión", "LOCATION:Sala 1\n")
    c, _ = await _client(body)
    jsonschema.Draft202012Validator(SCHEMA).validate(c.get("/api/dashboard", headers=AUTH).json())


@pytest.mark.parametrize("name,model", [
    ("HourlySlot", HourlySlot), ("Weather", Weather),
    ("CalendarEvent", CalendarEvent), ("DashboardDTO", DashboardDTO),
])
def test_required_fields_match_pydantic_models(name, model):
    assert set(SCHEMA["$defs"][name]["required"]) == set(model.model_json_schema()["required"])
