## Purpose

Permitir configurar el plugin mediante un archivo `settings.json` legible y editable a mano, con valores por defecto seguros y protección ante errores de edición.

## ADDED Requirements

### Requirement: Archivo de configuración con valores por defecto
El plugin SHALL leer su configuración de `settings.json` en el directorio de ajustes de KOReader y, si el archivo no existe, SHALL crearlo con los valores por defecto. En esta fase los campos efectivos son: `enabled` (true), `backend.url` (vacía), `backend.token` (vacío), `backend.connect_timeout_s` (1.0), `backend.total_timeout_s` (2.2), `cache.min_refresh_interval_s` (600), `cache.stale_after_s` (10800), `cache.max_age_s` (86400), `display.max_events` (8), `display.show_hourly` (true), `display.show_location` (true), `display.anti_ghosting` (`full`) y `debug.log_timings` (false). Los campos `provider`, `fallback` y `direct.*` se aceptan y conservan, pero no tienen efecto hasta fases posteriores.

#### Scenario: Primer arranque
- **WHEN** KOReader carga el plugin y no existe `settings.json`
- **THEN** se crea el archivo con los valores por defecto

### Requirement: Validación de rangos
El plugin SHALL ajustar al rango permitido los valores fuera de él y registrar una advertencia: `backend.connect_timeout_s` de 0.3 a 1.5, `backend.total_timeout_s` de 0.5 a 2.5, `cache.min_refresh_interval_s` de 0 a 86400 y `display.max_events` de 1 a 8. Las claves desconocidas MUST ignorarse sin error.

#### Scenario: Timeout excesivo
- **WHEN** `backend.total_timeout_s` es 10 en el archivo
- **THEN** el plugin usa 2.5 y registra una advertencia

#### Scenario: Clave desconocida
- **WHEN** el archivo contiene la clave `foo`
- **THEN** el plugin carga normalmente e ignora `foo`

### Requirement: Protección del archivo editado a mano
Si `settings.json` no es JSON válido, el plugin SHALL usar los valores por defecto en memoria, registrar un error y MUST NOT sobrescribir el archivo.

#### Scenario: JSON inválido
- **WHEN** el usuario deja una coma sobrante en `settings.json`
- **THEN** el plugin funciona con los valores por defecto y el archivo del usuario queda intacto
