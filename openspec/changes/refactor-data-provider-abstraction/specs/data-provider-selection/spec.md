## Purpose

Permitir que el dashboard obtenga sus datos de proveedores intercambiables (backend BFF o directo), con garantías comunes que protejan el presupuesto de suspensión sin importar cuál esté activo.

## ADDED Requirements

### Requirement: Proveedor activo configurable
El plugin SHALL usar como fuente de datos el proveedor indicado por `provider` en la configuración (`backend` o `direct`). Un cambio de proveedor MUST aplicarse en la siguiente suspensión sin reiniciar KOReader.

#### Scenario: Cambio de proveedor en caliente
- **WHEN** el usuario cambia el proveedor de `backend` a `direct` desde el menú
- **THEN** la siguiente suspensión usa el proveedor `direct` sin reiniciar KOReader

#### Scenario: Proveedor aún no disponible
- **WHEN** `provider` es `direct` y el modo directo no está implementado o configurado
- **THEN** se muestra el caché y el pie indica "Proveedor no configurado"

### Requirement: Garantías comunes de todo proveedor
Todo proveedor SHALL entregar exactamente un resultado por petición (datos, "sin cambios" o error), MUST terminar dentro del tiempo asignado más 100 ms, SHALL entregar datos ya validados y normalizados según el contrato del dashboard y MUST NOT modificar el caché por sí mismo.

#### Scenario: Proveedor lento
- **WHEN** se asignan 1.5 s a un proveedor cuyo servidor no responde
- **THEN** el proveedor entrega un error de timeout antes de 1.6 s

#### Scenario: Un solo resultado
- **WHEN** un proveedor recibe una respuesta HTTP corrupta
- **THEN** entrega un único resultado de error y ningún resultado de éxito

### Requirement: Comportamiento del modo backend sin cambios
Con `provider` igual a `backend`, el plugin SHALL comportarse exactamente como en la Fase 1.

#### Scenario: Regresión de la Fase 1
- **WHEN** `provider` es `backend`
- **THEN** todos los escenarios de `suspend-dashboard`, `dashboard-cache` y `eink-dashboard-view` siguen cumpliéndose
