# Tareas a realizar en el Kindle

Guía autocontenida de todas las tareas marcadas `[dispositivo]` en las changes de OpenSpec. Está pensada para hacerse en otro momento y desde otro equipo, sin más contexto que este archivo.

| Fase | Change de OpenSpec | Tareas en el Kindle | ¿Cuándo? |
|------|--------------------|---------------------|----------|
| 1 | `add-bff-dashboard-mvp` | 1.1, 1.2, 1.3, 1.4 (spike) | **Ahora**: no necesitan el backend ni el plugin real |
| 1 | `add-bff-dashboard-mvp` | 8.4, 9.2, 9.3, 9.4 | Cuando el plugin de la Fase 1 esté terminado |
| 2 | `refactor-data-provider-abstraction` | 5.1, 5.2 | Al terminar la Fase 2 |
| 3 | `add-standalone-direct-provider` | 4.2, 6.1, 6.2 | Durante y al terminar la Fase 3 |

---

## 0. Preparación (una sola vez)

### 0.1 Requisitos del Kindle
- [ ] Kindle con jailbreak y **KOReader v2024.04 o posterior** (versión en *Menú → ? → Acerca de*).
- [ ] **Sin "Ofertas especiales"** (anuncios en la pantalla de bloqueo).
- [ ] En KOReader existe el menú *Pantalla (engranaje) → Pantalla de suspensión*. Si no aparece, KOReader no puede pintar su propia pantalla de suspensión en este Kindle y el proyecto no es viable en él: **detente y avisa**.
- [ ] Wi-Fi configurado y funcionando en KOReader.

Anota el modelo:

| Dato | Valor |
|------|-------|
| Modelo de Kindle (p. ej. Paperwhite 4) | |
| Versión de firmware del Kindle | |
| Versión de KOReader | |
| Resolución (si la conoces) | |

### 0.2 Cómo copiar archivos y leer el log
- **Por USB:** conecta el Kindle al PC. La carpeta de KOReader está en `koreader/` en la raíz del Kindle.
  - Plugins: `koreader/plugins/<nombre>.koplugin/`
  - Log: `koreader/crash.log`
- **Por SSH** (si tienes el plugin SSH de KOReader activo): la misma ruta es `/mnt/us/koreader/`.
- Después de copiar un plugin, **reinicia KOReader**: *Menú → Salir → Reiniciar KOReader*.
- Antes de cada prueba, conviene **vaciar `crash.log`** (bórralo; KOReader lo vuelve a crear) para que sólo contenga esa prueba.

### 0.3 Cómo devolver los resultados
1. Rellena las tablas de este archivo (o una copia).
2. Guarda el `crash.log` de cada bloque de pruebas con un nombre descriptivo (p. ej. `crash-q1.log`).
3. Sube todo a `openspec/changes/<change>/findings/` en el repo (`git add`, `commit`, `push`).
4. En Claude Code: *"ya hice las tareas X.Y en el Kindle, los resultados están en findings/"*. Claude marcará las tareas y ajustará el plan si hace falta.

---

## FASE 1 — Spike de integración (tareas 1.1 a 1.4)

**Objetivo:** responder con datos reales cinco preguntas (Q1–Q5) que deciden el diseño antes de escribir el plugin definitivo. Duración estimada: 2–3 horas.

### 1.0 Instalar el plugin de prueba

Crea la carpeta `koreader/plugins/spike.koplugin/` con estos dos archivos.

**`_meta.lua`**

```lua
local _ = require("gettext")
return {
    name = "spike",
    fullname = _("Spike dashboard"),
    description = _([[Plugin temporal de mediciones para el dashboard. Borrar al terminar.]]),
}
```

**`main.lua`**

```lua
-- Plugin temporal de mediciones (spike) para KOReader Dashboard Screensaver.
-- Todas las líneas de log empiezan con "[spike]" y quedan en koreader/crash.log.
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local NetworkMgr = require("ui/network/manager")
local Screensaver = require("ui/screensaver")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiutil = require("ffi/util")
local http = require("socket.http")
local logger = require("logger")
local socket = require("socket")
local socketutil = require("socketutil")
local time = require("ui/time")
local Screen = Device.screen

local DEFAULT_HTTP = "http://example.com/"
local DEFAULT_HTTPS = "https://example.com/"

local function now_ms() return time.to_ms(time.now()) end
local function log(...) logger.info("[spike]", os.date("%H:%M:%S"), ...) end
local function setting(key, default)
    local v = G_reader_settings:readSetting(key)
    if v == nil then return default end
    return v
end

-- Q1: registrar cuándo pinta el screensaver nativo (se envuelve una sola vez)
if not Screensaver._spike_wrapped then
    local orig_show = Screensaver.show
    Screensaver.show = function(self, ...)
        log("Screensaver.show t=", now_ms())
        return orig_show(self, ...)
    end
    Screensaver._spike_wrapped = true
end

-- Petición GET acotada: devuelve (resultado, ms)
local function probe(url, total_timeout)
    local sink = {}
    local t = now_ms()
    socketutil:set_timeout(1, total_timeout or 2.5)
    local ok, code = pcall(function()
        return socket.skip(1, http.request{
            url = url, method = "GET",
            sink = socketutil.table_sink(sink),
            create = socketutil.tcp,
        })
    end)
    socketutil:reset_timeout()
    local result = ok and tostring(code) or ("EXC " .. tostring(code))
    return result, now_ms() - t
end

local Spike = WidgetContainer:extend{
    name = "spike",
    is_doc_only = false,
}

function Spike:init()
    self.ui.menu:registerToMainMenu(self)
end

function Spike:onSuspend()
    local t0 = now_ms()
    log("onSuspend t=", t0,
        "online=", tostring(NetworkMgr:isOnline()),
        "wifi_on=", tostring(NetworkMgr:isWifiOn()),
        "screensaver_type=", tostring(G_reader_settings:readSetting("screensaver_type")))

    -- Q2: ¿hay red útil durante la suspensión?
    if G_reader_settings:isTrue("spike_net") then
        local res, ms = probe(setting("spike_url_http", DEFAULT_HTTP), 2.5)
        log("Q2 probe result=", res, "ms=", ms)
    end

    -- Q4: espera artificial antes de pintar
    local block = setting("spike_block_s", 0)
    if block > 0 then
        log("Q4 bloqueando", block, "s")
        ffiutil.sleep(block)
    end

    -- Q3: medir el pintado a pantalla completa
    local label = string.format("SPIKE %s  espera=%ds", os.date("%H:%M:%S"), block)
    self.widget = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        CenterContainer:new{
            dimen = Geom:new{ w = Screen:getWidth(), h = Screen:getHeight() },
            TextWidget:new{ text = label, face = Font:getFace("tfont", 40) },
        },
    }
    local tp = now_ms()
    UIManager:show(self.widget)
    UIManager:setDirty(self.widget, "full")
    UIManager:forceRePaint()
    log("Q3 paint_ms=", now_ms() - tp, "total_ms=", now_ms() - t0, "label=", label)
end

function Spike:onResume()
    log("onResume t=", now_ms())
    if self.widget then
        UIManager:close(self.widget)
        self.widget = nil
        UIManager:setDirty("all", "full")
    end
end

-- Q5: 10 GET por HTTP y 10 por HTTPS al mismo host, con el Kindle despierto
local function bench()
    local lines = {}
    for _, spec in ipairs{ { "HTTP", setting("spike_url_http", DEFAULT_HTTP) },
                           { "HTTPS", setting("spike_url_https", DEFAULT_HTTPS) } } do
        local times = {}
        for i = 1, 10 do
            local res, ms = probe(spec[2], 10)
            log("Q5", spec[1], i, "result=", res, "ms=", ms)
            table.insert(times, ms)
        end
        table.sort(times)
        table.insert(lines, string.format("%s  min=%d  mediana=%d  max=%d ms",
            spec[1], times[1], times[5], times[10]))
    end
    local text = table.concat(lines, "\n")
    log("Q5 resumen\n" .. text)
    UIManager:show(InfoMessage:new{ text = "Resultados Q5:\n\n" .. text })
end

local function editUrl(key, title, default)
    local dlg
    dlg = InputDialog:new{
        title = title,
        input = setting(key, default),
        buttons = {{
            { text = "Cancelar", id = "close", callback = function() UIManager:close(dlg) end },
            { text = "Guardar", is_enter_default = true, callback = function()
                G_reader_settings:saveSetting(key, dlg:getInputText())
                UIManager:close(dlg)
            end },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

function Spike:addToMainMenu(menu_items)
    menu_items.spike_dashboard = {
        text = "Spike dashboard",
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = "Q2 · Probar red al suspender",
                checked_func = function() return G_reader_settings:isTrue("spike_net") end,
                callback = function() G_reader_settings:flipNilOrFalse("spike_net") end,
            },
            {
                text_func = function()
                    return "Q4 · Espera antes de pintar: " .. setting("spike_block_s", 0) .. " s (toca para cambiar)"
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    G_reader_settings:saveSetting("spike_block_s", (setting("spike_block_s", 0) + 1) % 5)
                    touchmenu_instance:updateItems()
                end,
            },
            {
                text = "Q5 · Medir HTTP vs HTTPS (10 + 10)",
                callback = function()
                    UIManager:show(InfoMessage:new{ text = "Midiendo… (puede tardar ~30 s)", timeout = 2 })
                    UIManager:scheduleIn(2.5, bench)
                end,
            },
            {
                text = "Configurar URL HTTP de prueba",
                keep_menu_open = true,
                callback = function() editUrl("spike_url_http", "URL HTTP", DEFAULT_HTTP) end,
            },
            {
                text = "Configurar URL HTTPS de prueba",
                keep_menu_open = true,
                callback = function() editUrl("spike_url_https", "URL HTTPS", DEFAULT_HTTPS) end,
            },
        },
    }
end

return Spike
```

Reinicia KOReader. Debe aparecer **Herramientas → Spike dashboard**. Si KOReader no arranca o el menú no aparece, copia las últimas líneas de `crash.log` y pásaselas a Claude.

> Por defecto, las pruebas de red usan `example.com`, que responde tanto por HTTP como por HTTPS. Si el backend ya está desplegado, puedes poner su `/healthz` como URL HTTP.

---

### Tarea 1.1 — Q1: ¿quién pinta primero, el plugin o el screensaver nativo?

**Pasos:**
1. En *Spike dashboard*: **desactiva** "Probar red al suspender" y deja la espera en **0 s**.
2. Pon *Pantalla → Pantalla de suspensión* en un tipo **distinto de "Desactivada"** (p. ej. "Portada del libro"). Anota cuál.
3. Vacía `crash.log`.
4. Suspende con el botón de encendido, espera ~5 s, **mira qué muestra la pantalla** y despierta. Repite **5 veces**.
5. Pon *Pantalla de suspensión* en **"Desactivada"** (o "Sin pantalla de suspensión", según la versión).
6. Repite 5 suspensiones más, mirando la pantalla cada vez.
7. Guarda `crash.log` como `crash-q1.log`.

**Resultados:**

| # | Tipo de pantalla de suspensión | ¿Qué se ve en la pantalla? (texto "SPIKE…", portada, mezcla, nada) | En el log, ¿aparece `Screensaver.show` antes o después de `onSuspend`? |
|---|------|------|------|
| 1 | | | |
| 2 | | | |
| 3 | | | |
| 4 | | | |
| 5 | | | |
| 6 | Desactivada | | |
| 7 | Desactivada | | |
| 8 | Desactivada | | |
| 9 | Desactivada | | |
| 10 | Desactivada | | |

**Cómo se interpreta** (lo decide Claude con los datos, pero como referencia):
- Con "Desactivada" se ve siempre "SPIKE…" limpio → **estrategia A** (usar `onSuspend`).
- La portada tapa el texto, aparece mezclada, o "Desactivada" hace que no se vea nada → **estrategia B** (reemplazar el screensaver nativo).

---

### Tarea 1.2 — Q2: ¿hay red durante la suspensión?

**Pasos:**
1. *Pantalla de suspensión* en **"Desactivada"**.
2. En *Spike dashboard*: **activa** "Probar red al suspender" y deja la espera en **0 s**.
3. Asegúrate de que el Wi-Fi está **conectado**.
4. Vacía `crash.log`.
5. Haz **20 suspensiones**, alternando entre suspender enseguida tras despertar (10 veces) y tras 2–3 minutos de uso (10 veces). Espera ~5 s dormido antes de despertar.
6. Guarda `crash.log` como `crash-q2.log`.

**Resultados** (salen de las líneas `onSuspend … online=` y `Q2 probe result= … ms=`):

| # | Espera previa | `online` | `result` (200 = OK) | `ms` |
|---|---------------|----------|---------------------|------|
| 1–10 | inmediata | | | |
| 11–20 | 2–3 min | | | |

Resumen: éxitos ___ / 20. **Si fallan más de 4 (> 20 %)**, el plan incorpora la descarga previa de datos con el Kindle despierto.

---

### Tarea 1.3 — Q3: ¿cuánto tarda el refresco completo?

Sale de las mismas suspensiones de 1.1 y 1.2: las líneas `Q3 paint_ms=`.

| Métrica | Valor |
|---------|-------|
| `paint_ms` mínimo | |
| `paint_ms` típico (mediana) | |
| `paint_ms` máximo | |
| ¿La pantalla hace **flash** negro/blanco al mostrar "SPIKE…"? (sí/no) | |
| ¿Quedan **restos** de la página anterior? (sí/no) | |

---

### Tarea 1.3 (cont.) — Q4: ¿cuánto margen da el Kindle antes de dormir?

**Pasos:**
1. *Pantalla de suspensión* en "Desactivada"; **desactiva** "Probar red al suspender".
2. Para cada espera (**1, 2, 3 y 4 s**; se cambia tocando el ítem "Q4 · Espera…"), haz **3 suspensiones**.
3. En cada una, mira si llega a aparecer el texto "SPIKE … espera=Ns" antes de que el Kindle duerma.
4. Guarda `crash.log` como `crash-q4.log`.

| Espera | Intento 1: ¿aparece "SPIKE"? | Intento 2 | Intento 3 | Observaciones |
|--------|------------------------------|-----------|-----------|---------------|
| 1 s | | | | |
| 2 s | | | | |
| 3 s | | | | |
| 4 s | | | | |

> Si con alguna espera el texto no aparece, o aparece al **despertar** en vez de al dormir, anótalo. Es justo lo que se quiere saber.

---

### Tarea 1.4 — Q5: coste de HTTPS frente a HTTP

**Pasos:**
1. Con el Wi-Fi conectado y el Kindle **despierto**.
2. Vacía `crash.log`.
3. *Spike dashboard → Q5 · Medir HTTP vs HTTPS*. Espera el mensaje con los resultados.
4. Repítelo 2 veces más (3 rondas en total).
5. Guarda `crash.log` como `crash-q5.log`.

| Ronda | HTTP mediana (ms) | HTTPS mediana (ms) | Diferencia |
|-------|-------------------|--------------------|------------|
| 1 | | | |
| 2 | | | |
| 3 | | | |

Si la diferencia pasa de **1000 ms**, se recomienda HTTP en la LAN o una VPN para el backend.

---

### Cierre del spike
- [ ] Todos los logs (`crash-q1.log` … `crash-q5.log`) y este archivo rellenado subidos a `openspec/changes/add-bff-dashboard-mvp/findings/`.
- [ ] **Borrar** `koreader/plugins/spike.koplugin/` del Kindle y reiniciar KOReader.
- [ ] Dejar *Pantalla de suspensión* como estaba (anota cómo estaba: ________).

---

## FASE 1 — Aceptación del plugin terminado (tareas 8.4, 9.2, 9.3, 9.4)

> Requisitos: el backend desplegado y accesible desde el Kindle, y el plugin `dashboardscreensaver.koplugin` de la Fase 1 terminado.

### Tarea 8.4 — Instalación desde cero siguiendo sólo el README

- [ ] Seguir `plugin/README.md` **al pie de la letra**, sin ayuda externa.
- [ ] Anotar cada paso confuso, incompleto o incorrecto:

| Paso del README | Problema |
|-----------------|----------|
| | |

### Tarea 9.2 — Checklist de escenarios

Antes de empezar: en `settings.json` del plugin, pon `"debug": { "log_timings": true }`. Vacía `crash.log` y guárdalo al final como `crash-aceptacion.log`.

Cómo provocar cada condición:
- **Caché de hace X tiempo:** usa el dashboard con red, después apaga el Wi-Fi y espera ese tiempo, o pide a Claude una herramienta para fijar la fecha del caché.
- **Servidor colgado:** en el servidor, `docker compose pause` (acepta conexiones pero no responde) y `docker compose unpause` para volver.
- **Servidor apagado:** `docker compose stop`.
- **Caché corrupto:** abre `dashboard_cache.json` y borra la mitad final del contenido.

| # | Escenario | Cómo prepararlo | Resultado esperado | ✔/✘ | Notas |
|---|-----------|-----------------|--------------------|-----|-------|
| 1 | Camino feliz con red | Wi-Fi on, caché de más de 10 min | Dashboard en < 3 s con fecha, clima, agenda y batería; pie "En vivo"; flash completo sin restos | | |
| 2 | Caché reciente | Suspender, despertar y volver a suspender antes de 10 min | Sin petición de red (log); aparece en < 1 s | | |
| 3 | Modo avión | Wi-Fi off, caché de ~2 h | El Wi-Fi sigue apagado; pie "Sin conexión · datos de hace 2 h" | | |
| 4 | Servidor colgado | `docker compose pause`, caché de ~1 h | Muestra el caché; total ≤ 3.0 s en el log; `E_TIMEOUT` | | |
| 5 | Servidor apagado | `docker compose stop` | Muestra el caché en ≤ 1 s más de lo normal | | |
| 6 | Portal cautivo | Pedir a Claude una URL de prueba que responda HTML | Caché sin modificar; pie "Respuesta inválida" | | |
| 7 | Token inválido | Cambiar el token en `settings.json` | Caché; pie "Token inválido"; el token no aparece en `crash.log` | | |
| 8 | Sin cambios (304) | Caché de ~20 min sin cambios en el calendario | Pie "En vivo"; `validated_at` actualizado | | |
| 9 | Primera ejecución sin nada | Borrar el caché, Wi-Fi off | Fecha, batería y "Sin datos: conéctate a Wi-Fi para actualizar" | | |
| 10 | Caché corrupto | Truncar `dashboard_cache.json`, Wi-Fi off | El archivo se borra; pantalla mínima | | |
| 11 | Caché de ayer | Dejar el caché de un día para otro sin red | "Agenda desactualizada"; clima con aviso de antigüedad | | |
| 12 | Datos de hace 5 h | Caché de ~5 h sin red | Pie "⚠ Datos de hace 5 h"; la agenda se muestra | | |
| 13 | Backend sin configurar | `backend.url` vacía | Sin petición; pie "Configura el backend" | | |
| 14 | Despertar | Despertar con el dashboard visible | El dashboard desaparece y la página se repinta sin restos | | |
| 15 | Plugin desactivado | Desactivarlo en el menú | Pantalla de suspensión nativa; sin petición HTTP | | |
| 16 | Muchos eventos | Crear 8 eventos hoy con títulos largos | Nada sale de los márgenes; "+N más" si no caben | | |
| 17 | Sin eventos hoy | Un día sin eventos pendientes | "Sin eventos hoy" | | |
| 18 | Anti-ghosting doble | `display.anti_ghosting = "double"` | Flash negro y luego el dashboard | | |
| 19 | Modo noche | Activar el modo noche en KOReader | Pantalla invertida, sin halos grises | | |
| 20 | Vista previa | Menú → "Vista previa ahora" | Se muestra el dashboard; un toque lo cierra | | |
| 21 | Refrescar con error | Backend parado + "Refrescar datos ahora" | Mensaje de error legible; caché intacto | | |
| 22 | Ver estado del caché | Menú → "Ver estado del caché" | Muestra la antigüedad, el origen, el último error y los tiempos | | |

Anota **una foto** de la pantalla en los escenarios 1, 3, 9, 11 y 16 si puedes; son útiles para revisar el layout.

### Tarea 9.3 — Tiempos

**Pasos:**
1. `log_timings` activado, backend funcionando, Wi-Fi on y `cache.min_refresh_interval_s = 0` en `settings.json` (para forzar la red en cada suspensión).
2. **50 suspensiones** normales. Guarda el log como `crash-tiempos-lan.log`.
3. `docker compose pause` en el servidor y **10 suspensiones**. Guarda el log como `crash-tiempos-colgado.log`.
4. Devuelve `min_refresh_interval_s` a 600.

Los tiempos salen de las líneas `[dashboard] suspend … total=`. Claude puede calcular los percentiles a partir del log; basta con subir los archivos.

| Medición | Objetivo | Resultado |
|----------|----------|-----------|
| p95 `total` con LAN | ≤ 1000 ms | |
| Máximo `total` con el servidor colgado | ≤ 3000 ms | |

### Tarea 9.4 — Batería (6 días)

Se compara el consumo con el plugin **activado** frente a **desactivado**, con el mismo uso.

**Reglas para las dos mitades:**
- Unas **20 suspensiones al día**, con un uso de lectura parecido.
- Mismo brillo, mismo Wi-Fi (on u off igual en ambas mitades) y sin cargar durante la medición del día.
- Anota el % de batería (visible en el pie del dashboard o en la barra de KOReader) al empezar y al terminar cada día.

| Día | Plugin | Batería inicio | Batería fin | Consumo del día | Suspensiones aprox. |
|-----|--------|----------------|-------------|-----------------|---------------------|
| 1 | Activado | | | | |
| 2 | Activado | | | | |
| 3 | Activado | | | | |
| 4 | Desactivado | | | | |
| 5 | Desactivado | | | | |
| 6 | Desactivado | | | | |

Objetivo: diferencia media **< 1 % por día** atribuible al plugin.

> Consejo: empieza esta prueba en cuanto el plugin funcione de forma estable, en paralelo con el resto, porque ocupa casi una semana de calendario.

---

## FASE 2 — Aceptación (tareas 5.1 y 5.2)

> Requisitos: la change `refactor-data-provider-abstraction` implementada.

### Tarea 5.1 — Regresión
- [ ] Con `provider = backend`, repetir la **checklist 9.2 completa** (22 escenarios). Todo debe dar el mismo resultado que en la Fase 1. Anotar cualquier diferencia:

| # escenario | Diferencia observada |
|-------------|----------------------|
| | |

### Tarea 5.2 — Menú de ajustes y proveedor

| # | Escenario | Cómo prepararlo | Resultado esperado | ✔/✘ | Notas |
|---|-----------|-----------------|--------------------|-----|-------|
| 1 | Cambiar la URL | Editar la URL del backend en el menú | `settings.json` actualizado; la siguiente suspensión la usa **sin reiniciar KOReader** | | |
| 2 | Timeout fuera de rango | Intentar poner 4 s | El selector no deja pasar de 2.5 s | | |
| 3 | Token enmascarado | Abrir el ajuste del token | Se ve enmascarado; no está en `crash.log` | | |
| 4 | Probar conexión OK | Backend activo | Mensaje "OK · N ms · N KB"; caché actualizado | | |
| 5 | Probar conexión 401 | Token incorrecto | "Token inválido"; caché intacto | | |
| 6 | Borrar caché | Menú → Borrar caché → confirmar | El estado del caché indica "sin caché" | | |
| 7 | Cambio de proveedor | Cambiar a "Directo" (aún no implementado en la Fase 2) | Se muestra el caché; pie "Proveedor no configurado" | | |
| 8 | Conserva claves | Poner `debug.log_timings: true` a mano y cambiar la URL desde el menú | `log_timings` sigue en `true` | | |

---

## FASE 3 — Rendimiento y aceptación (tareas 4.2, 6.1 y 6.2)

> Requisitos: la change `add-standalone-direct-provider` implementada. Claude te dará tres archivos `.ics` de prueba (50, 200 y 500 KB) y la forma de lanzar el benchmark.

### Tarea 4.2 — Benchmark de lectura de .ics

| Tamaño del .ics | Tiempo de lectura (ms) | Memoria pico (si se muestra) | Observaciones |
|-----------------|------------------------|------------------------------|---------------|
| 50 KB | | | |
| 200 KB | | | |
| 500 KB | | | |

Si 200 KB tarda más de **1000 ms**, se reducirá el límite por defecto de tamaño del .ics.

### Tarea 6.1 — Modo autónomo y fallback

Si puedes, haz una parte **en una red ajena** (la de otra casa, un café o el teléfono como punto de acceso), donde el backend no sea accesible.

| # | Escenario | Cómo prepararlo | Resultado esperado | ✔/✘ | Notas |
|---|-----------|-----------------|--------------------|-----|-------|
| 1 | Modo directo | `provider = direct`, coordenadas + URL .ics | Clima y eventos en < 3 s; pie "Directo" | | |
| 2 | Hora local correcta | Kindle en UTC (si es posible cambiarlo), coordenadas de tu ciudad | Horas de los eventos en hora local correcta | | |
| 3 | Evento de todo el día | Crear uno hoy | "Todo el día" | | |
| 4 | Evento recurrente | Evento semanal creado hace 2+ semanas | **No** aparece (limitación conocida); aviso `RRULE_IGNORED` en el estado del caché | | |
| 5 | Calendario caído | URL .ics inválida | Clima OK; "Agenda no disponible" | | |
| 6 | Todo caído | Sin Internet pero con Wi-Fi local | Muestra el caché | | |
| 7 | Fallback directo | `provider = backend`, `fallback = direct`, backend apagado (`docker compose stop`) | Datos del modo directo; pie "Directo (respaldo)"; total ≤ 3.0 s | | |
| 8 | Fallback sólo a caché | `fallback = cache`, backend colgado (`docker compose pause`) | Muestra el caché sin intentar el modo directo | | |
| 9 | 401 no dispara el fallback | `fallback = direct`, token incorrecto | Caché; pie "Token inválido"; sin petición a Open-Meteo en el log | | |
| 10 | Sin coordenadas | `provider = direct` sin latitud/longitud | Sin petición; pie "Proveedor no configurado" | | |

### Tarea 6.2 — Regresión final
- [ ] Con `provider = backend` y `fallback = cache`, repetir la checklist **9.2** (Fase 1) y la **5.2** (Fase 2). Anotar las diferencias:

| Checklist / # | Diferencia observada |
|---------------|----------------------|
| | |
