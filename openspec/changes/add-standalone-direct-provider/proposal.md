## Why

El modo backend requiere un servidor personal alcanzable. En viajes, redes ajenas o sin infraestructura propia, el dashboard queda limitado al caché. Un proveedor autónomo que consulte Open-Meteo y un feed iCal directamente desde el Kindle mantiene el dashboard útil sin servidor, y además sirve como respaldo automático cuando el backend falla.

> **Depende de:** `refactor-data-provider-abstraction` archivada.

## What Changes

- Nuevo `DirectProvider`, que obtiene el clima de Open-Meteo (sin autenticación, `timezone=auto`) y los eventos del día de una o más URLs `.ics`, y produce el mismo contrato de datos v1 con `source = "direct"`.
- Parser iCal minimalista en Lua, por streaming, sin dependencias: `SUMMARY`, `DTSTART`, `DTEND`, `DURATION`, `LOCATION` y `STATUS`, con fechas UTC, locales o de día completo. **Limitación explícita:** sin expansión de recurrencias ni conversión de zonas horarias distintas a la local.
- Degradación parcial: clima sin agenda o agenda sin clima.
- Fallback automático configurable (`fallback`: `cache`, `direct` o `none`). Si el backend falla por una causa recuperable y queda presupuesto, se intenta el proveedor directo antes del caché.
- Menú: coordenadas, nombre de la ubicación, URLs ICS y modo de fallback.

## Capabilities

### New Capabilities
- `standalone-data-source`: obtención de clima y agenda directamente desde el dispositivo, con su alcance y sus limitaciones.
- `provider-fallback`: conmutación automática del proveedor principal al directo o al caché ante fallos.

### Modified Capabilities
- `plugin-configuration`: `fallback` y `direct.*` pasan a tener efecto.

## Impact

- **Plugin:** nuevos `dashboard/provider_direct.lua`, `dashboard/ical_parser.lua` y `dashboard/weather_codes.lua`; cambios en `provider_factory.lua`, `orchestrator.lua` y `settings.lua`.
- **Rendimiento:** payloads mayores (Open-Meteo ≈ 5 KB, ICS de 20 a 500 KB). El modo directo cae al caché con más frecuencia que el backend; se documenta como modo secundario.
- **Privacidad:** las URLs ICS privadas se guardan en `settings.json` del dispositivo.
