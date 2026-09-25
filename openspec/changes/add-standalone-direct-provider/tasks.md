## 1. Clima directo

- [ ] 1.1 Crear `dashboard/weather_codes.lua` (port de la tabla WMO). Verificación: test de paridad busted contra el fixture exportado desde `backend/app/wmo.py`
- [ ] 1.2 Implementar el cliente Open-Meteo con `timezone=auto`, sink de 16 KB y extracción de `utc_offset_seconds`. Verificación: tests busted con un fixture grabado → sección `weather` válida según `dto.validate`

## 2. Parser iCal

- [ ] 2.1 Implementar `unfold`, `unescapeText` y `daysFromCivil`. Verificación: tests busted con líneas plegadas con espacio y con TAB, escapes, y fechas de años bisiestos y de fin de siglo
- [ ] 2.2 Implementar `parseDateTime` para UTC, local/TZID y `VALUE=DATE`, y `DURATION` en forma de horas/minutos o días. Verificación: tests busted de `20260923T170000Z` con offset −3 h → 14:00 y de todo el día
- [ ] 2.3 Implementar `parseEventsForDay` (máquina de estados, bloques ignorados, cancelados, ventana del día, `RRULE_IGNORED`, `TZID_ASSUMED_LOCAL`, `ICS_MALFORMED`). Verificación: tests busted con fixtures reales de Google, iCloud y Nextcloud, más casos inválidos

## 3. DirectProvider

- [ ] 3.1 Implementar el sink de streaming con límite `max_ics_bytes` y el aviso `ICS_TRUNCATED`. Verificación: test busted con un feed de 2 MB sintético que se corta a los 512 KB
- [ ] 3.2 Implementar `DirectProvider` con el reparto del presupuesto (clima 40 %), la degradación parcial y el ensamblado del contrato v1. Verificación: la suite de contrato de la Fase 2 pasa sobre `DirectProvider`, más tests de clima caído y de ICS caído
- [ ] 3.3 Registrar `DirectProvider` en `provider_factory.lua` en lugar de `UnconfiguredProvider`. Verificación: test busted de la fábrica con `provider = direct` configurado y sin coordenadas

## 4. Fallback y rendimiento

- [ ] 4.1 Añadir los códigos `E_CONN_REFUSED` y `E_NO_ROUTE` y la lógica de fallback en `orchestrator.lua` (design D4). Verificación: tests busted: conexión rechazada → directo; timeout con < 1.2 s restantes → caché; 401 → caché sin intentar el directo
- [ ] 4.2 [dispositivo] Medir el tiempo de parseo de ICS de 50, 200 y 500 KB y la memoria pico. Verificación: resultados en `findings/ics_benchmark.md`; si 200 KB tarda más de 1 s, bajar el default de `max_ics_bytes`

## 5. Menú y documentación

- [ ] 5.1 Añadir al menú latitud/longitud, nombre de la ubicación, URLs ICS (`MultiInputDialog`) y el modo de fallback. Verificación: en el emulador, los valores se guardan en `settings.json` y las URLs no aparecen en `crash.log`
- [ ] 5.2 Documentar las limitaciones (RRULE, TZID, tamaño) en el README y en la ayuda del menú. Verificación: revisión del texto frente al spec `standalone-data-source`

## 6. Verificación de aceptación

- [ ] 6.1 [dispositivo] Ejecutar los escenarios de `standalone-data-source` y `provider-fallback` en el Kindle, incluido el uso sin backend en una red ajena. Verificación: resultados en `findings/acceptance.md`
- [ ] 6.2 [dispositivo] Volver a ejecutar los escenarios de las Fases 1 y 2 con `provider = backend` y `fallback = cache`. Verificación: sin regresiones en `findings/regression.md`
- [ ] 6.3 Ejecutar `openspec validate add-standalone-direct-provider --strict` y `busted`. Verificación: todo en verde; la change queda lista para `openspec archive`
