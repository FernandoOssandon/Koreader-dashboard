import pytest
from pydantic import ValidationError

from app.models import DashboardDTO, truncate
from app.wmo import _TABLE, describe

# Ejemplo normativo de design D13
EXAMPLE = {
    "v": 1, "source": "backend",
    "generated_at": "2026-09-23T13:40:00-03:00", "generated_ts": 1790181600, "ttl_s": 900,
    "tz": "America/Santiago", "date": "2026-09-23", "weekday": 3,
    "weather": {
        "location": "Santiago", "temp": 18, "feels_like": 17, "t_min": 9, "t_max": 22,
        "code": 2, "icon": "partly_cloudy_day", "desc": "Parcialmente nublado",
        "pop": 10, "humidity": 45, "wind_kmh": 12, "sunrise": "07:12", "sunset": "19:31",
        "hourly": [
            {"time": "16:00", "temp": 21, "icon": "clear_day", "pop": 0},
            {"time": "19:00", "temp": 17, "icon": "partly_cloudy_night", "pop": 5},
            {"time": "22:00", "temp": 13, "icon": "clear_night", "pop": 0},
            {"time": "01:00", "temp": 11, "icon": "cloudy", "pop": 20},
        ],
    },
    "events": [
        {"title": "Feriado bancario", "all_day": True, "start": None, "end": None,
         "start_ts": 1790132400, "end_ts": 1790218800, "location": None, "cal": "Feriados"},
        {"title": "Stand-up equipo", "all_day": False, "start": "14:00", "end": "14:15",
         "start_ts": 1790182800, "end_ts": 1790183700, "location": "Meet", "cal": "Trabajo"},
        {"title": "Dentista", "all_day": False, "start": "18:30", "end": "19:30",
         "start_ts": 1790199000, "end_ts": 1790202600, "location": "Av. Providencia 1234",
         "cal": "Personal"},
    ],
    "events_total": 3,
    "warnings": [],
}


def test_example_validates():
    dto = DashboardDTO.model_validate(EXAMPLE)
    assert dto.weather.hourly[3].time == "01:00"
    assert dto.events_total == 3


def test_rejects_bad_hhmm_and_version():
    bad = {**EXAMPLE, "v": 2}
    with pytest.raises(ValidationError):
        DashboardDTO.model_validate(bad)
    bad = {**EXAMPLE, "events": [{**EXAMPLE["events"][1], "start": "25:00"}]}
    with pytest.raises(ValidationError):
        DashboardDTO.model_validate(bad)


EXPECTED_ICONS = {
    0: ("clear_day", "clear_night"), 1: ("clear_day", "clear_night"),
    2: ("partly_cloudy_day", "partly_cloudy_night"), 3: ("cloudy", "cloudy"),
    45: ("fog", "fog"), 48: ("fog", "fog"),
    51: ("drizzle", "drizzle"), 53: ("drizzle", "drizzle"), 55: ("drizzle", "drizzle"),
    56: ("drizzle", "drizzle"), 57: ("drizzle", "drizzle"),
    61: ("rain", "rain"), 63: ("rain", "rain"), 66: ("rain", "rain"),
    65: ("heavy_rain", "heavy_rain"), 67: ("heavy_rain", "heavy_rain"),
    71: ("snow", "snow"), 73: ("snow", "snow"), 75: ("snow", "snow"), 77: ("snow", "snow"),
    85: ("snow", "snow"), 86: ("snow", "snow"),
    80: ("showers", "showers"), 81: ("showers", "showers"), 82: ("showers", "showers"),
    95: ("thunderstorm", "thunderstorm"), 96: ("thunderstorm", "thunderstorm"),
    99: ("thunderstorm", "thunderstorm"),
}


@pytest.mark.parametrize("code,icons", EXPECTED_ICONS.items())
def test_wmo_table(code, icons):
    assert describe(code, True)[0] == icons[0]
    assert describe(code, False)[0] == icons[1]
    assert describe(code, True)[1] != "—"


def test_wmo_covers_all_table_codes_and_unknown():
    assert set(EXPECTED_ICONS) == set(_TABLE)
    assert describe(4, True) == ("unknown", "—")
    assert describe(-1, False) == ("unknown", "—")


def test_truncate():
    assert truncate("  a   b ", 10) == "a b"
    out = truncate("é" * 80, 60)
    assert len(out) == 60 and out.endswith("…")
