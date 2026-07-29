# Trazabilidad de la conversación

C es Claudia, coordinadora y usuaria operativa. E es Eduardo Espadas.

| Solicitud de la conversación | Cobertura del sistema |
|---|---|
| Seleccionar alumno y obtener grado | Alumnos y búsqueda por matrícula/nombre |
| Mensualidad, estancia y “otros” | Conceptos configurables: constancia, club de tareas, etc. |
| Cobrar y registrar ingreso a la vez | Función transaccional `register_cash_payment` |
| Entregar recibo al padre | Recibo con folio, alumno, grado, concepto, mes y usuario |
| Capturar transferencias manualmente | Ingresos con fecha, ciclo, mes, referencia, monto y cuenta |
| Transferencia sin identificar | Se guarda sin alumno y se asigna posteriormente |
| Pagos parciales, incluso $50 | Aplicaciones a cargos y saldo pendiente acumulable |
| Revisar banco semanalmente | Importación y conciliación de movimientos bancarios |
| Voucher por correo | Adjuntos y anotación de evidencia |
| Formulario de inscripción o alta manual | Alumnos, contactos, alergias e importación CSV |
| Sofia/Sofía, mayúsculas y acentos | Búsqueda normalizada con `unaccent` |
| Septiembre como mes 1 | Meses operativos por ciclo escolar |
| Filtrar renglones acumulados | Tablas filtrables por fecha, alumno, concepto, forma y caja |
| Caja administración, PyME, chica y dirección | Cuentas configurables con saldo calculado |
| Costos, gastos, partidas e IVA | Egresos tipados con subtotal, IVA y total |
| Copiar nómina anterior | Periodos, empleados, préstamos, descuentos e incidencias |
| Nómina alimenta resultados | Nómina confirmada genera egreso |
| Traspasos internos | Afectan origen/destino sin contar ingreso o egreso |
| Flujo de efectivo | Vista calculada desde movimientos |
| Estado de resultados | Ingresos menos costos, gastos y nómina |
| Presupuesto y real por mes | Líneas presupuestales y vista real contra presupuesto |
| Matrícula y preinscritos para proyectar | Preinscripciones, importe medio y supuestos |
| Becas internas/oficiales 30/50/100% | Becas configurables que reducen el cargo |
| Adeudo acumulado | Estado de cuenta con saldo anterior y actual |

## Pendientes para producción

- Conectar la interfaz al proyecto Supabase definitivo.
- Implementar PDF e impresión del recibo.
- Terminar importadores CSV de alumnos y banco.
- Recibir y mapear los archivos reales que usa actualmente el colegio.
- Validar catálogos, cuotas, permisos y cancelaciones con Dirección.
- Configurar Storage, respaldos y aviso de privacidad.
