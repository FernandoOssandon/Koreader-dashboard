## Purpose

Obtener el clima y la agenda del día directamente desde el Kindle, sin servidor intermediario, produciendo el mismo contrato de datos que el modo backend.

## ADDED Requirements

### Requirement: Clima directo desde Open-Meteo
Con el proveedor `direct`, el plugin SHALL obtener el clima de Open-Meteo con las coordenadas configuradas y la zona horaria que Open-Meteo resuelve para ellas. MUST producir la sección `weather` del contrato v1 con la misma tabla de códigos WMO que el backend, y SHALL usar el desfase horario devuelto por Open-Meteo como hora local para `date`, `weekday` y las horas de la agenda, en lugar de la zona horaria del dispositivo.

#### Scenario: Modo directo con Wi-Fi
- **WHEN** `provider` es `direct` con coordenadas y una URL ICS válidas, y el dispositivo se suspende
- **THEN** el dashboard muestra el clima y los eventos de hoy en menos de 3 segundos y el pie indica la fuente "Directo"

#### Scenario: Kindle con zona horaria incorrecta
- **WHEN** el dispositivo está configurado en UTC y las coordenadas corresponden a Santiago
- **THEN** la fecha y las horas de los eventos se muestran en hora de Santiago

### Requirement: Agenda directa desde iCal
El plugin SHALL descargar cada URL ICS configurada y extraer los eventos que intersectan el día local actual: título (`SUMMARY`, con secuencias de escape resueltas), inicio y fin (`DTSTART`/`DTEND`, o `DURATION` en forma de horas/minutos o días), lugar (`LOCATION`) y todo el día (fechas sin hora). Los eventos cancelados MUST descartarse. Las fechas en UTC SHALL convertirse a la hora local; las fechas flotantes o con `TZID` se interpretan como hora local. El resultado MUST respetar el mismo orden, ventana (eventos no terminados) y límites del contrato v1.

#### Scenario: Evento UTC
- **WHEN** un evento tiene `DTSTART:20260923T170000Z` y la hora local es UTC−3
- **THEN** aparece con `start` "14:00"

#### Scenario: Evento de todo el día
- **WHEN** un evento tiene `DTSTART;VALUE=DATE:20260923`
- **THEN** aparece como "Todo el día"

#### Scenario: Líneas plegadas
- **WHEN** el `SUMMARY` de un evento ocupa dos líneas, la segunda empezando con un espacio
- **THEN** el título aparece completo en una sola línea

### Requirement: Limitaciones declaradas del parser
El parser MUST NOT expandir recurrencias (`RRULE`, `RDATE`, `EXDATE`, `RECURRENCE-ID`): sólo incluye la instancia base si cae hoy y añade el aviso `RRULE_IGNORED`. Un `TZID` distinto de la zona local SHALL interpretarse como hora local, con el aviso `TZID_ASSUMED_LOCAL`. Estas limitaciones MUST estar documentadas en el README y en la ayuda del menú, recomendando el modo backend para calendarios con recurrencias.

#### Scenario: Evento recurrente
- **WHEN** un evento semanal tiene su instancia base hace 2 semanas
- **THEN** no aparece en la agenda y los avisos incluyen `RRULE_IGNORED`

### Requirement: Tolerancia a iCal inválido o grande
El parser SHALL ignorar las líneas que no respeten el formato de contenido iCal, descartar los eventos sin `DTSTART`, tratar un `DTEND` anterior a `DTSTART` como igual a `DTSTART` y descartar un evento sin cierre al final del archivo, con el aviso `ICS_MALFORMED`. MUST procesar el feed línea a línea, sin cargarlo entero en memoria, y detenerse al superar `direct.max_ics_bytes` (512 KB por defecto), conservando los eventos encontrados hasta ahí y añadiendo el aviso `ICS_TRUNCATED`.

#### Scenario: VEVENT sin cierre
- **WHEN** un ICS contiene un evento válido y otro sin `END:VEVENT` al final
- **THEN** se muestra el evento válido y los avisos incluyen `ICS_MALFORMED`

#### Scenario: Feed demasiado grande
- **WHEN** un feed pesa 2 MB
- **THEN** la descarga se detiene a los 512 KB, se muestran los eventos de hoy encontrados hasta ahí y los avisos incluyen `ICS_TRUNCATED`

### Requirement: Degradación parcial
Si falla sólo el clima o sólo la agenda, el proveedor directo SHALL entregar la parte disponible, con la otra sección en `null`. Sólo si fallan ambas MUST entregar un error.

#### Scenario: Calendario caído
- **WHEN** Open-Meteo responde correctamente y la URL ICS responde 404
- **THEN** se muestra el clima actualizado y la agenda indica "Agenda no disponible"

#### Scenario: Todo caído
- **WHEN** Open-Meteo y la URL ICS fallan
- **THEN** el proveedor entrega un error y se muestra el caché
