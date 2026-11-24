# Manual de administración — CEI Cobros

**Versión inicial · 24 de noviembre de 2026**

Para Dirección y personal técnico responsable de cuentas, catálogos, respaldo y disponibilidad. Las credenciales y claves privadas nunca deben anotarse en este archivo.

## 1. Preparar y mantener la operación

Antes de iniciar un ciclo, comprueba en Supabase que exista un ciclo activo, meses del ciclo, cuentas, conceptos y tarifas, categorías de egreso y perfiles activos. Revisa que no queden datos de prueba. Haz una captura controlada de alumno, cargo, cobro, egreso y conciliación y compara los resultados.

Al cierre de cada jornada, revisa ingresos, egresos, saldos pendientes y conciliaciones. Asegura que las copias de seguridad de la base estén activas y que se pueda restaurar una copia en un proyecto separado. Los proyectos Supabase Free no incluyen copias descargables automáticas según la guía de producción de Supabase; verifica el plan y retención antes de depender de un respaldo.

## 2. Perfiles y cuentas

Los perfiles se guardan en `public.profiles`: nombre, rol y bandera `active`. Los roles existentes son `direccion`, `caja` y `captura` (el esquema también conserva `admin` por compatibilidad; las migraciones lo convierten a `direccion`). El alta de una cuenta en Auth crea por defecto un perfil `captura`; solo la primera cuenta de la base se asigna automáticamente a Dirección. Crear una cuenta no equivale a otorgar permisos administrativos.

En la versión actual, los módulos no se ocultan por rol. Las políticas de datos habilitan las operaciones al personal con perfil activo; los cambios de perfiles y algunas acciones de Dirección se restringen a `direccion`/`admin`. Por tanto, asignar `caja` o `captura` sirve para identificar la función del personal, pero no constituye por sí solo una separación completa de todas las operaciones. Otorga cuentas solo a personal autorizado y solicita un control de permisos más estricto si se necesita limitar, por ejemplo, caja exclusivamente a cobros.

La pantalla de la aplicación no incluye un módulo de administración de usuarios. Dirección puede administrar perfiles desde Supabase Studio, con acceso autorizado:

1. En **Authentication → Users**, crea o localiza la cuenta por correo y confirma que el usuario sea el correcto.
2. Copia el UUID del usuario.
3. En **SQL Editor**, consulta primero el perfil:

```sql
select id, full_name, role, active
from public.profiles
where id = 'UUID_CONFIRMADO';
```

4. Si corresponde activar o cambiar el rol, ejecuta una actualización precisa y comprueba el resultado:

```sql
update public.profiles
set role = 'caja', active = true
where id = 'UUID_CONFIRMADO';

select id, full_name, role, active
from public.profiles
where id = 'UUID_CONFIRMADO';
```

Sustituye `caja` por `captura` o `direccion` según la autorización aprobada. No otorgues Dirección por conveniencia: el permiso puede cambiar perfiles y retirar datos de prueba. Para revocar acceso, establece `active = false`; evita borrar el usuario o su perfil si se necesita conservar auditoría. El personal puede cambiar su propia contraseña desde el menú de la aplicación.

## 3. Disponibilidad: Vercel y Supabase

La aplicación se publica en Vercel, pero los inicios de sesión y datos dependen de Supabase. La URL inicial de Vercel respondió y redirigió al inicio de sesión al revisar este repositorio. Eso confirma que Vercel servía la página en ese momento; no demuestra que Auth y la base de datos estén disponibles.

La URL configurada localmente y en el JavaScript publicado en Vercel es la del proyecto Supabase `cei-cobros`. El 24 de noviembre de 2026 se detectó **INACTIVE** y el nombre DNS del endpoint no resolvía. Se restauró el proyecto existente; la comprobación posterior mostró `ACTIVE_HEALTHY` y Auth respondió HTTP 200. No se reemplazó la base ni sus datos.

### Recuperar la conexión de producción

1. En Supabase, confirma que el proyecto correcto exista y que esté activo. Si aparece pausado, usa **Resume project**.
2. Copia el **Project URL** y la clave pública/publishable de ese mismo proyecto desde la página de API. No uses una clave `service_role` en el navegador.
3. En Vercel, abre el proyecto **centro-educativo-itzam**, sección **Settings → Environment Variables**. Configura `NEXT_PUBLIC_SUPABASE_URL` y `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` para **Production**; comprueba también Preview si se usa.
4. Guarda y crea un nuevo deployment de producción para que Next.js incluya las variables públicas actualizadas.
5. Abre la aplicación y prueba inicio de sesión, carga de alumnos, una operación controlada y cierre de sesión. Comprueba que el dato aparezca en el panel de Supabase.
6. Actualiza también las variables locales en `.env.local` si se trabaja desde esta computadora. Ese archivo está excluido de Git y no debe compartirse.

Si el proyecto Supabase anterior ya no existe, localiza el proyecto de producción y evalúa la restauración antes de reemplazarlo. Un proyecto nuevo no recupera los datos del anterior. Aplica y revisa todas las migraciones de `supabase/migrations` antes de poner una base nueva en operación. El flujo de GitHub Actions que aplica migraciones depende de secretos de base y token de Supabase configurados en GitHub.

### Evitar que Supabase se pause por inactividad

Supabase indica que los proyectos **Free** con poca actividad durante siete días pueden pausarse. El workflow `supabase-keepalive.yml` solicita la reactivación si detecta el estado `INACTIVE` y hace una consulta real cada seis horas mediante GitHub Actions. Esto reduce el riesgo de nuevas pausas por inactividad, pero no equivale a una garantía del proveedor. Para garantizar que no se pause por inactividad, la propia guía de Supabase indica pasar a un plan de pago. Revisa el costo y la facturación con Dirección antes de cambiar el plan. La frecuencia de visitas a Vercel no mantiene por sí misma activa una base de Supabase.

Vercel no suspende un despliegue solo porque pase una semana sin visitas. Sin embargo, Vercel Hobby puede pausar el equipo al agotar sus límites gratuitos; Pro también puede pausar proyectos si está activada esa regla de Spend Management. Revisa **Usage/Billing** y el estado del equipo y despliegue. No desactives un límite de gasto sin acordarlo con Dirección. Comprueba el panel de despliegues de Vercel si no responde la página; comprueba Supabase si carga la página pero no funciona el inicio de sesión o no aparecen datos.

Referencias oficiales: [pausa de proyectos Supabase Free](https://supabase.com/docs/guides/platform/free-project-pausing), [lista de producción de Supabase](https://supabase.com/docs/guides/deployment/going-into-prod), [planes Hobby de Vercel](https://vercel.com/docs/plans/hobby), [uso y límites en Vercel](https://vercel.com/docs/plans/account-plans#what-happens-when-i-reach-100-usage), [Spend Management en Vercel](https://vercel.com/docs/spend-management).

## 4. Migraciones y despliegues

El repositorio está conectado a GitHub y enlazado con el proyecto de Vercel. Los cambios enviados a la rama configurada pueden generar un deployment automático. Antes de aceptar una versión, revisa el resultado del build en Vercel y evita incluir `.env.local`, claves, datos personales o exports. Las migraciones de base están en `supabase/migrations`; el workflow de GitHub crea una vista previa (`--dry-run`) antes de aplicar cambios si están configurados `SUPABASE_ACCESS_TOKEN` y `SUPABASE_DB_PASSWORD`.

No borres datos desde SQL como forma rutinaria de corregir movimientos. Las cancelaciones de ingresos, egresos y otros movimientos registran motivo y conservan historial. Revisa [Operación real](OPERACION_REAL.md) antes de corregir información financiera.

## 5. Prueba financiera y cierres

La opción de prueba financiera puede crear alumnos y movimientos de demostración. Solo Dirección debe usar **Usar prueba de 10** y, después de una prueba, **Retirar datos de prueba** en Alumnos; también existe una opción de retiro de datos de prueba en Inicio. Confirma primero que se trate de datos demostrativos: retirar datos no es un método para cancelar movimientos reales.

Al cierre, confirma el estado de cuenta, los ingresos, egresos, conciliaciones bancarias y traspasos. Conserva el respaldo y documenta la fecha de verificación. No incluyas contraseñas, credenciales o información de alumnos en este manual.
