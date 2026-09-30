## 1. Spike de integración en el dispositivo (gate técnico, ≤ 1 día)

- [ ] 1.1 [dispositivo] Crear un plugin `spike.koplugin` que loguee `time.now()` en `onSuspend` y en un wrapper temporal de `Screensaver.show`; suspender 10 veces y registrar el orden y si el screensaver nativo pisa lo pintado (Q1). Verificación: tabla de resultados en `findings/spike.md` con la estrategia A o B elegida
- [ ] 1.2 [dispositivo] Desde `onSuspend`, registrar `NetworkMgr:isOnline()` y el resultado de un GET de prueba en 20 suspensiones (Q2). Verificación: tasa de éxito en `findings/spike.md` y decisión sobre el prefetch (umbral: > 20 % de fallos)
- [ ] 1.3 [dispositivo] Medir `setDirty(full) + forceRePaint()` a pantalla completa y probar bloqueos artificiales de 1, 2, 3 y 4 s para ver si el pintado se completa antes de dormir (Q3, Q4). Verificación: tiempos p50/p95 y el margen máximo observado en `findings/spike.md`
- [ ] 1.4 [dispositivo] Medir 10 GET por HTTP y 10 por HTTPS al mismo host (Q5). Verificación: latencias en `findings/spike.md` y default de esquema confirmado; borrar `spike.koplugin`

## 2. Backend: scaffold y adapters

- [x] 2.1 Crear `backend/pyproject.toml` (fastapi, uvicorn[standard], httpx, icalendar, recurring-ical-events, pydantic-settings; dev: pytest, pytest-asyncio, respx, jsonschema, ruff), `app/config.py` con las variables `DASH_*` y `app/main.py` con `/healthz`. Verificación: `uvicorn app.main:app` responde 200 en `/healthz` y el arranque falla con un mensaje claro si falta `DASH_TOKEN`
- [x] 2.2 Crear `app/models.py` con los modelos Pydantic del DTO v1 (design D13). Verificación: un test de pytest valida el ejemplo de D13 contra los modelos
- [x] 2.3 Implementar `app/wmo.py` con la tabla WMO → icono y descripción, según `is_day`. Verificación: test parametrizado que cubre todos los códigos de la tabla y el caso `unknown`
- [x] 2.4 Implementar `OpenMeteoAdapter.fetch()` (slot actual, mínima/máxima, pop diario, sunrise/sunset, 4 franjas a +3/+6/+9/+12 h; timeout de 10 s y un reintento). Verificación: tests con respx y un fixture JSON grabado, incluido el caso de franjas que cruzan la medianoche
- [x] 2.5 Implementar `IcsCalendarAdapter` (descarga en paralelo, expansión con recurring-ical-events en `DASH_TZ`, todo el día, cruce de medianoche con "00:00"/"24:00", cancelados descartados, "(Sin título)", `cal` desde `X-WR-CALNAME`, filtro `end_ts > now` y orden). Verificación: tests con fixtures `.ics` para RRULE semanal + EXDATE, todo el día de varios días, TZID `Europe/Madrid` → "10:00" en Santiago, cruce de medianoche, cancelado y sin DTEND

## 3. Backend: snapshot y endpoint

- [x] 3.1 Implementar `SnapshotStore` con refreshers en el `lifespan` (clima 900 s, ICS 300 s, rebuild por minuto al cambiar el día o terminar un evento), conservando el último dato bueno con su `fetched_at` y backoff exponencial de hasta 30 min. Verificación: test con reloj falso que cruza la medianoche y regenera `date` sin llamar a los upstreams
- [x] 3.2 Implementar la política de degradación (`WEATHER_STALE`, `CALENDAR_STALE`, `CALENDAR_PARTIAL`, sección `null` a las 6 h). Verificación: tests para el clima caído 2 h y 7 h y para uno de dos feeds en 404
- [x] 3.3 Implementar el ensamblado del DTO con truncado por caracteres, `max_events`, serialización minificada UTF-8, recorte por tamaño (lugares → hourly a 2 → eventos) y ETag. Verificación: test del peor caso (8 eventos de 60 caracteres con tildes y lugares de 40) ≤ 2048 bytes con el orden de recorte y `events_total` correctos
- [x] 3.4 Implementar `GET /api/dashboard` con Bearer (`hmac.compare_digest`), `If-None-Match` → 304, 503 + `Retry-After` sin snapshot, `?max_events` y la cabecera `Content-Type` exacta, sin compresión. Verificación: tests de endpoint para 200, 304, 401, 503 y `max_events=3`
- [x] 3.5 Implementar `/healthz` con `status` y la antigüedad de cada upstream, sin autenticación. Verificación: test de endpoint sin cabecera Authorization
- [x] 3.6 Añadir logs JSON estructurados (request_id, status, latency_ms, etag_hit) sin escribir el token ni las URLs ICS. Verificación: test que captura los logs y comprueba que el token no aparece
- [x] 3.7 Copiar el JSON Schema de D13 a `backend/tests/schema/dashboard-v1.json` y añadir un test de contrato sobre la respuesta real. Verificación: `pytest` en verde, incluido el test que compara los campos requeridos con `DashboardDTO.model_json_schema()`
- [x] 3.8 Añadir un test de latencia: 200 requests secuenciales al uvicorn local. Verificación: p95 < 50 ms

## 4. Backend: despliegue

- [x] 4.1 Crear un `Dockerfile` multi-stage (python:3.12-slim, usuario no root, amd64 y arm64), `docker-compose.yml` con `restart: unless-stopped` y healthcheck, y `.env.example`. Verificación: `docker compose up -d` y el healthcheck pasa a `healthy`
- [x] 4.2 Escribir `backend/README.md` (URL ICS secreta de Google/iCloud, IP fija o reserva DHCP, HTTP en LAN frente a VPN). Verificación: revisión del README siguiendo los pasos desde cero
- [ ] 4.3 Desplegar en el servidor doméstico. Verificación: `curl` con token desde otra máquina de la LAN responde en < 300 ms

## 5. Plugin: esqueleto, configuración y contrato

- [ ] 5.1 Crear `_meta.lua` y `main.lua` (WidgetContainer, `is_doc_only = false`) con `onSuspend` y `onResume` envueltos en `pcall`, según la estrategia elegida en 1.1. Verificación: KOReader carga el plugin en el emulador y el log muestra "[dashboard]" al suspender
- [x] 5.2 Implementar `dashboard/config.lua` (defaults, merge profundo, clamp con advertencia, claves desconocidas ignoradas, creación si no existe y no sobrescribir un JSON inválido). Verificación: tests busted para `total_timeout_s = 10 → 2.5`, la clave `foo` y el JSON con coma sobrante
- [x] 5.3 Implementar `dashboard/dto.lua` (`validate`, `sanitize`, `truncateUtf8`). Verificación: tests busted con el ejemplo válido, `v = 2`, `json.null` → `nil`, título de 80 caracteres con emojis, icono "tornado", `temp = 999` y un evento sin `title`

## 6. Plugin: caché y cliente HTTP

- [x] 6.1 Implementar `dashboard/cache_manager.lua` (`load`, `save` atómico con `.tmp` + `os.rename`, `touch`, `freshness`, `clear`). Verificación: tests busted de round-trip, archivo truncado → `nil` y borrado, `validated_at` futuro → `expired`, cambio de día → `expired`, y umbrales `fresh`/`stale`
- [x] 6.2 Implementar `dashboard/backend_client.lua` según D10 (socketutil, `limitFilter(8192)`, ETag, comprobación de `Content-Type`, mapeo de errores, `reset_timeout` siempre). Verificación: tests busted con `http` inyectado para 200, 304, 401, 503, timeout, HTML de portal cautivo, 9 KB de basura y JSON con otro schema; cada caso comprueba que se invoca exactamente un callback y que el token no aparece en los logs

## 7. Plugin: vista

- [x] 7.1 Implementar `dashboard/format_es.lua` (días, meses, `dateTitle`, `ageLabel`, rangos "HH:MM–HH:MM", "Todo el día", "+N más"). Verificación: tests busted
- [x] 7.2 Implementar `dashboard/view_model.lua` (`build`, `readDevice` con `pcall`). Verificación: tests busted con la tabla de verdad live/cache/none × clima nulo/ok × eventos nulo/vacío/n × fresh/stale/expired, contra los textos de pantalla y pie de los specs
- [x] 7.3 Preparar 13 iconos × 2 tamaños (96 y 48 px) en PNG de escala de grises con alpha, con licencia compatible (Meteocons o Weather Icons). Verificación: `icons/` completo y un test que comprueba que existe un PNG por cada valor de `WeatherIcon`
- [ ] 7.4 Implementar `dashboard/dashboard_widget.lua` según D11 (escalado, truncado, "+N más", sin grises de fondo, anti-ghosting `double`). Verificación: capturas en el emulador (Paperwhite y 600×800) de 5 fixtures: sin clima, sin eventos, 8 eventos largos, stale y sin caché, guardadas en `findings/screenshots/`

## 8. Plugin: orquestación y menú

- [x] 8.1 Implementar `dashboard/orchestrator.lua` con el algoritmo de D3 (deadline, `shouldFetch` puro, reserva de 0.7 s, mínimo de 0.5 s, fallback a la pantalla mínima, guardado después del paint, log de tiempos). Verificación: tests busted de `shouldFetch` (tabla de verdad) y de `runSuspend` con cliente y reloj falsos: un cliente que tarda 2.4 s recibe como máximo `restante − 0.7` y una excepción del cliente termina mostrando el caché
- [ ] 8.2 Conectar `onSuspend` y `onResume` en `main.lua` (`dismiss()` cierra y hace `setDirty("all", "full")`; nunca devolver `true`). Verificación: en el emulador, suspender y despertar dejan la página repintada sin restos
- [ ] 8.3 Implementar el menú mínimo (activar, "Vista previa ahora", "Refrescar datos ahora", "Ver estado del caché") y el aviso si la estrategia A requiere desactivar la pantalla de suspensión nativa. Verificación: en el emulador, cada opción funciona y "Refrescar" con el backend apagado muestra el error legible
- [ ] 8.4 Escribir `plugin/README.md` (requisitos previos, instalación, `settings.json` campo por campo, estrategia de pantalla de suspensión, rollback). Verificación: instalación desde cero en el Kindle siguiendo sólo el README

## 9. Verificación de aceptación

- [x] 9.1 Añadir un test busted que analiza los `require(...)` de `dashboard_widget.lua`, `view_model.lua` y `cache_manager.lua` y falla si alguno referencia `backend_client`, `provider_`, `socket`, `ical_parser` o `ui/network`. Verificación: el test pasa y falla al introducir un require prohibido
- [ ] 9.2 [dispositivo] Ejecutar todos los escenarios de `specs/suspend-dashboard`, `specs/dashboard-cache` y `specs/eink-dashboard-view` en el Kindle con `debug.log_timings = true`. Verificación: resultados escenario por escenario en `findings/acceptance.md`
- [ ] 9.3 [dispositivo] Medir los tiempos del handler en 50 suspensiones con el backend en LAN y en 10 con el servidor colgado. Verificación: p95 ≤ 1.0 s en LAN y máximo ≤ 3.0 s con el servidor colgado, registrados en `findings/acceptance.md`
- [ ] 9.4 [dispositivo] Medir la batería durante 3 días con el plugin activado y 3 días con el plugin desactivado, con 20 ciclos de suspensión diarios. Verificación: diferencia < 1 %/día en `findings/acceptance.md`
- [ ] 9.5 Ejecutar `openspec validate add-bff-dashboard-mvp --strict` y todos los tests (`pytest`, `busted`). Verificación: todo en verde; la change queda lista para `openspec archive`
