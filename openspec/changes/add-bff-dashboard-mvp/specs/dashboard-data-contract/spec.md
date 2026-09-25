## Purpose

Contrato canónico de los datos del dashboard, idéntico sin importar qué fuente los produzca, para que la vista, el caché y el ciclo de suspensión sean independientes del origen de los datos.

## ADDED Requirements

### Requirement: Estructura canónica v1
Toda fuente de datos del dashboard SHALL producir un objeto con los siguientes campos obligatorios: `v` (=1), `source` (`backend` o `direct`), `generated_at` (ISO-8601 con offset), `generated_ts` (epoch en segundos), `ttl_s` (≥ 60), `tz` (zona IANA), `date` (`YYYY-MM-DD`, "hoy" en `tz`), `weekday` (1–7, ISO, 1 = lunes), `weather` (objeto o `null`), `events` (arreglo o `null`), `events_total` (≥ 0) y `warnings` (arreglo de hasta 5 códigos). El JSON Schema normativo está en el `design.md` de esta change.

#### Scenario: Ejemplo completo válido
- **WHEN** una fuente entrega un objeto con todos los campos obligatorios en sus rangos
- **THEN** el cliente lo acepta y lo muestra

#### Scenario: Versión futura
- **WHEN** el cliente recibe un objeto con `v` igual a 2
- **THEN** lo rechaza como incompatible y conserva los datos anteriores

### Requirement: Sección de clima
Cuando `weather` no es `null`, SHALL contener `location` (≤ 40 caracteres), `temp`, `feels_like`, `t_min` y `t_max` (enteros en °C entre −60 y 60), `code` (código WMO), `icon` (uno de `clear_day`, `clear_night`, `partly_cloudy_day`, `partly_cloudy_night`, `cloudy`, `fog`, `drizzle`, `rain`, `heavy_rain`, `snow`, `showers`, `thunderstorm`, `unknown`), `desc` (≤ 32 caracteres, en español), `pop` (0–100) y `hourly` (hasta 4 franjas con `time` `HH:MM`, `temp` e `icon`). Los campos `humidity`, `wind_kmh`, `sunrise` y `sunset` son opcionales. Un `weather` igual a `null` MUST significar "clima no disponible".

#### Scenario: Clima no disponible
- **WHEN** `weather` es `null`
- **THEN** la pantalla muestra "Clima no disponible" en lugar de la sección de clima

### Requirement: Sección de agenda
Cuando `events` no es `null`, SHALL ser un arreglo de hasta 8 eventos con `title` (1–60 caracteres), `all_day` (booleano), `start` y `end` (`HH:MM` o `null`; ambos `null` si `all_day`), `start_ts`, `end_ts` y, opcionalmente, `location` (≤ 40) y `cal` (≤ 20). Un `events` igual a `null` MUST significar "agenda no disponible" y un arreglo vacío MUST significar "no hay eventos hoy". Si `events_total` supera la cantidad de elementos de `events`, la diferencia son eventos omitidos.

#### Scenario: Agenda no disponible
- **WHEN** `events` es `null`
- **THEN** la pantalla muestra "Agenda no disponible"

#### Scenario: Agenda vacía
- **WHEN** `events` es un arreglo vacío
- **THEN** la pantalla muestra "Sin eventos hoy"

#### Scenario: Eventos omitidos
- **WHEN** `events` contiene 8 elementos y `events_total` es 10
- **THEN** la pantalla indica "+2 más"

### Requirement: Validación mínima y normalización en el cliente
Antes de usar o guardar datos recibidos, el cliente SHALL rechazarlos si no son un objeto, si `v` no es 1, si `date` o `weekday` son inválidos, si `generated_ts` no es numérico, si `weather` no es `null` y le faltan temperaturas, icono o descripción, o si algún evento carece de `title` o `all_day`. Los datos aceptados MUST normalizarse sin fallar nunca: se truncan los textos a sus máximos por caracteres (sin cortar secuencias UTF-8), se ajustan los números a sus rangos, se recortan los arreglos a sus máximos, los iconos desconocidos pasan a `unknown` y los valores JSON `null` se tratan como ausentes.

#### Scenario: Temperatura fuera de rango
- **WHEN** el cliente recibe `temp` igual a 999
- **THEN** la muestra como 60

#### Scenario: Título largo con caracteres multibyte
- **WHEN** un evento tiene un título de 80 caracteres con tildes y emojis
- **THEN** se muestra truncado a 60 caracteres terminados en "…" y sin caracteres corruptos

#### Scenario: Icono desconocido
- **WHEN** el cliente recibe `icon` igual a "tornado"
- **THEN** muestra el icono genérico

#### Scenario: Evento sin título
- **WHEN** un evento de la respuesta no tiene el campo `title`
- **THEN** la respuesta completa se rechaza y se conservan los datos anteriores

### Requirement: Datos del dispositivo fuera del contrato
El contrato de datos MUST NOT incluir información del dispositivo. La batería, el estado de carga y la frescura de los datos SHALL obtenerse localmente en el dispositivo en el momento de pintar.

#### Scenario: Batería actual con datos en caché
- **WHEN** se pinta el dashboard con datos en caché de hace 3 horas y la batería está al 64 %
- **THEN** la pantalla muestra "Batería 64%"
