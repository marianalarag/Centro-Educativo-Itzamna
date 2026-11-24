# Manual de usuario — CEI Cobros

**Versión inicial · 24 de noviembre de 2026**

Guía para el personal con una cuenta activa que captura alumnos y movimientos escolares o financieros. Dirección asigna los perfiles y autoriza las operaciones sensibles.

## 1. Acceso

1. Abre [CEI Control Escolar](https://centro-educativo-itzam.vercel.app).
2. Escribe tu correo y contraseña y selecciona **Entrar**.
3. Al terminar, usa **Cerrar sesión** en el menú lateral. No compartas tu cuenta.

Si no puedes entrar, revisa el correo y contraseña. Si el sistema dice que no se conecta o no carga datos, avisa a Dirección; no vuelvas a capturar el mismo movimiento hasta confirmar si se guardó.

## 2. Navegación

El menú lateral contiene **Inicio, Alumnos, Cobros, Ingresos, Conciliación, Egresos, Nómina, Traspasos, Becas, Presupuesto** y **Reportes**. El encabezado muestra el ciclo escolar activo. Las tablas de los módulos permiten buscar texto y, donde corresponda, filtrar por categoría, alumno, estado u otros campos.

### Inicio

Consulta el resumen de ingresos, egresos y saldos, avisos de pagos, y movimientos recientes. Usa los filtros de salón y estado para revisar la cobranza. Los avisos se pueden marcar como leídos.

### Alumnos

- Para un alta individual, selecciona **Nuevo alumno** y captura matrícula, nombre, nivel/grado y los datos disponibles del tutor. Revisa la matrícula antes de guardar.
- Para una lista, selecciona **Importar lista**, descarga la plantilla o prepara un archivo `.csv` o `.xlsx` de hasta 500 filas. Revisa la vista previa y corrige los errores señalados antes de importar.
- Busca por matrícula o nombre para localizar un registro. Usa las acciones de la fila para editar o dar de baja cuando tu perfil lo permita.

Las bajas son lógicas: el historial se conserva.

### Cobros

1. Selecciona **Nuevo cobro** y elige un alumno existente, o captura los datos de un alumno nuevo.
2. Elige el concepto y verifica el precio base, fecha de vencimiento y recargo mostrado.
3. Elige **Registrar pago** para registrar dinero recibido o **Dejar pendiente** para crear solo el adeudo.
4. Si hubo pago, captura fecha, forma de pago e importe recibido. Deja el importe vacío para liquidar el total; captura una cantidad menor para un pago parcial.
5. Revisa el resumen y confirma. Si se genera un recibo, imprime o guarda la impresión antes de cerrar.

El recibo y el ingreso en caja se registran juntos. No repitas el cobro si la pantalla tarda: primero verifica el folio en **Ingresos**.

### Ingresos y transferencias

En **Ingresos**, usa **Registrar transferencia** para anotar un depósito: fecha, importe, referencia y datos disponibles. Si todavía no sabes a qué alumno corresponde, déjalo sin identificar y pide apoyo para asignarlo después. No lo registres como efectivo.

### Conciliación bancaria

1. Selecciona **Importar movimientos** y carga el archivo del banco.
2. Compara fecha, referencia e importe de cada movimiento bancario con los ingresos existentes.
3. Relaciona únicamente el ingreso que corresponda. El importe debe coincidir; revisa los movimientos no identificados y duplicados por separado.

Conciliar compara el banco con un ingreso ya capturado; no vuelve a registrar el dinero recibido.

### Egresos y traspasos

- En **Egresos**, selecciona **Nuevo egreso** e indica fecha, descripción, importe, cuenta de origen, partida y forma de pago. Registra importes con cuidado y conserva la evidencia fuera del sistema según el procedimiento del colegio.
- En **Traspasos**, indica fecha, importe, cuenta de origen y destino y motivo. Verifica las dos cuentas: un traspaso mueve dinero entre cajas y no es ingreso ni gasto.

### Becas, nómina y presupuesto

Estas secciones presentan los datos de su módulo. Si tu cuenta tiene permiso de captura, usa el botón de alta y verifica la información del ciclo, periodo, vigencia, porcentajes, cuentas e importes antes de guardar. Para cambios de catálogo o decisiones de autorización, consulta a Dirección.

### Reportes

Elige **Cobranza por alumno, Ingresos, Egresos** o **Estado de resultados**. Ajusta salón, estado y fechas cuando estén disponibles. Revisa la vista previa y el total de filas, selecciona PDF, CSV o Excel y descarga. Comparte exportaciones solo con personal autorizado: pueden incluir información personal y financiera.

## 3. Corregir un error

- Usa el lápiz para editar los datos permitidos.
- Las opciones de baja o cancelación piden motivo y conservan el historial. No borres registros desde la base de datos.
- Si el importe de un recibo es incorrecto, solicita que se cancele con el motivo y registra el pago correcto; no ajustes manualmente el saldo.
- Después de una corrección, revisa el saldo o reporte relacionado.

## 4. Contraseña y protección de datos

Selecciona **Cambiar contraseña**, escribe y confirma una contraseña nueva de al menos 8 caracteres. Cierra sesión en equipos compartidos. No guardes exportaciones con datos personales en carpetas públicas ni envíes contraseñas por correo o chat.

## 5. Si algo falla

Anota la hora, sección y acción que estabas realizando, junto con el texto del error. Avisa a Dirección. No compartas capturas con datos de alumnos en grupos no autorizados. Para revisar si un cobro quedó guardado, busca primero su folio en **Ingresos**.
