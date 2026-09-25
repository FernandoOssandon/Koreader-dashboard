## Purpose

Conservar en el dispositivo la última respuesta válida del dashboard, para que siempre haya algo útil que mostrar sin red, y medir cuán actuales son esos datos.

## ADDED Requirements

### Requirement: Persistencia de la última respuesta válida
El plugin SHALL guardar en disco (`dashboard_cache.json`) cada conjunto de datos válido recibido, junto con su ETag, la fuente que lo produjo, el momento en que se guardó y el momento de la última confirmación de la fuente. La escritura MUST ser atómica: un corte de energía durante la escritura no puede dejar un caché ilegible que reemplace al anterior. Si la fuente confirma que no hubo cambios, sólo se actualiza el momento de confirmación.

#### Scenario: Guardado tras respuesta nueva
- **WHEN** el backend responde 200 con datos válidos
- **THEN** el caché contiene esos datos, su ETag y la hora de confirmación actual

#### Scenario: Corte durante la escritura
- **WHEN** el proceso se interrumpe mientras se escribe el caché
- **THEN** en la siguiente lectura se obtiene el caché anterior completo o el nuevo completo, nunca uno parcial

### Requirement: Caché corrupto
Si el caché no puede leerse, no es JSON válido, tiene otra versión de formato o sus datos no cumplen el contrato, el plugin SHALL eliminarlo y tratarlo como ausente.

#### Scenario: Archivo truncado
- **WHEN** `dashboard_cache.json` está truncado, el Wi-Fi está apagado y el dispositivo se suspende
- **THEN** el archivo se elimina y se muestra la pantalla mínima

### Requirement: Niveles de frescura
La antigüedad del caché SHALL medirse desde su última confirmación. El nivel es `fresh` si la antigüedad es menor a `stale_after_s` (3 h por defecto), `stale` hasta `max_age_s` (24 h por defecto) y `expired` desde ahí. También es `expired` si la fecha de los datos no coincide con la fecha actual del dispositivo, o si la hora de confirmación está en el futuro. Con `stale`, la pantalla SHALL indicar la antigüedad. Con `expired`, SHALL ocultar la agenda con el texto "Agenda desactualizada" y mantener el clima con la advertencia de antigüedad.

#### Scenario: Datos de hace 5 horas
- **WHEN** el caché se confirmó hace 5 horas y no hay red
- **THEN** el pie indica "⚠ Datos de hace 5 h" y la agenda se muestra

#### Scenario: Datos de ayer
- **WHEN** la fecha de los datos del caché es de ayer y no hay red
- **THEN** la agenda muestra "Agenda desactualizada" y el clima se muestra con el aviso de antigüedad

#### Scenario: Reloj del dispositivo corregido hacia atrás
- **WHEN** la hora de confirmación del caché es posterior a la hora actual del dispositivo
- **THEN** el caché se trata como `expired` pero se sigue mostrando
