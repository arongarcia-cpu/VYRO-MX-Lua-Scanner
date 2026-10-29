# Flujo de detección de VYRO MX

```text
[Modelo de huevo en el mundo]
  |- identidad visual/huella/UID
  |- zona, rareza, tamaño, mutaciones
  `-> [Runtime Luau]
          |- observación y validación
          |- snapshot con job_id / event_id
          `-> [NodeAgent local]
                  |- aceptación y ACK
                  |- cola duradera / reintentos
                  `-> [Backend]
                          |- política whitelist y zona
                          |- clasificación y límites por licencia
                          |- deduplicación de apariciones
                          `-> [Feed de clientes]
                                  |- agrupación por mascota y zona
                                  |- variantes por servidor
                                  `-> [Renderizar tarjetas]
```

La arquitectura es una descripción funcional, no una especificación de despliegue. No incluye direcciones ni credenciales de producción.

## Riesgos a revisar

- Un `send_all=true` transmite huevos observados que el backend debe validar. No se recomienda retirarlo sin medir el efecto sobre diagnósticos y detecciones no reconocidas.
- En una versión del runtime, `eggs` y `live_eggs` se construyen desde el mismo arreglo: revisar trabajo y ancho de banda redundantes.
- Reutilizar `event_id` o generar mal el `spawn_id` puede deduplicar apariciones válidas o duplicarlas.
- El ACK de NodeAgent **no equivale necesariamente** a que el dato haya llegado al cliente.
- Observación de un huevo no equivale a whitelist aceptada; ni una reserva equivale a un salto confirmado.
- La app debe limitarse a presentar los datos autorizados y a búsqueda/ordenamiento local. La autorización no puede delegarse a la interfaz.
- Comprobar el estado tras teletransporte, recarga del Lua y pérdida temporal de conexión.

## Métricas por ciclo

`cycle_generation`, `job_id`, `event_id`, `scan_duration_ms`, `whitelist_local`, `node_ack`, `backend_accepted`, `frontend_visible`, `first_observed_at`, `displayed_at`.

Distinguir tasas de transporte, detección y visibilidad usando siempre el mismo ciclo y tier.
