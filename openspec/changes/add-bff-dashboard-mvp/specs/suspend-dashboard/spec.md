## Purpose

Mostrar el dashboard en la pantalla E-Ink cada vez que el lector se suspende, con datos lo más frescos posible y sin retrasar nunca la suspensión ni vaciar la batería.

## ADDED Requirements

### Requirement: Mostrar el dashboard al suspender
Cuando el plugin está activado y el dispositivo entra en suspensión, el plugin SHALL mostrar el dashboard a pantalla completa en lugar de la pantalla de suspensión nativa de KOReader. Cuando el plugin está desactivado, MUST NOT intervenir en la suspensión ni hacer peticiones de red.

#### Scenario: Camino feliz con red
- **WHEN** hay Wi-Fi conectado, el caché tiene más de 10 minutos y el usuario presiona el botón de encendido
- **THEN** en menos de 3 segundos se ve el dashboard con fecha, clima, agenda y batería
- **AND** el pie indica "En vivo"

#### Scenario: Plugin desactivado
- **WHEN** `enabled` es `false` y el dispositivo se suspende
- **THEN** se muestra la pantalla de suspensión nativa de KOReader y no se hace ninguna petición HTTP

### Requirement: Presupuesto temporal de suspensión
El plugin SHALL devolver el control a KOReader en 3.0 s o menos desde que empieza la suspensión, en cualquier condición de red y de datos. La petición de red MUST tener un timeout de conexión de 1.0 s como máximo y un timeout total de 2.2 s por defecto, configurable y nunca mayor a 2.5 s. Además, el tiempo asignado a la red MUST dejar al menos 0.7 s para pintar; si quedan menos de 0.5 s para la red, no se intenta.

#### Scenario: Servidor colgado
- **WHEN** el backend acepta la conexión pero nunca responde y existe un caché de hace 1 hora
- **THEN** el dashboard se muestra desde el caché
- **AND** el control vuelve a KOReader en 3.0 s o menos

#### Scenario: Servidor inalcanzable
- **WHEN** la IP del backend no responde a la conexión TCP
- **THEN** la conexión se abandona a los 1.0 s como máximo y se muestra el caché

### Requirement: Uso de red mínimo
El plugin SHALL hacer como máximo una petición HTTP por suspensión, SHALL NOT hacer ninguna si el caché fue confirmado hace menos de `min_refresh_interval_s` (600 s por defecto) y MUST NOT encender el Wi-Fi ni esperar a que conecte. Si tiene datos en caché, SHALL enviar su ETag como petición condicional. No hay reintentos dentro de una misma suspensión.

#### Scenario: Caché reciente evita la red
- **WHEN** el caché fue confirmado hace 3 minutos y el dispositivo se suspende
- **THEN** no se hace ninguna petición HTTP y el dashboard aparece en menos de 1 segundo

#### Scenario: Modo avión
- **WHEN** el Wi-Fi está apagado, existe un caché de hace 2 horas y el dispositivo se suspende
- **THEN** el Wi-Fi sigue apagado, no se hace ninguna petición, el dashboard aparece desde el caché en menos de 1 segundo
- **AND** el pie indica "Sin conexión · datos de hace 2 h"

#### Scenario: Datos sin cambios
- **WHEN** el caché tiene el mismo ETag que el servidor y fue confirmado hace 20 minutos
- **THEN** el servidor responde 304, se muestra el caché, su hora de confirmación pasa a ser la actual y el pie indica "En vivo"

### Requirement: Orden de degradación
El plugin SHALL elegir la pantalla en este orden: datos recién obtenidos; si no, el último caché válido con indicación de antigüedad; si no, una pantalla mínima con la fecha del dispositivo, la batería y el texto "Sin datos: conéctate a Wi-Fi para actualizar". Una respuesta no válida (timeout, error TLS, 401/403, otro status no exitoso, más de 8192 bytes, tipo de contenido distinto de JSON, JSON inválido o contrato incompatible) MUST NOT reemplazar ni borrar el caché existente.

#### Scenario: Portal cautivo
- **WHEN** la red responde 200 con `Content-Type: text/html`
- **THEN** se muestra el caché anterior sin modificarlo y el pie indica "Respuesta inválida"

#### Scenario: Token rechazado
- **WHEN** el backend responde 401
- **THEN** se muestra el caché y el pie indica "Token inválido"

#### Scenario: Primera ejecución sin red ni caché
- **WHEN** no existe caché y el Wi-Fi está apagado
- **THEN** se muestra la fecha del dispositivo, la batería y "Sin datos: conéctate a Wi-Fi para actualizar"

#### Scenario: Backend sin configurar
- **WHEN** la URL del backend está vacía
- **THEN** no se hace ninguna petición y el pie indica "Configura el backend"

### Requirement: Tolerancia a errores internos
Ningún error del plugin SHALL impedir o retrasar más allá del presupuesto la suspensión del dispositivo. Si falla incluso la pantalla mínima, el plugin MUST NOT mostrar nada, SHALL registrar el error en el log y KOReader continúa con su comportamiento por defecto.

#### Scenario: Excepción al construir la pantalla
- **WHEN** ocurre una excepción al construir el dashboard
- **THEN** el dispositivo se suspende normalmente y el log contiene "[dashboard] suspend failed"

### Requirement: Salida limpia al despertar
Al despertar, el plugin SHALL cerrar el dashboard y repintar la interfaz subyacente con refresco completo.

#### Scenario: Despertar
- **WHEN** el dashboard está visible y el usuario despierta el dispositivo
- **THEN** el dashboard desaparece y la página de lectura se repinta con refresco completo, sin restos del dashboard

### Requirement: Confidencialidad en logs
El plugin MUST NOT escribir en el log el token del backend.

#### Scenario: Log de una suspensión con error de autenticación
- **WHEN** una suspensión termina con error 401 y los tiempos por etapa están activados
- **THEN** `crash.log` contiene el código de error y los tiempos, pero no el token

### Requirement: Acciones interactivas de diagnóstico
El plugin SHALL ofrecer en el menú de KOReader: activar o desactivar el dashboard, "Vista previa ahora" (muestra el dashboard sin suspender y se cierra con un toque), "Refrescar datos ahora" (obtiene datos sin el presupuesto de suspensión e informa del resultado) y "Ver estado del caché" (antigüedad, origen, último error y últimos tiempos).

#### Scenario: Vista previa
- **WHEN** el usuario elige "Vista previa ahora"
- **THEN** se muestra el dashboard con los datos actuales y un toque lo cierra

#### Scenario: Refresco manual con error
- **WHEN** el usuario elige "Refrescar datos ahora" y el backend responde 503
- **THEN** se muestra un mensaje con el error legible y el caché no cambia
