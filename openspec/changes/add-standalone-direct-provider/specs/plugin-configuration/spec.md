## MODIFIED Requirements

### Requirement: Archivo de configuración con valores por defecto
El plugin SHALL leer su configuración de `settings.json` en el directorio de ajustes de KOReader y, si el archivo no existe, SHALL crearlo con los valores por defecto. Los campos efectivos son: `enabled` (true), `provider` (`backend`), `fallback` (`cache`), `backend.url` (vacía), `backend.token` (vacío), `backend.connect_timeout_s` (1.0), `backend.total_timeout_s` (2.2), `direct.latitude` y `direct.longitude` (sin valor), `direct.location_name` (vacío), `direct.ics_urls` (lista vacía), `direct.total_timeout_s` (2.2), `direct.max_ics_bytes` (524288), `cache.min_refresh_interval_s` (600), `cache.stale_after_s` (10800), `cache.max_age_s` (86400), `display.max_events` (8), `display.show_hourly` (true), `display.show_location` (true), `display.anti_ghosting` (`full`) y `debug.log_timings` (false). Los cambios hechos desde el menú SHALL guardarse de forma atómica, conservando las claves que el menú no gestiona. Las URLs ICS MUST NOT escribirse en los logs.

#### Scenario: Primer arranque
- **WHEN** KOReader carga el plugin y no existe `settings.json`
- **THEN** se crea el archivo con los valores por defecto

#### Scenario: Guardado desde el menú conserva claves
- **WHEN** `settings.json` contiene `debug.log_timings: true` y el usuario cambia la URL desde el menú
- **THEN** el archivo guardado tiene la nueva URL y conserva `debug.log_timings: true`

#### Scenario: Modo directo sin coordenadas
- **WHEN** `provider` es `direct` y faltan `direct.latitude` o `direct.longitude`
- **THEN** no se hace ninguna petición y el pie indica "Proveedor no configurado"
