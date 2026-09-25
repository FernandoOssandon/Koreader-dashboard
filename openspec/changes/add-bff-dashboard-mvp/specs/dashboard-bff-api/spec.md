## Purpose

Servicio HTTP que consolida el clima y la agenda del día en un único snapshot compacto, para que el lector E-Ink lo obtenga con una sola petición rápida y barata en batería.

## ADDED Requirements

### Requirement: Endpoint de snapshot consolidado
El backend SHALL exponer `GET /api/dashboard`, que responde `200` con un cuerpo JSON conforme al contrato de datos del dashboard v1, `Content-Type: application/json; charset=utf-8` y una cabecera `ETag`. El cuerpo MUST estar minificado, codificado en UTF-8 sin escapes `\uXXXX` para caracteres no ASCII, y MUST NOT llevar `Content-Encoding`.

#### Scenario: Respuesta válida
- **WHEN** un cliente autenticado hace `GET /api/dashboard`
- **THEN** recibe `200` con un cuerpo que valida contra el JSON Schema del dashboard v1
- **AND** la respuesta incluye `ETag` y no incluye `Content-Encoding`

#### Scenario: Caracteres no ASCII
- **WHEN** un evento se titula "Reunión de diseño"
- **THEN** el cuerpo contiene los bytes UTF-8 de "ó" y no la secuencia `ó`

### Requirement: Tamaño máximo del cuerpo
El cuerpo serializado de `GET /api/dashboard` MUST pesar como máximo 2048 bytes. Si el snapshot lo excede, el backend SHALL recortarlo en este orden hasta que quepa: primero quita el lugar de cada evento, luego reduce el pronóstico horario a 2 franjas y después elimina eventos del final de uno en uno, conservando el total real de eventos del día.

#### Scenario: Peor caso de contenido
- **WHEN** hay 8 eventos con títulos de 60 caracteres con tildes y lugares de 40 caracteres
- **THEN** el cuerpo pesa 2048 bytes o menos
- **AND** `events_total` sigue reflejando la cantidad real de eventos pendientes del día

### Requirement: Latencia desde memoria
El backend SHALL responder `GET /api/dashboard` a partir de un snapshot precalculado en memoria, sin consultar a los upstreams durante la petición. La latencia p95 MUST ser menor a 50 ms medida en el servidor y menor a 300 ms medida desde un cliente en la misma LAN.

#### Scenario: Ráfaga secuencial
- **WHEN** un cliente hace 200 peticiones secuenciales a `GET /api/dashboard`
- **THEN** el p95 de latencia medido en el servidor es menor a 50 ms

#### Scenario: Upstream lento no afecta la latencia
- **WHEN** el servicio de clima tarda 10 s en responder durante un refresco en segundo plano
- **THEN** las peticiones a `GET /api/dashboard` siguen respondiendo en menos de 50 ms con el snapshot anterior

### Requirement: Autenticación por token
El backend SHALL exigir `Authorization: Bearer <token>` en `GET /api/dashboard` y MUST responder `401` con `{"error":"unauthorized"}` si el token falta o no coincide. `GET /healthz` MUST NOT requerir autenticación ni exponer datos de clima o agenda.

#### Scenario: Token inválido
- **WHEN** un cliente hace `GET /api/dashboard` con un token incorrecto
- **THEN** recibe `401` con `{"error":"unauthorized"}`

#### Scenario: Health sin token
- **WHEN** un cliente hace `GET /healthz` sin cabecera de autorización
- **THEN** recibe `200` con `status` y la antigüedad en segundos de cada upstream

### Requirement: Petición condicional por ETag
El backend SHALL responder `304` sin cuerpo cuando la cabecera `If-None-Match` coincide con el ETag del snapshot actual.

#### Scenario: Sin cambios
- **WHEN** un cliente envía `If-None-Match` con el ETag recibido en la respuesta anterior y el snapshot no cambió
- **THEN** recibe `304` sin cuerpo

#### Scenario: Con cambios
- **WHEN** un cliente envía un ETag antiguo y el snapshot cambió
- **THEN** recibe `200` con el cuerpo nuevo y un ETag distinto

### Requirement: Límite de eventos solicitado
El backend SHALL aceptar el parámetro opcional `max_events` (entero de 1 a 8, por defecto 8) y MUST devolver como máximo esa cantidad de eventos, manteniendo `events_total` sin recortar.

#### Scenario: Cliente pide 3 eventos
- **WHEN** hay 5 eventos pendientes hoy y el cliente hace `GET /api/dashboard?max_events=3`
- **THEN** `events` contiene 3 elementos y `events_total` es 5

### Requirement: Servicio sin datos iniciales
Si el backend aún no pudo construir ningún snapshot, SHALL responder `503` con `{"error":"no_snapshot"}` y la cabecera `Retry-After`.

#### Scenario: Arranque con upstreams caídos
- **WHEN** el backend arranca y ni el clima ni el calendario han respondido nunca
- **THEN** `GET /api/dashboard` responde `503` con `Retry-After`

### Requirement: Normalización de la agenda a la zona horaria configurada
El backend SHALL calcular "hoy" y todas las horas locales de la agenda y del pronóstico en la zona horaria IANA configurada, expandiendo eventos recurrentes (incluidas excepciones y exclusiones) y convirtiendo eventos definidos en otras zonas horarias. MUST incluir sólo los eventos no cancelados que intersectan el día actual y aún no han terminado, ordenados primero los de todo el día y después por hora de inicio.

#### Scenario: Evento recurrente en otra zona horaria
- **WHEN** la zona configurada es `America/Santiago` y existe un evento semanal creado en `Europe/Madrid` a las 15:00 que ocurre hoy, 23 de septiembre de 2026
- **THEN** el evento aparece con `start` igual a "10:00"

#### Scenario: Evento terminado
- **WHEN** un evento de hoy terminó antes de la generación del snapshot
- **THEN** no aparece en `events`

#### Scenario: Evento cancelado
- **WHEN** un evento de hoy tiene estado cancelado en el feed iCal
- **THEN** no aparece en `events`

#### Scenario: Evento que cruza la medianoche
- **WHEN** un evento empezó ayer a las 22:00 y termina hoy a las 02:00
- **THEN** aparece con `start` "00:00" y `end` "02:00"

### Requirement: Cambio de día sin depender de los upstreams
El backend SHALL recalcular el snapshot al cambiar el día en la zona horaria configurada, aunque ningún upstream se haya refrescado.

#### Scenario: Medianoche
- **WHEN** pasan las 00:00 en la zona configurada sin refrescos de upstream
- **THEN** en menos de 60 s, `date` corresponde al nuevo día y `events` sólo contiene eventos de ese día

### Requirement: Degradación ante fallos de upstream
Si un upstream falla, el backend SHALL seguir sirviendo su último dato válido y añadir a `warnings` `WEATHER_STALE` o `CALENDAR_STALE` según corresponda. Si ese dato tiene más de 6 horas, la sección correspondiente (`weather` o `events`) MUST ser `null`. Si falla sólo uno de varios feeds iCal, SHALL usar los demás y añadir `CALENDAR_PARTIAL`.

#### Scenario: Servicio de clima caído
- **WHEN** el último clima válido tiene 2 horas y el servicio de clima responde con error
- **THEN** `weather` contiene el último dato válido y `warnings` incluye `WEATHER_STALE`

#### Scenario: Clima caído por más de 6 horas
- **WHEN** el último clima válido tiene 7 horas
- **THEN** `weather` es `null`

#### Scenario: Uno de dos calendarios caído
- **WHEN** hay dos feeds iCal configurados y uno responde 404
- **THEN** `events` contiene los eventos del feed disponible y `warnings` incluye `CALENDAR_PARTIAL`
