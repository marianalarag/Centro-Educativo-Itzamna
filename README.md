# CEI Cobros

Sistema web para la operación financiera del Centro Educativo Itzamná. La
primera etapa se concentra en números, tablas y captura: alumnos, cargos,
pagos parciales, recibos, transferencias, egresos y traspasos.

## Ejecutar localmente

1. Copiar `.env.example` como `.env.local` y agregar las credenciales públicas
   del proyecto Supabase.
2. Ejecutar la migración de `supabase/migrations` en un proyecto Supabase.
3. Instalar y arrancar:

```bash
npm install
npm run dev
```

La operación real inicia después de aplicar todas las migraciones. La prueba
financiera no se carga automáticamente: Dirección puede cargarla desde
Alumnos y retirarla desde el mismo lugar mediante cancelación lógica.

## Arquitectura

- Next.js App Router + TypeScript, desplegable en Vercel.
- Supabase Auth, PostgreSQL y Row Level Security.
- `register_cash_payment` crea recibo, ingreso y aplicaciones en una sola
  transacción. Si alguna validación falla, no se guarda ningún fragmento.
- Los traspasos se registran aparte y no inflan ingresos ni egresos.
- Desde las tablas operativas se pueden editar alumnos, cargos, ingresos,
  conciliaciones, egresos y traspasos. Los movimientos financieros se cancelan
  con motivo y conservan el historial; al cancelar un ingreso se revierten sus
  aplicaciones sobre los cargos.

## Alcance recomendado

**Etapa 1 operativa:** autenticación, ciclo actual, alumnos/importación, cartera,
pagos parciales, caja, transferencias, egresos, traspasos y reportes tabulares
exportables.

**Etapa 2:** nómina, presupuesto y automatizaciones adicionales de reportes.

**Etapa 3:** sugerencias automáticas para transferencias, portal de tutores y
módulos escolares futuros.

Antes de producción se deben validar con Dirección: catálogo contable, reglas
de vencimiento, folios, autorización de saldos negativos, retención de
respaldos y política de datos personales.

La guía de operación diaria y correcciones está en
`docs/OPERACION_REAL.md`.
