## Context

Con la Fase 2, cualquier proveedor que cumpla la interfaz `DataProvider` y su suite de contrato se conecta sin tocar la vista ni el caché. El reto de esta fase es hacer en el Kindle, con 3.0 s y memoria limitada, lo que el backend hace con librerías completas: Open-Meteo sin problema, pero el ICS puede pesar cientos de KB y no hay un intérprete de RRULE ni una base de zonas horarias disponible.

## Goals / Non-Goals

**Goals:**
- `DirectProvider` que produzca el contrato v1 con un parser iCal propio, por streaming y sin dependencias.
- Fallback automático backend → directo → caché dentro del presupuesto.

**Non-Goals:**
- Expansión de RRULE (ni siquiera la forma WEEKLY básica en v1) y conversión entre zonas horarias arbitrarias (no hay tzdata en Lua).
- Descargas en paralelo (LuaSocket es bloqueante y de un solo hilo).

## Decisions

### D1. `DirectProvider`

```lua
---@class DirectProvider : DataProvider
---@field id "direct"
function DirectProvider.new(cfg, deps) end        -- cfg = config.direct; deps = {http?, json?, clock?}
function DirectProvider:fetchData(onSuccess, onError, opts) end
function DirectProvider:isConfigured() end        -- latitude/longitude presentes
```

Secuencia dentro de `opts.timeout_s`:
1. **Clima (40 % del presupuesto, mínimo 0.8 s):** `GET https://api.open-meteo.com/v1/forecast?latitude=..&longitude=..&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,is_day&hourly=temperature_2m,weather_code,precipitation_probability&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset&timezone=auto&forecast_days=2`. Sink limitado a 16 KB. De la respuesta se toman `utc_offset_seconds` y `timezone` como zona local.
2. **ICS (resto del presupuesto, repartido en partes iguales entre las URLs, en secuencia):** sink en streaming que alimenta a `ICalParser`.
3. **Ensamblado:** mismo orden, ventana y límites que el backend; `source = "direct"`; `generated_ts = os.time()`; `date` y `weekday` calculados con `utc_offset_seconds` (no con `os.date`).

Si el clima falla y no hay `utc_offset_seconds`, se usa el último offset conocido del caché. Si no hay ninguno, el offset del dispositivo, con el aviso `TZ_FROM_DEVICE`.

*Alternativa descartada:* pedir `timezone=<IANA>` fijo en la configuración. Obliga al usuario a configurarlo y no resuelve el cambio de horario (DST) en Lua; `timezone=auto` lo resuelve Open-Meteo.

### D2. `ICalParser`

```lua
---@class ICalParseOpts
---@field day_start_ts integer   -- 00:00 local del día, en epoch UTC
---@field day_end_ts integer     -- day_start_ts + 86400
---@field utc_offset_s integer
---@field max_candidates integer -- 4 × max_events
---@field max_bytes integer      -- 524288

---@return CalendarEvent[] events, string[] warnings
function ICalParser.parseEventsForDay(line_iter, opts) end
function ICalParser.unfold(line_iter) end                      -- iterador de líneas lógicas
function ICalParser.parseDateTime(value, params, utc_offset_s) end  --> ts|nil, all_day
function ICalParser.unescapeText(s) end                        -- \n \, \; \\
function ICalParser.daysFromCivil(y, m, d) end                 -- algoritmo de H. Hinnant
```

Patrones Lua (normativos):

```lua
local CONT      = "^[ \t]"                                   -- línea de continuación
local CONTENT   = "^([%w%-]+)([^:]*):(.*)$"                  -- NAME[;PARAMS]:VALUE
local PARAM     = ";([%w%-]+)=([^;:]*)"
local DT_UTC    = "^(%d%d%d%d)(%d%d)(%d%d)T(%d%d)(%d%d)(%d%d)Z$"
local DT_LOCAL  = "^(%d%d%d%d)(%d%d)(%d%d)T(%d%d)(%d%d)(%d%d)$"
local DATE_ONLY = "^(%d%d%d%d)(%d%d)(%d%d)$"
local DUR       = "^P(%d*)D?T?(%d*)H?(%d*)M?"               -- validación posterior de componentes
```

Reglas:
- Máquina de estados `OUTSIDE → IN_EVENT → OUTSIDE`. Los bloques `VTIMEZONE`, `VALARM` y `VTODO` se saltan.
- Conversión civil → epoch con `daysFromCivil`, **nunca** `os.time{}` (aplicaría la TZ del dispositivo). Para `DT_LOCAL`: `ts = civil − utc_offset_s`.
- Memoria O(eventos candidatos del día); los eventos fuera del día se descartan al cerrar su `VEVENT`.
- CR/LF: se normaliza quitando `\r` al final de cada línea.

### D3. Streaming del ICS

Un sink ltn12 propio acumula bytes hasta `\n`, emite líneas al parser, cuenta bytes y aborta con `"ics_truncated"` al superar `max_bytes`. Así nunca se materializa el archivo entero. *Descartado:* descargar a `table_sink` y luego hacer `gmatch`, porque un feed de 500 KB duplica la memoria en el Kindle.

### D4. Fallback en el orquestador

```
primary ← factory.primary; fallback ← factory.fallback   -- DirectProvider si provider = backend y fallback = direct
res ← primary:fetchData(...)
if res.err and res.err.retryable and fallback and remaining(deadline) − 0.7 ≥ 1.2 then
    res ← fallback:fetchData(..., { timeout_s = remaining − 0.7 })
end
→ render(res.dto or cache or minimal)
```

Errores recuperables: `E_TIMEOUT`, `E_NO_ROUTE` y `E_CONN_REFUSED` (nuevos códigos, separados de `E_TIMEOUT` para distinguir "servidor apagado" (rápido) de "servidor lento" (sin presupuesto)), además de `E_HTTP_STATUS` con 5xx. `E_AUTH`, `E_SCHEMA` y `E_NOT_CONFIGURED` no disparan el fallback.

### D5. `weather_codes.lua`

Port de la tabla WMO de `add-bff-dashboard-mvp/design.md` (D13). Un test de paridad compara la tabla Lua con un fixture JSON exportado desde `backend/app/wmo.py`.

## Risks / Trade-offs

- **[ICS grandes superan el presupuesto]** → Streaming + `max_bytes` + fallback al caché; benchmark en la tarea 4.2 para ajustar el default. Recomendación documentada: usar el modo backend para calendarios grandes.
- **[Sin RRULE, faltan eventos recurrentes]** → Limitación declarada con el aviso `RRULE_IGNORED`, visible en "Ver estado del caché". Se podría evaluar un WEEKLY/DAILY básico en una change futura.
- **[TLS a Open-Meteo y a Google Calendar es obligatorio (HTTPS)]** → El coste del handshake (medido en la tarea 1.4 de la Fase 1) se descuenta del presupuesto. Si supera 1 s por host, el modo directo casi siempre caerá al caché en la suspensión. Mitigación: "Refrescar datos ahora" sin presupuesto y prefetch si se implementó.
- **[URLs ICS secretas en el dispositivo]** → Documentado; nunca se loguean.
