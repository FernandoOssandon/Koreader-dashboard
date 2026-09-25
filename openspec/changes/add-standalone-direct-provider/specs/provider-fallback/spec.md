## Purpose

Mantener el dashboard actualizado cuando el backend no está disponible, conmutando automáticamente al proveedor directo o al caché dentro del presupuesto de suspensión.

## ADDED Requirements

### Requirement: Fallback configurable
Con `provider` igual a `backend`, el plugin SHALL aplicar la política `fallback`: `cache` (por defecto) muestra el caché si el backend falla; `direct` intenta primero el proveedor directo y, si éste también falla, muestra el caché; `none` muestra la pantalla mínima sin caché. `fallback` igual a `direct` MUST ignorarse cuando `provider` ya es `direct`.

#### Scenario: Backend apagado con fallback directo
- **WHEN** `provider` es `backend`, `fallback` es `direct`, el backend rechaza la conexión y hay Wi-Fi
- **THEN** los datos se obtienen del proveedor directo y el control vuelve a KOReader en 3.0 s o menos

#### Scenario: Fallback sólo a caché
- **WHEN** `fallback` es `cache` y el backend no responde
- **THEN** se muestra el caché sin intentar el proveedor directo

### Requirement: Condiciones para intentar el fallback
El proveedor directo SHALL intentarse como fallback sólo si el error del backend es recuperable (timeout, conexión rechazada, sin ruta, error 5xx) y quedan al menos 1.2 s de presupuesto. Errores de autenticación, de contrato o de configuración MUST NOT disparar el fallback, porque indican un problema que el usuario debe corregir. El pie SHALL indicar qué fuente produjo los datos mostrados.

#### Scenario: Timeout consume el presupuesto
- **WHEN** el backend agota 2.2 s de timeout y quedan menos de 1.2 s
- **THEN** no se intenta el proveedor directo y se muestra el caché

#### Scenario: Token inválido no dispara el fallback
- **WHEN** el backend responde 401 y `fallback` es `direct`
- **THEN** no se intenta el proveedor directo, se muestra el caché y el pie indica "Token inválido"

#### Scenario: Fuente visible
- **WHEN** los datos mostrados provienen del fallback directo
- **THEN** el pie indica "Directo (respaldo)"
