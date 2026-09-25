## 1. Interfaz y suite de contrato

- [ ] 1.1 Crear `dashboard/data_provider.lua` con la clase base, `getCachedData` por defecto, `isConfigured` y `assertImplements` (design D1). Verificación: tests busted de `assertImplements` con un objeto válido y otro al que le falta `fetchData`
- [ ] 1.2 Crear la suite de contrato compartida `spec/provider_contract_spec.lua` (design D5). Verificación: la suite falla con un proveedor de prueba que llama a los dos callbacks o se excede del tiempo

## 2. BackendProvider y fábrica

- [ ] 2.1 Renombrar `backend_client.lua` a `provider_backend.lua` como `BackendProvider` (`id = "backend"`) sin cambiar su comportamiento. Verificación: los tests de la tarea 6.2 de la Fase 1 y la suite de contrato pasan sobre `BackendProvider`
- [ ] 2.2 Crear `dashboard/provider_factory.lua` con `UnconfiguredProvider` para `direct`. Verificación: tests busted para `provider = backend`, `provider = direct` y un valor desconocido (→ backend con advertencia)
- [ ] 2.3 Inyectar el proveedor en `orchestrator.lua` y reconstruirlo cuando cambie la configuración, fuera de `runSuspend`. Verificación: test busted que cambia `provider` y comprueba que la siguiente `runSuspend` usa el nuevo proveedor

## 3. Configuración persistente

- [ ] 3.1 Implementar `ConfigStore:set`, `save` (atómico, conservando claves no gestionadas) y la notificación `on_change`. Verificación: test busted con `debug.log_timings: true` que sobrevive a un `set("backend.url", ...)` + `save()`
- [ ] 3.2 Pedir confirmación antes del primer `save()` si el archivo original era JSON inválido. Verificación: test busted con un archivo inválido, en el que no se escribe nada sin confirmar

## 4. Menú de ajustes

- [ ] 4.1 Implementar `dashboard/settings.lua` con todas las entradas del spec `plugin-settings-menu` e integrar el menú mínimo de la Fase 1. Verificación: en el emulador, cada entrada modifica `settings.json` y los `SpinWidget` no permiten salir de rango
- [ ] 4.2 Añadir el token con `text_type = "password"` y revisar los logs. Verificación: en el emulador el token se ve enmascarado; `grep` del token en `crash.log` sin resultados
- [ ] 4.3 Implementar "Probar conexión" y "Borrar caché". Verificación: en el emulador, "OK · N ms · N KB" con el backend activo, "Token inválido" con un token incorrecto y el caché ausente tras borrarlo

## 5. Verificación de aceptación

- [ ] 5.1 [dispositivo] Volver a ejecutar todos los escenarios de aceptación de la Fase 1 con `provider = backend`. Verificación: resultados en `findings/regression.md` sin diferencias
- [ ] 5.2 [dispositivo] Ejecutar los escenarios de `data-provider-selection` y `plugin-settings-menu` en el Kindle. Verificación: resultados en `findings/acceptance.md`
- [ ] 5.3 Ejecutar `openspec validate refactor-data-provider-abstraction --strict` y `busted`. Verificación: todo en verde; la change queda lista para `openspec archive`
