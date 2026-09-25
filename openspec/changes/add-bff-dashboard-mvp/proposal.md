## Why

Al suspender el Kindle, la pantalla E-Ink queda congelada durante horas sin consumir energía, pero hoy sólo muestra una portada. Aprovechar ese momento para mostrar el clima y la agenda del día convierte el lector en un panel de información de consumo casi nulo. La Fase 1 entrega un MVP funcional de extremo a extremo con el modo más rápido y barato en batería: un backend intermediario (BFF) que entrega todo en un solo JSON pequeño.

## What Changes

- Nuevo microservicio **Dashboard BFF** que consolida el clima (Open-Meteo) y uno o más calendarios iCal, normaliza la zona horaria y expone `GET /api/dashboard` (JSON < 2 KB, ETag/304, token Bearer) y `GET /healthz`.
- Definición del **contrato de datos canónico v1** (DTO) que cualquier fuente de datos debe producir y que la vista consume.
- Nuevo **plugin de KOReader** `dashboardscreensaver.koplugin` que:
  - intercepta la suspensión y muestra el dashboard con refresco E-Ink completo, respetando un presupuesto total de 3.0 s;
  - hace una sola llamada HTTP acotada (connect ≤ 1.0 s, total ≤ 2.2 s, tope 2.5 s) y sólo si el caché no es reciente;
  - persiste la última respuesta válida en `dashboard_cache.json` para el modo avión o sin conexión;
  - degrada siempre (live → caché → pantalla mínima) y nunca bloquea la suspensión;
  - cierra el dashboard y repinta la UI al despertar.
- Configuración del plugin en `settings.json`, editable a mano. El menú completo queda para la Fase 2; en esta fase sólo hay un menú mínimo: activar, vista previa, refrescar y estado.
- Spike técnico en el dispositivo real para fijar el punto de integración con la suspensión y la disponibilidad de red.

## Capabilities

### New Capabilities
- `dashboard-bff-api`: endpoint HTTP del backend que entrega el snapshot consolidado de clima + agenda, con autenticación, caché condicional y degradación ante fallos de los upstreams.
- `dashboard-data-contract`: estructura canónica v1 de los datos del dashboard, sus límites y las reglas de validación y normalización en el cliente.
- `suspend-dashboard`: comportamiento del plugin durante la suspensión y el despertar (presupuesto temporal, uso de red, orden de fallback, tolerancia a errores).
- `dashboard-cache`: persistencia local de la última respuesta válida y cálculo de su frescura.
- `eink-dashboard-view`: contenido, layout y refresco de la pantalla E-Ink del dashboard.
- `plugin-configuration`: carga, valores por defecto, validación de rangos y protección del archivo `settings.json`.

### Modified Capabilities
<!-- Ninguna: proyecto nuevo. -->

## Impact

- **Código nuevo:** `backend/` (servicio Python + Docker) y `plugin/dashboardscreensaver.koplugin/`.
- **Dependencias externas:** Open-Meteo (API pública, sin auth) y feeds iCal privados, a los que sólo accede el backend.
- **Dispositivo:** requiere un Kindle con KOReader que permita pantalla de suspensión propia (sin "Ofertas especiales"). Según el spike, puede requerir poner "Pantalla de suspensión" de KOReader en "Desactivada".
- **Red doméstica:** el backend debe ser alcanzable desde el Kindle (IP fija o reserva DHCP recomendada).
- **Fases siguientes:** `refactor-data-provider-abstraction` y `add-standalone-direct-provider` construyen sobre las capacidades creadas aquí; esta change debe archivarse antes de empezarlas.
