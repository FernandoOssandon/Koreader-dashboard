## Why

Tras la Fase 1, el orquestador está atado a un único cliente HTTP y la configuración sólo se puede cambiar editando `settings.json` a mano. Para añadir el modo standalone (Fase 3) sin tocar la vista, el caché ni el ciclo de suspensión, hace falta una interfaz de proveedor explícita e intercambiable, y un menú que permita elegirla y configurarla desde el propio Kindle.

> **Depende de:** `add-bff-dashboard-mvp` archivada (sus capacidades deben existir en `openspec/specs/`).

## What Changes

- Interfaz formal `DataProvider` (`fetchData(onSuccess, onError, opts)`, `getCachedData()`, `isConfigured()`) con invariantes verificables mediante una suite de contrato compartida.
- El cliente de la Fase 1 pasa a ser `BackendProvider`, sin cambios de comportamiento.
- Selección del proveedor activo según `settings.json` (`provider`), aplicada sin reiniciar KOReader. `direct` responde "no configurado" hasta la Fase 3.
- Menú de ajustes completo en KOReader: proveedor, URL y token del backend, timeouts, parámetros de caché y de pantalla, "Probar conexión" y "Borrar caché". El menú mínimo de la Fase 1 se integra en él.
- Guardado atómico de `settings.json` desde el menú.

## Capabilities

### New Capabilities
- `data-provider-selection`: selección del proveedor de datos activo y garantías comunes que todo proveedor cumple ante el ciclo de suspensión.
- `plugin-settings-menu`: menú de configuración dentro de KOReader y acción de prueba de conexión.

### Modified Capabilities
- `plugin-configuration`: `provider` pasa a tener efecto y la configuración puede guardarse desde el menú.

## Impact

- **Plugin:** nuevos `dashboard/data_provider.lua`, `dashboard/provider_factory.lua` y `dashboard/settings.lua`; `backend_client.lua` se renombra a `provider_backend.lua`; `orchestrator.lua` recibe el proveedor inyectado.
- **Sin cambios** en el backend, el contrato de datos, el caché ni la vista. Todos los escenarios de la Fase 1 deben seguir pasando.
