# VYRO MX — Lua Scanner Runtime

**Copia pública de revisión del escáner Luau.** Este repositorio documenta el escaneo de huevos, la validación de identidad, el filtrado de candidatos y la entrega al backend. Su finalidad es permitir auditorías de estabilidad, rendimiento y confiabilidad por desarrolladores externos.

> Snapshot exportado el 29 de octubre de 2026. No contiene credenciales, configuraciones de producción ni datos operativos. **No es un paquete listo para desplegar.**

## Archivos

- `runtime/VYRO_PRIME_RUNTIME_REVIEW.lua`: runtime restaurado auditado, con URL remota sustituida por un ejemplo inválido.
- `reference/VYRO_PRIME_RUNTIME_VOLT.lua`: variante anterior para comparación; no se afirma que siga desplegada.
- `docs/PIPELINE.md`: flujo de detecciones y arquitectura funcional.
- `docs/WHITELIST.md`: lista de objetivos autorizados por la política del Buyer, utilizada como referencia de auditoría.
- `docs/PAYLOAD.md`: campos enviados por el Lua y datos presentados por el backend.
- `docs/REVIEW_CHECKLIST.md`: tareas de revisión y pruebas recomendadas.
- `examples/sample_snapshot.json`: ejemplo totalmente ficticio, no una captura real.
- `config.example.json`: valores de prueba, nunca credenciales reales.

## Flujo simplificado

```text
WorldEggs / Roblox -> Runtime Luau -> NodeAgent local
-> validación, deduplicación, política whitelist -> feed por licencia
-> apps web, Windows y Android
```

El Lua contiene lógica de captura, normalización, metadatos y reintentos. La política final de visibilidad por licencia se aplica del lado servidor; no debe confiarse a la interfaz.

## Qué queremos mejorar

1. Recuperar falsos negativos en los escaneos sin generar más falsos positivos.
2. Identificar dónde desaparecen detecciones entre Lua, ACK del NodeAgent y app.
3. Evitar reenvíos de snapshots duplicados y procesamiento de carga redundante.
4. Hacer que el backend distribuya eventos incrementales y grupos listos para mostrar.
5. Reducir bloqueos entre procesos de escaneo, reservas y entrega de eventos.

En cada propuesta incluir evidencia reproducible, impacto, una prueba aislada y rollback. **No modificar producción con el contenido de este repositorio.**

## Requisitos para analizar

Es código **Luau**, no Lua estándar; utiliza APIs de Roblox y funciones disponibles en determinados entornos de ejecución. Para análisis estático, revisar los dos archivos `.lua`. No se requieren claves reales para revisar contratos de datos, deduplicación o lógica de validación.

Los valores de servidor remoto fueron reemplazados por `https://example.invalid`. `127.0.0.1:8790` identifica un servicio local de ejemplo en el código. La integración real necesita configuración fuera del repositorio.

## Acceso y licencia

Este repositorio es **público para lectura y revisión**. Público **no implica** que el código sea software de licencia abierta: consultar `LICENSE`. Las contribuciones deben evitar secretos y datos personales.

Proyecto VYRO MX. Este repositorio no está afiliado ni respaldado por Roblox.
