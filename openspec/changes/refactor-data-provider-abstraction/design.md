## Context

En la Fase 1, `orchestrator.lua` crea `backend_client.lua` directamente. El cliente ya expone `fetchData(onSuccess, onError, opts)` (ver `add-bff-dashboard-mvp/design.md`, D10), así que el refactor consiste sobre todo en formalizar la interfaz e inyectarla. La vista, el caché y el DTO ya son agnósticos al origen, y un test lo garantiza.

## Goals / Non-Goals

**Goals:**
- Interfaz `DataProvider` con una suite de contrato reutilizable por cualquier proveedor.
- Configuración completa desde el Kindle, con cambios en caliente.

**Non-Goals:**
- Implementar `DirectProvider` o el fallback entre proveedores (Fase 3).
- Fetch asíncrono en subproceso (la firma con callbacks lo permitiría más adelante sin cambiar a los consumidores).

## Decisions

### D1. Interfaz `DataProvider`

```lua
---@class FetchOpts { timeout_s: number, etag: string|nil }
---@class FetchMeta { etag: string|nil, not_modified: boolean|nil, elapsed_ms: integer, provider_id: string }

---@class DataProvider
---@field id string                         -- "backend" | "direct"
local DataProvider = {}

--- Contrato (MUST):
---  1. Invoca EXACTAMENTE uno de onSuccess / onError, una sola vez.
---  2. Termina antes de opts.timeout_s + 100 ms.
---  3. Síncrono en las Fases 1-3 (el callback se llama antes de que fetchData retorne).
---  4. El DTO entregado ya pasó por dto.validate + dto.sanitize.
---  5. No escribe el caché.
---@param onSuccess fun(dto: DashboardDTO|nil, meta: FetchMeta)
---@param onError fun(err: ProviderError)
---@param opts FetchOpts
function DataProvider:fetchData(onSuccess, onError, opts) end

---@return DashboardDTO|nil, CacheEntry|nil  -- por defecto delega en CacheManager y filtra por provider == self.id
function DataProvider:getCachedData() end

---@return boolean ok, string|nil missing_field
function DataProvider:isConfigured() end

--- Para los tests: verifica que un objeto implementa la interfaz.
function DataProvider.assertImplements(obj) end
```

Base con metatabla simple (`DataProvider:extend{}`) al estilo de KOReader. *Descartado:* duck typing sin clase base, porque pierde `getCachedData` por defecto y la verificación en los tests.

### D2. `ProviderFactory`

```lua
---@param config ConfigStore
---@return DataProvider primary
---@return DataProvider|nil fallback   -- nil en la Fase 2; Fase 3: DirectProvider si fallback == "direct"
function ProviderFactory.build(config) end
```

En la Fase 2, `provider = "direct"` devuelve un `UnconfiguredProvider` que responde siempre `E_NOT_CONFIGURED`. El orquestador recibe el proveedor por inyección (`SuspendOrchestrator.new{ provider = ... }`) y lo reconstruye cuando `ConfigStore` notifica un cambio en `provider`, `backend.*` o `direct.*`.

### D3. Menú de ajustes

```lua
---@param config ConfigStore
---@param on_change fun(key: string)
---@return table sub_item_table
function SettingsMenu.build(config, on_change) end
```

Widgets de KOReader: `InputDialog` para la URL, `InputDialog` con `text_type = "password"` para el token, `SpinWidget` para los números (con los rangos del clamp como `value_min` y `value_max`, así que no se pueden introducir valores inválidos), `checked_func` para los booleanos, radio para el proveedor y `ConfirmBox` para "Borrar caché". "Probar conexión" usa `runInteractive{force_fetch = true}` y muestra un `InfoMessage` con el código, los ms y los KB.

### D4. Guardado de la configuración

`ConfigStore:set(key, value)` modifica el árbol en memoria **leído del archivo** (no sólo los defaults), para no perder claves que el menú no gestiona. `ConfigStore:save()` escribe `.tmp` y hace `os.rename`. Si el archivo era JSON inválido al arrancar, el primer `save()` desde el menú pide confirmación antes de sobrescribirlo.

### D5. Suite de contrato compartida

`spec/provider_contract_spec.lua` exporta `runContract(name, factory_fn, scenarios)`: un servidor falso (http inyectado) que simula OK, 304, timeout, basura y error, y comprueba los invariantes 1, 2, 4 y 5 de D1. La Fase 3 la reutiliza con `DirectProvider`.

## Risks / Trade-offs

- **[Regresión silenciosa al renombrar el cliente]** → Los tests de la tarea 6.2 de la Fase 1 se reutilizan sin cambios y la suite de contrato se ejecuta sobre `BackendProvider`.
- **[Cambios de configuración a mitad de una suspensión]** → Las suspensiones leen una instantánea de la configuración al empezar; la reconstrucción del proveedor ocurre fuera de `runSuspend`.
- **[Usuario sin teclado cómodo para URLs largas]** → Se mantiene la opción de editar `settings.json` a mano; el menú recarga el archivo al abrirse.
