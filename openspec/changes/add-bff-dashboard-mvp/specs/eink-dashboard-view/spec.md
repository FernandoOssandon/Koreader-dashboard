## Purpose

Definir qué muestra la pantalla del dashboard y cómo se pinta en tinta electrónica para que sea legible durante horas, sin ghosting y con independencia del origen de los datos.

## ADDED Requirements

### Requirement: Contenido de la pantalla
El dashboard SHALL mostrar, de arriba abajo: cabecera con el día de la semana y la fecha en español derivados de los datos (p. ej. "Miércoles 23 de septiembre"), junto a la ubicación y "Actualizado HH:MM"; sección de clima con icono, temperatura actual, descripción, mínima y máxima, probabilidad de lluvia y, si está activado, hasta 4 franjas horarias; sección "Agenda de hoy" con los eventos (primero "Todo el día", después con rango "HH:MM–HH:MM", y el lugar en una segunda línea si está activado); y un pie con el estado de los datos a la izquierda y la batería a la derecha ("Batería 78%", con indicador de carga si corresponde). La pantalla MUST NOT mostrar la hora actual como reloj.

#### Scenario: Pantalla completa con datos en vivo
- **WHEN** se pinta el dashboard con clima y 3 eventos recién obtenidos
- **THEN** se ven la cabecera con fecha y "Actualizado", el clima, los 3 eventos en orden y el pie con "En vivo" y la batería

#### Scenario: Sin eventos
- **WHEN** los datos indican que no hay eventos hoy
- **THEN** la sección de agenda muestra "Sin eventos hoy"

#### Scenario: Batería no disponible
- **WHEN** el dispositivo no puede informar el nivel de batería
- **THEN** el pie muestra "Batería —" y el resto de la pantalla se pinta normalmente

### Requirement: Refresco completo de tinta electrónica
El dashboard SHALL pintarse con un único refresco completo con flash sobre toda la pantalla, garantizando que el pintado termina antes de que el dispositivo duerma. Con `anti_ghosting` igual a `double`, SHALL pintar primero la pantalla entera en negro y luego el dashboard, ambos con refresco completo.

#### Scenario: Sin restos de la página anterior
- **WHEN** el usuario suspende desde una página de texto denso
- **THEN** el dashboard se ve sin restos visibles de esa página

#### Scenario: Modo anti-ghosting reforzado
- **WHEN** `anti_ghosting` es `double` y el dispositivo se suspende
- **THEN** la pantalla hace un flash negro y después muestra el dashboard

### Requirement: Legibilidad en E-Ink
Las superficies grandes SHALL ser blanco o negro puros, sin fondos grises ni degradados. Las líneas separadoras MUST medir al menos 2 px físicos y el texto al menos 14 pt escalados a la densidad de la pantalla. La fecha y la temperatura actual MUST ir en negrita, a 30 pt o más.

#### Scenario: Modo noche
- **WHEN** KOReader está en modo noche y se muestra el dashboard
- **THEN** la pantalla aparece invertida sin halos grises alrededor de iconos ni de texto

### Requirement: Adaptación a la pantalla
El layout SHALL escalarse a la resolución y densidad del dispositivo (de 600×800 a 1264×1680, en vertical) sin que ningún texto se salga de los márgenes. Los títulos de eventos que no quepan MUST truncarse con "…". Si no caben todas las filas de la agenda, las que sobren se reemplazan por "+N más". En orientación horizontal se muestra el mismo contenido sin las franjas horarias.

#### Scenario: Pantalla pequeña con agenda llena
- **WHEN** el dispositivo es de 600×800 y hay 8 eventos con títulos de 60 caracteres
- **THEN** ningún texto sale de los márgenes y las filas que no caben se resumen como "+N más"

### Requirement: Independencia del origen de los datos
La vista SHALL construirse exclusivamente a partir del contrato de datos del dashboard y del estado local del dispositivo, y MUST NOT depender del mecanismo de obtención de los datos (red, fuente concreta, formato de origen). Esta regla se verifica automáticamente en los tests.

#### Scenario: Mismo resultado con cualquier fuente
- **WHEN** se pinta el mismo conjunto de datos del contrato con fuente `backend` y con fuente `direct`
- **THEN** ambas pantallas son idénticas salvo el indicador de fuente del pie
