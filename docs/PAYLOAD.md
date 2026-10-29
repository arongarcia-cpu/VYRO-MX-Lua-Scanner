# Contrato de datos — revisión del escáner

## Datos emitidos por Luau

El escáner genera, entre otros: `uid`, `event_id`, `egg_name`, `egg_type`, `pet_name`, `rarity`, `biome`, `scale`, `asset_scale`, `visual_scale`, `mutations`, `fingerprint`, `position`, `timestamp`, `job_id`, `source`, `source_confidence`, `identity_source`, `identity_confidence`, `nest_index`, `restock_generation`, `area_state` y `per_second` si existe.

El snapshot incorpora métricas agregadas de escaneo y contexto del servidor. Estas métricas no deben confundirse con las detecciones comerciales aceptadas.

## Datos que prepara el backend

Los grupos visibles pueden incluir `best_scale`, `best_job_id`, `server_count`, `variants`, `quality_score`, `quality_reason`, `cycle_generation`, `preview_asset_id`, `income_per_sec`, `estimated_per_second`, `income_exact`, `income_estimate_partial` y `income_source`.

Las variantes individuales llevan su propio `job_id`, `spawn_id`, escala, mutaciones, estado y tiempos. La app debe presentar los datos **ya autorizados** por el backend.

## Convenciones de confiabilidad

- Distinguir `asset_scale` observada de tamaño visual/modelo y de peso en kilogramos.
- Una ganancia estimada no es observación exacta; identificar su procedencia.
- Mutaciones múltiples deben preservarse como arreglo, no concatenarse antes de validar.
- No interpretar el vector vacío de mutaciones como «ninguna mutación» si la observación es desconocida.
- El identificador de deduplicación debe incorporar contexto suficiente (trabajo, aparición y generación/ciclo cuando proceda).
- Los datos no confirmados por ACK no deben contabilizarse como aceptados.
