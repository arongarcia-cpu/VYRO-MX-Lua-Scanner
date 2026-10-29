# Checklist para auditoría externa

**Escaneo e identidad**
- [ ] Revisar `scanNow`, fase temprana, estabilización y reintentos.
- [ ] Confirmar los modelos válidos y las mutaciones en cada zona.
- [ ] Medir falsos negativos y falsos positivos con muestras controladas.
- [ ] Revisar campos de identidad, UID, fingerprints y conflictos de zona.
- [ ] Comparar distintas configuraciones de rendimiento sin asumir equivalencia.

**Transporte**
- [ ] Trazar detección -> envío -> NodeAgent -> ACK -> persistencia -> cliente.
- [ ] Examinar `send_all`, serialización y snapshots repetidos.
- [ ] Auditar reintentos y rechazo de carga sin perder apariciones.
- [ ] Revisar deduplicación por `job_id` / `spawn_id` / generación de ciclo.
- [ ] Medir los percentiles p50, p95 y p99 de cada etapa.

**Aplicaciones**
- [ ] Mantener whitelist y autorización por tier en servidor.
- [ ] Enviar tarjetas listas y cambios incrementales al frontend.
- [ ] Garantizar consistencia de caché, resincronización y eliminaciones.

**Validación**
- [ ] Ensayar una única cuenta en entorno autorizado y aislado.
- [ ] Hacer comparativa A/B durante ciclos completos.
- [ ] Demostrar rollback de archivo **y sesión Lua cargada**.
- [ ] No desplegar PR automáticamente ni editar credenciales.
- [ ] Entregar evidencia y evaluación de impacto antes de fusionar.
