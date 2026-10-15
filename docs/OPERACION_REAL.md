# Operación real del sistema CEI

## Antes de iniciar

1. Confirmar que el ciclo activo, cuentas, conceptos de cobro, tarifas,
   categorías de egreso y perfiles del personal estén configurados.
2. Verificar que no existan filas de demostración activas.
3. Crear un respaldo de Supabase y conservar la fecha del respaldo.
4. Hacer una prueba pequeña: un alumno, un cargo, un pago, un egreso y una
   conciliación. Confirmar que los saldos y reportes coincidan.

## Operación diaria

- Registrar alumnos o importarlos desde una lista validada.
- Registrar cobros desde Cobros; el recibo y el ingreso se generan juntos.
- Capturar transferencias sin alumno cuando todavía no sea posible identificar
  el pago.
- En Conciliación, seleccionar el ingreso confirmado que corresponde al
  movimiento bancario. El sistema valida que los importes coincidan.
- Registrar egresos y traspasos con la cuenta y categoría correctas.
- Usar el lápiz para corregir datos y la papelera para cancelar o dar de baja.
  Las operaciones financieras conservan historial y motivo.

## Correcciones

No se deben borrar filas directamente en Supabase. Para un error financiero:

1. Abrir la fila correspondiente.
2. Corregir los datos editables o cancelar con un motivo.
3. Si el importe de un recibo es incorrecto, cancelar el ingreso y capturar el
   correcto; no modificar manualmente el saldo del cargo.
4. Revisar el saldo del alumno y el reporte de movimientos.

## Roles mínimos

- Captura: alumnos, importaciones y datos operativos autorizados.
- Caja: cobros, recibos, ingresos, egresos y conciliación.
- Dirección: correcciones sensibles, retiro de prueba, catálogos y revisión.

## Respaldo y cierre

Al terminar cada jornada, revisar ingresos, egresos, saldos pendientes y
conciliaciones. Mantener habilitado el respaldo administrado de Supabase y
probar periódicamente la restauración en un proyecto separado. No guardar
contraseñas ni datos personales en archivos de exportación sin protección.
