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

La pantalla inicial incluye datos demostrativos para validar el diseño con el
cliente antes de conectar información real.

## Arquitectura

- Next.js App Router + TypeScript, desplegable en Vercel.
- Supabase Auth, PostgreSQL y Row Level Security.
- `register_cash_payment` crea recibo, ingreso y aplicaciones en una sola
  transacción. Si alguna validación falla, no se guarda ningún fragmento.
- Los traspasos se registran aparte y no inflan ingresos ni egresos.
- Las cancelaciones deben implementarse como cambios de estado y
  contramovimientos, nunca como borrados.

## Alcance recomendado

**Etapa 1:** autenticación, catálogos, alumnos/importación, cartera, caja,
transferencias, egresos, traspasos y estados de cuenta tabulares.

**Etapa 2:** nómina, conciliación bancaria importada, presupuesto, reportes
financieros y exportaciones.

**Etapa 3:** sugerencias automáticas para transferencias, portal de tutores y
módulos escolares futuros.

Antes de producción se deben validar con Dirección: catálogo contable, reglas
de vencimiento, folios, autorización de saldos negativos, retención de
respaldos y política de datos personales.
