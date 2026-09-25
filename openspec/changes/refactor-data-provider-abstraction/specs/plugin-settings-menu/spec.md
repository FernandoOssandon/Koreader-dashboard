## Purpose

Permitir configurar el dashboard por completo desde el menú de KOReader en el propio Kindle, sin editar archivos, y diagnosticar la conexión con el proveedor.

## ADDED Requirements

### Requirement: Menú de ajustes
El plugin SHALL ofrecer en el menú de KOReader: activar o desactivar; elegir el proveedor (Backend / Directo); para el backend, URL, token y timeout total (de 0.5 a 2.5 s); para el caché, intervalo mínimo de refresco, "datos viejos tras" y "caducan tras"; para la pantalla, máximo de eventos, pronóstico horario sí/no, lugar del evento sí/no y anti-ghosting (normal/doble); además de "Vista previa ahora", "Refrescar datos ahora", "Ver estado del caché", "Probar conexión" y "Borrar caché". Cada cambio SHALL persistirse en `settings.json`.

#### Scenario: Cambiar la URL
- **WHEN** el usuario edita la URL del backend en el menú y confirma
- **THEN** `settings.json` contiene la nueva URL y la siguiente suspensión la usa sin reiniciar KOReader

#### Scenario: Valor fuera de rango en el menú
- **WHEN** el usuario intenta poner el timeout total en 4 s
- **THEN** el selector no permite valores por encima de 2.5 s

#### Scenario: Borrar caché
- **WHEN** el usuario elige "Borrar caché" y confirma
- **THEN** `dashboard_cache.json` se elimina y "Ver estado del caché" indica que no hay caché

### Requirement: Token enmascarado
El token del backend MUST mostrarse enmascarado en el menú y MUST NOT aparecer en ningún log ni mensaje.

#### Scenario: Editar el token
- **WHEN** el usuario abre el ajuste del token
- **THEN** el valor se muestra enmascarado y no aparece en `crash.log`

### Requirement: Probar conexión
"Probar conexión" SHALL hacer una petición al proveedor activo sin el presupuesto de suspensión y mostrar el resultado: el código o error legible, la latencia en milisegundos y el tamaño de la respuesta. Si la respuesta es válida, MUST actualizar el caché.

#### Scenario: Conexión correcta
- **WHEN** el backend está disponible y el usuario pulsa "Probar conexión"
- **THEN** se muestra un mensaje del tipo "OK · 184 ms · 1.3 KB" y el caché se actualiza

#### Scenario: Token inválido
- **WHEN** el backend responde 401 a "Probar conexión"
- **THEN** se muestra "Token inválido" y el caché no cambia
