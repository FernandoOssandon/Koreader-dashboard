# Dashboard de suspensión para KOReader

Plugin de KOReader que, al suspender el lector, muestra en la pantalla E-Ink un dashboard con la fecha, el clima, tu agenda del día y la batería. Los datos vienen de tu [backend](../backend/README.md) y quedan guardados en el dispositivo, así que siempre hay algo que mostrar aunque no haya Wi-Fi.

## Requisitos previos

- Kindle con jailbreak y **KOReader v2024.04 o posterior**.
- **Sin "Ofertas especiales"** (anuncios en la pantalla de bloqueo): con ellas el Kindle no permite una pantalla de suspensión propia.
- El menú *Pantalla → Pantalla de suspensión* debe existir en KOReader. Si no aparece, KOReader no puede pintar su propia pantalla de suspensión en ese Kindle y el plugin no sirve.
- El [backend](../backend/README.md) funcionando y accesible desde el Kindle (por ejemplo `http://192.168.1.10:8080`), y su token.

## Instalación

1. Conecta el Kindle por USB.
2. Copia la carpeta `dashboardscreensaver.koplugin` a `koreader/plugins/` del Kindle.
3. Reinicia KOReader: *Menú → Salir → Reiniciar KOReader*.
4. En KOReader, ve a *Pantalla (engranaje) → Pantalla de suspensión* y elige **Desactivada**. (Ver [Estrategia de pantalla de suspensión](#estrategia-de-pantalla-de-suspensión).)
5. Abre *Herramientas → Dashboard de suspensión*. La primera vez el plugin crea `settings.json` con los valores por defecto.
6. Edita `settings.json` (ver más abajo) y pon como mínimo `backend.url` y `backend.token`.
7. Prueba con *Herramientas → Dashboard de suspensión → Refrescar datos ahora* y luego *Vista previa ahora*.
8. Suspende el Kindle con el botón de encendido.

`settings.json` está en `koreader/settings/dashboardscreensaver/settings.json`. Se edita a mano; el plugin lo lee al arrancar KOReader, así que **reinicia KOReader tras cambiarlo**.

## `settings.json`, campo por campo

```json
{
  "schema_version": 1,
  "enabled": true,
  "backend": {
    "url": "http://192.168.1.10:8080/api/dashboard",
    "token": "el-token-de-tu-backend",
    "connect_timeout_s": 1.0,
    "total_timeout_s": 2.2
  },
  "cache": { "min_refresh_interval_s": 600, "stale_after_s": 10800, "max_age_s": 86400 },
  "display": { "max_events": 8, "show_hourly": true, "show_location": true, "anti_ghosting": "full" },
  "debug": { "log_timings": false }
}
```

| Campo | Por defecto | Qué hace |
|-------|-------------|----------|
| `enabled` | `true` | Si es `false`, el plugin no interviene: se muestra la pantalla de suspensión nativa y no se hace ninguna petición. También se cambia desde el menú. |
| `backend.url` | vacío | URL completa del endpoint, terminada en `/api/dashboard`. Con la URL vacía el pie muestra "Configura el backend". Conviene poner una **IP** y no un nombre, para evitar la resolución DNS. |
| `backend.token` | vacío | Token Bearer (`DASH_TOKEN` del backend). Nunca se escribe en `crash.log`. |
| `backend.connect_timeout_s` | `1.0` | Espera máxima para conectar (0.3 a 1.5). |
| `backend.total_timeout_s` | `2.2` | Espera máxima total de la petición (0.5 a 2.5). El tiempo real se recorta para que todo termine en 3 s. |
| `cache.min_refresh_interval_s` | `600` | Si los datos se confirmaron hace menos que esto, no se hace ninguna petición (ahorra batería). `0` fuerza la red en cada suspensión. Máximo 86400. |
| `cache.stale_after_s` | `10800` | Pasado este tiempo, el pie avisa "⚠ Datos de hace N h". |
| `cache.max_age_s` | `86400` | Pasado este tiempo (o al cambiar el día), la agenda se oculta como "Agenda desactualizada". |
| `display.max_events` | `8` | Máximo de eventos en la agenda (1 a 8). |
| `display.show_hourly` | `true` | Muestra las franjas horarias del clima (sólo en vertical). |
| `display.show_location` | `true` | Muestra la ciudad en la cabecera y el lugar de cada evento. |
| `display.anti_ghosting` | `"full"` | `"double"` pinta primero la pantalla en negro y luego el dashboard: menos restos de la página anterior, a costa de un flash extra. |
| `debug.log_timings` | `false` | Escribe en `koreader/crash.log` una línea `[dashboard] suspend …` con el origen, el error y los tiempos por etapa. |

Los valores fuera de rango se ajustan al límite más cercano y quedan registrados como advertencia en `crash.log`. Las claves desconocidas se ignoran. Si el JSON está mal escrito, el plugin usa los valores por defecto **sin tocar tu archivo**, para que puedas corregirlo.

`provider`, `fallback` y `direct.*` se aceptan y se conservan, pero aún no tienen efecto.

## Menú *Herramientas → Dashboard de suspensión*

- **Activar dashboard**: activa o desactiva el plugin. Al activarlo avisa si la pantalla de suspensión nativa no está en "Desactivada".
- **Vista previa ahora**: muestra el dashboard con los datos guardados, sin suspender. Un toque lo cierra.
- **Refrescar datos ahora**: pide datos al backend sin el límite de 3 s y dice si funcionó o por qué falló.
- **Ver estado del caché**: antigüedad y origen de los datos, último error y últimos tiempos.

## Estrategia de pantalla de suspensión

El plugin se engancha al evento de suspensión de KOReader (`onSuspend`). Para que su pantalla no se mezcle con la nativa, la pantalla de suspensión de KOReader debe estar en **Desactivada**.

> **Pendiente de confirmar en el dispositivo** (tarea 1.1 del spike): si en tu Kindle la pantalla nativa se pinta encima del dashboard, habrá que cambiar el punto de enganche para reemplazar el screensaver nativo. Sólo cambia `main.lua`; el resto del plugin es el mismo.

## Qué verás en el pie

| Pie | Significado |
|-----|-------------|
| `En vivo` | Datos recién obtenidos o confirmados por el servidor. |
| `Datos de hace N min` | Datos guardados recientes; no hizo falta pedirlos. |
| `Sin conexión · datos de hace N h` | No había Wi-Fi; se muestra lo guardado. |
| `Servidor lento · datos de hace N h` | El backend no respondió a tiempo. |
| `⚠ Datos de hace N h` | Los datos tienen más de `stale_after_s`. |
| `Configura el backend` | Falta `backend.url`. |
| `Token inválido` | El backend respondió 401 o 403: revisa `backend.token`. |
| `Servidor HTTP 503` | El backend respondió con un error. |
| `Respuesta inválida` / `Versión incompatible` | La respuesta no cumple el contrato (¿portal cautivo del Wi-Fi?). |

Sin datos guardados ni red se muestra la fecha, la batería y "Sin datos: conéctate a Wi-Fi para actualizar".

## Problemas frecuentes

- **No aparece el menú**: comprueba que la carpeta se llama exactamente `dashboardscreensaver.koplugin` y está dentro de `koreader/plugins/`. Mira `koreader/crash.log`.
- **Al suspender sale la pantalla normal**: `enabled` está en `false`, o el plugin falló. Busca `[dashboard] suspend failed` en `crash.log`.
- **Siempre "Sin conexión"**: el Kindle apaga el Wi-Fi al suspender; el plugin nunca lo enciende ni espera a que conecte. Los datos se actualizan cuando hay Wi-Fi activo al suspender.
- **Quiero ver los tiempos**: pon `debug.log_timings` en `true` y busca las líneas `[dashboard] suspend` en `crash.log`.

## Desinstalar / volver atrás

1. Desactiva el plugin desde el menú (o pon `"enabled": false`), o borra la carpeta `dashboardscreensaver.koplugin`.
2. Restaura *Pantalla de suspensión* al tipo que tenías.
3. Opcional: borra `koreader/settings/dashboardscreensaver/` y `koreader/cache/dashboardscreensaver/`.

## Desarrollo

Los tests usan busted sobre Lua 5.1 (la misma semántica que LuaJIT de KOReader) y corren en Docker:

```bash
cd plugin
docker build -f Dockerfile.test -t kodash-busted .   # una sola vez
./test.sh                                            # todos los tests
./test.sh spec/orchestrator_spec.lua                 # uno solo
```

- `dashboard/` contiene la lógica; `dashboard_widget.lua` y `main.lua` son la única parte que depende de KOReader.
- Regla de dependencias, verificada por `spec/architecture_spec.lua`: la vista, el view model y el caché no pueden requerir módulos de red ni de proveedores.
- Los widgets y `main.lua` se prueban con stubs de KOReader (`spec/support/kostubs.lua`). Eso detecta errores de ejecución y desbordes de layout, pero **no sustituye** a probarlo en el emulador de KOReader o en el Kindle.
- Los iconos se generan con `python tools/make_icons.py` (requiere Pillow); están dibujados en el propio script, sin recursos externos.
- Los módulos del plugin se requieren siempre **al principio** de cada archivo: KOReader sólo añade la carpeta del plugin a `package.path` mientras carga `main.lua`.
