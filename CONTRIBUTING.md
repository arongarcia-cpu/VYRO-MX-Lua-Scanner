# Contribuciones

Se aceptan propuestas para revisión técnica, especialmente mejoras de confiabilidad, métricas, deduplicación, manejo de errores y rendimiento.

Antes de enviar un PR:

- No incluir claves, configuraciones reales, rutas privadas, datos de usuarios ni registros de producción.
- Describir el problema con un caso de prueba reproducible y datos sintéticos.
- Presentar un cambio mínimo, sus riesgos y un plan de rollback.
- No ejecutar pruebas contra servicios en producción.
- No asumir que un ACK de un servicio intermedio equivale a aparición visible en cliente.

Las contribuciones no autorizan despliegues ni uso del código fuera de revisión.
