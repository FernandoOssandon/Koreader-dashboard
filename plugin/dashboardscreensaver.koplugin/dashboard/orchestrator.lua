-- Ciclo de vida de la suspensión (design D3/D4): presupuesto de 3 s, un solo intento de red,
-- degradación a caché → pantalla mínima, y guardado del caché DESPUÉS de pintar.
local CacheManager = require("dashboard/cache_manager")
local ViewModel = require("dashboard/view_model")
local logger = require("logger")
local redact = require("dashboard/redact")

local Orchestrator = {}
Orchestrator.__index = Orchestrator

local BUDGET_MS = 3000
local PAINT_RESERVE_S = 0.7 -- tiempo que se deja para pintar tras la red
local MIN_NET_S = 0.5       -- con menos que esto, ni se intenta la red

--- deps: {
---   config      = objeto con `.cfg` (se lee en cada uso: los cambios de ajustes se ven sin reiniciar),
---   client      = { fetchData(onSuccess, onError, opts) },
---   cache       = CacheManager,
---   ui          = { show, close, setDirty, forceRePaint, paintBlack },
---   network     = { isOnline() },
---   makeWidget  = fn(view_model, display, opts) -> widget,
---   readDevice  = fn() -> { battery, charging, date, weekday }   (opcional)
---   now_ms, now, today = relojes inyectables                      (opcionales)
--- }
function Orchestrator.new(deps)
    local d = deps
    d.readDevice = d.readDevice or ViewModel.readDevice
    d.now = d.now or os.time
    d.today = d.today or function() return os.date("%Y-%m-%d") end
    if not d.now_ms then
        local time = require("ui/time")
        d.now_ms = function() return time.to_ms(time.now()) end
    end
    return setmetatable({ d = d }, Orchestrator)
end

--- ¿Hay que pedir datos? Función pura.
--- @return boolean, string|nil  (hacer la petición, código de error a mostrar si no se hace)
function Orchestrator.shouldFetch(entry, now, cache_cfg, online, url)
    if url == nil or url == "" then return false, "E_NOT_CONFIGURED" end
    if entry then
        local age = now - entry.validated_at
        local same_day = entry.dto.date == os.date("%Y-%m-%d", now)
        if age >= 0 and age < cache_cfg.min_refresh_interval_s and same_day then
            return false, nil -- caché confirmado hace poco: ahorra batería
        end
    end
    if not online then return false, "E_NO_NETWORK" end
    return true, nil
end

-- Obtiene los datos (red o caché) y decide qué mostrar. `deadline` (ms) sólo existe en la suspensión.
function Orchestrator:_gather(opts)
    local d, cfg = self.d, self.d.config.cfg
    local t = { cache = 0, net = 0 }

    local t0 = d.now_ms()
    local entry = d.cache:load()
    t.cache = d.now_ms() - t0

    local online = false
    local ok, res = pcall(function() return d.network:isOnline() end)
    if ok then online = res and true or false end

    local should, reason
    if opts.no_network then -- "Vista previa": sólo lo que ya hay
        should = false
    elseif opts.force then -- "Refrescar ahora": ignora min_refresh_interval_s
        if cfg.backend.url == "" then should, reason = false, "E_NOT_CONFIGURED"
        elseif not online then should, reason = false, "E_NO_NETWORK"
        else should = true end
    else
        should, reason = Orchestrator.shouldFetch(entry, d.now(), cfg.cache, online, cfg.backend.url)
    end

    local dto, meta, err
    if should then
        local timeout = cfg.backend.total_timeout_s
        if opts.deadline then
            timeout = math.min(timeout, (opts.deadline - d.now_ms()) / 1000 - PAINT_RESERVE_S)
        end
        if timeout < MIN_NET_S then
            err = { code = "E_BUDGET_EXCEEDED", message = "sin presupuesto para la red" }
        else
            local n0 = d.now_ms()
            local cok, cerr = pcall(d.client.fetchData, d.client,
                function(x, m) dto, meta = x, m end,
                function(e) err = e end,
                { timeout_s = timeout, etag = entry and entry.etag })
            t.net = d.now_ms() - n0
            if not cok then -- una excepción del cliente nunca debe impedir mostrar el caché
                dto, meta = nil, nil
                err = { code = "E_INTERNAL", message = "excepción en el cliente" }
                logger.warn("[dashboard] cliente lanzó una excepción:", redact(cerr, cfg.backend.token):sub(1, 200))
            end
        end
    elseif reason then
        err = { code = reason }
    end

    local shown, fresh
    if meta and meta.not_modified and entry then
        d.cache:touch()
        shown, fresh = entry.dto, { origin = "live", age_s = 0, level = "fresh" }
        dto = nil -- nada nuevo que guardar
    elseif dto then
        shown, fresh = dto, { origin = "live", age_s = 0, level = "fresh" }
    elseif entry then
        shown = entry.dto
        fresh = CacheManager.freshness(entry, d.now(), cfg.cache, d.today())
    else
        fresh = { origin = "none", level = "expired" }
    end
    if fresh.origin ~= "live" and err then
        fresh.err, fresh.err_status = err.code, err.http_status
    end
    -- Último resultado, en memoria, para "Ver estado del caché"
    self.last = { err = err, timings = t, at = d.now(), origin = fresh.origin }
    return { dto = dto, meta = meta, err = err, shown = shown, freshness = fresh, timings = t }
end

--- Entrada del caché y frescura actuales, más el resultado de la última ejecución.
function Orchestrator:status()
    local d, cfg = self.d, self.d.config.cfg
    local entry = d.cache:load()
    return { entry = entry, freshness = CacheManager.freshness(entry, d.now(), cfg.cache, d.today()), last = self.last }
end

-- Construye y pinta la vista. Si falla el árbol de widgets, cae a la pantalla mínima.
function Orchestrator:_present(g, opts)
    local d, cfg = self.d, self.d.config.cfg
    local device = d.readDevice()
    local vm = ViewModel.build(g.shown, device, g.freshness, cfg.display)
    local ok, widget = pcall(d.makeWidget, vm, cfg.display, opts)
    if not ok then
        logger.warn("[dashboard] fallo al construir la vista, usando la pantalla mínima:", tostring(widget):sub(1, 200))
        vm = ViewModel.build(nil, device, { origin = "none", level = "expired" }, cfg.display)
        widget = d.makeWidget(vm, cfg.display, opts) -- si también falla, main.lua registra "suspend failed"
    end
    if cfg.display.anti_ghosting == "double" then d.ui:paintBlack() end
    d.ui:show(widget)
    d.ui:setDirty(widget, "full")
    d.ui:forceRePaint()
    self.widget = widget
end

local function log_timings(cfg, tag, g, total, ui_ms)
    if not cfg.debug.log_timings then return end
    logger.info(("[dashboard] %s origin=%s err=%s cache=%dms net=%dms ui=%dms total=%dms"):format(
        tag, g.freshness.origin, g.err and g.err.code or "-", g.timings.cache, g.timings.net, ui_ms, total))
end

--- Handler de la suspensión. Debe devolver el control en ≤ 3 s. Lo llama main.lua dentro de un pcall.
function Orchestrator:runSuspend()
    local d, cfg = self.d, self.d.config.cfg
    if not cfg.enabled then return nil end
    local t0 = d.now_ms()
    local g = self:_gather({ deadline = t0 + BUDGET_MS })
    local u0 = d.now_ms()
    self:_present(g)
    local ui_ms = d.now_ms() - u0
    if g.dto then d.cache:save(g.dto, g.meta and g.meta.etag, "backend") end -- después de pintar
    log_timings(cfg, "suspend", g, d.now_ms() - t0, ui_ms)
    return { origin = g.freshness.origin, err = g.err, timings = g.timings }
end

--- Acciones del menú. opts: { force_fetch = bool, no_network = bool, show = bool, on_tap = fn }.
--- Sin presupuesto de 3 s.
function Orchestrator:runInteractive(opts)
    local d, cfg = self.d, self.d.config.cfg
    local t0 = d.now_ms()
    local g = self:_gather({ force = opts.force_fetch, no_network = opts.no_network })
    if opts.show then self:_present(g, { on_tap = opts.on_tap }) end
    if g.dto then d.cache:save(g.dto, g.meta and g.meta.etag, "backend") end
    local total = d.now_ms() - t0
    log_timings(cfg, "interactive", g, total, 0)
    return { origin = g.freshness.origin, err = g.err, freshness = g.freshness, dto = g.shown,
             meta = g.meta, elapsed_ms = total }
end

--- Al despertar: cierra el dashboard y repinta lo de debajo con refresco completo.
function Orchestrator:dismiss()
    local w = self.widget
    if not w then return end
    self.widget = nil
    self.d.ui:close(w)
    self.d.ui:setDirty("all", "full")
end

return Orchestrator
