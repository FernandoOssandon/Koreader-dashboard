# Backend del dashboard (BFF)

Servicio que junta el clima (Open-Meteo) y tu agenda (feeds `.ics`) en un único JSON de menos de 2 KB. El plugin de KOReader lo pide una sola vez cada vez que el Kindle se suspende.

Responde desde memoria (~2 ms), así que no depende de que Open-Meteo o tu calendario estén rápidos en ese momento.

## Requisitos
- Un equipo que esté siempre encendido en tu red (Raspberry Pi, mini PC, NAS o VPS) con **Docker** y Docker Compose.
- Las URLs secretas `.ics` de tus calendarios (ver abajo).

## Puesta en marcha

```bash
cd backend
cp .env.example .env
# edita .env: como mínimo DASH_TOKEN, DASH_ICS_URLS y tu ubicación
docker compose up -d --build
docker compose ps          # el estado debe pasar a "healthy"
```

Comprueba que responde (cambia `TOKEN` y la IP):

```bash
curl http://localhost:8080/healthz
curl -H "Authorization: Bearer TOKEN" http://localhost:8080/api/dashboard
```

Para generar un token: `python -c "import secrets; print(secrets.token_urlsafe(24))"`.

## Configuración (`.env`)

| Variable | Por defecto | Descripción |
|----------|-------------|-------------|
| `DASH_TOKEN` | — (obligatoria) | Token Bearer que debe enviar el Kindle. Sin él, el servicio no arranca. |
| `DASH_TZ` | `America/Santiago` | Zona horaria IANA. Define qué es "hoy" y las horas de la agenda. |
| `DASH_LAT`, `DASH_LON` | Santiago | Ubicación del clima. |
| `DASH_LOCATION_NAME` | `Santiago` | Nombre que se muestra junto al clima. |
| `DASH_ICS_URLS` | vacío | URLs `.ics` separadas por coma. Sin ellas la agenda aparece como "no disponible". |
| `DASH_WEATHER_REFRESH_S` | `900` | Cada cuánto se pide el clima (mínimo 60). |
| `DASH_CALENDAR_REFRESH_S` | `300` | Cada cuánto se descargan los calendarios (mínimo 60). |
| `DASH_MAX_EVENTS` | `8` | Máximo de eventos que devuelve (1 a 8). |
| `DASH_PORT` | `8080` | Puerto publicado en el equipo. |

## Cómo obtener la URL `.ics` secreta

**Google Calendar**
1. Abre Google Calendar en el navegador, en el equipo.
2. Junto al calendario que quieres: ⋮ → *Configuración y uso compartido*.
3. En *Integrar el calendario*, copia la **Dirección secreta en formato iCal**.

**iCloud**
1. En Calendario (Mac) o en iCloud.com, pulsa el icono de compartir del calendario.
2. Activa *Calendario público* y copia el enlace. Cambia `webcal://` por `https://`.

> ⚠️ Esa URL da acceso de lectura a todo el calendario a quien la tenga. Ponla solo en `.env`, no la subas a git (`.env` ya está en `.gitignore`) ni la compartas. Si se filtra, restablécela desde Google Calendar (*Restablecer*).

Puedes poner varios calendarios separándolos con coma. Si uno falla, el backend usa los demás y lo avisa en `warnings`.

## Red: IP fija y HTTP frente a VPN

- **IP estable.** El Kindle guarda la dirección del backend. Reserva una IP en tu router (reserva DHCP) para el equipo del backend, o asígnale una IP fija. Poner una IP en vez de un nombre también evita la resolución DNS, que cuesta tiempo cuando el Kindle se suspende.
- **HTTP en la LAN.** Si el backend solo se usa dentro de tu casa, HTTP es suficiente: el token protege datos de poca sensibilidad (clima y agenda) y el handshake TLS cuesta tiempo y batería en un Kindle.
- **Fuera de casa.** No expongas el puerto 8080 a Internet por HTTP. Usa una VPN (WireGuard o Tailscale) y sigue con HTTP dentro de ella, o pon HTTPS delante con un proxy inverso (Caddy o nginx).

## Comprobaciones y diagnóstico

- `GET /healthz` no necesita token y devuelve `status` (`ok` o `degraded`) y la antigüedad en segundos del clima y de la agenda.
- `docker compose logs -f` muestra un JSON por petición (`status`, `latency_ms`, `etag_hit`). El token y las URLs `.ics` nunca se escriben en los logs.
- `503 no_snapshot` justo después de arrancar es normal: el servicio aún no ha descargado nada. Reintenta en unos segundos.
- `401` significa que el token no coincide con `DASH_TOKEN`.
- Si `warnings` incluye `WEATHER_STALE` o `CALENDAR_STALE`, un upstream falló y se está sirviendo el último dato bueno. Pasadas 6 horas esa sección pasa a `null`.

## Desarrollo

```bash
cd backend
python -m venv .venv && .venv/Scripts/activate     # en Linux/macOS: source .venv/bin/activate
pip install -e ".[dev]"
pytest                                             # 72 tests
DASH_TOKEN=dev uvicorn app.main:app --reload
```

El contrato de datos (JSON Schema) está en `tests/schema/dashboard-v1.json`; un test lo compara con los modelos de `app/models.py`.
