"""Tabla WMO → (icono, descripción), compartida con la Fase 3 (design D13)."""

# código → (icono de día, icono de noche, descripción)
_TABLE: dict[int, tuple[str, str, str]] = {}


def _add(codes, day, night, desc):
    for c in codes:
        _TABLE[c] = (day, night, desc)


_add([0], "clear_day", "clear_night", "Despejado")
_add([1], "clear_day", "clear_night", "Mayormente despejado")
_add([2], "partly_cloudy_day", "partly_cloudy_night", "Parcialmente nublado")
_add([3], "cloudy", "cloudy", "Nublado")
_add([45, 48], "fog", "fog", "Niebla")
_add([51, 53, 55, 56, 57], "drizzle", "drizzle", "Llovizna")
_add([61, 63, 66], "rain", "rain", "Lluvia")
_add([65, 67], "heavy_rain", "heavy_rain", "Lluvia intensa")
_add([71, 73, 75, 77, 85, 86], "snow", "snow", "Nieve")
_add([80, 81, 82], "showers", "showers", "Chubascos")
_add([95, 96, 99], "thunderstorm", "thunderstorm", "Tormenta")


def describe(code: int, is_day: bool) -> tuple[str, str]:
    """Devuelve (icono, descripción). Códigos desconocidos → ("unknown", "—")."""
    row = _TABLE.get(code)
    if row is None:
        return "unknown", "—"
    return (row[0] if is_day else row[1]), row[2]
