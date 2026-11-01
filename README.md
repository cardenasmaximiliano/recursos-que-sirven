# apiwhatsapp — Recordatorios por WhatsApp (OpenWA)

Carpeta donde se desarrolla la integración de WhatsApp de HemoGestión. Número vinculado: **+5492235554717**.

> **Aviso:** OpenWA usa la API **no oficial** de WhatsApp (se conecta como WhatsApp Web). El número puede ser bloqueado
> por WhatsApp y los mensajes viajan por una vía que Meta no garantiza. Los recordatorios llevan datos de turnos de
> donantes. Por eso la integración tiene tope diario, horario permitido, pausas al azar y un interruptor general.

## Cómo funciona

```
Escritorio (C++) ─┐                                    ┌─ OpenWA (Node, :2785) ─► WhatsApp del donante
Android ──────────┼─ HTTP ─► apiPHP (Apache :8090) ────┤
Programador de ───┘          (guarda la API key)       └─ MySQL: whatsapp_mensajes, plantillas_whatsapp
tareas (cada 30 min) ─► php apiPHP\cli\whatsapp.php ciclo
```

La **API key de OpenWA vive solo en el servidor** (`apiPHP\config.local.php`). Ni el escritorio ni Android la conocen.

### Los tres caminos

| # | Camino | Quién lo dispara | Qué hace |
|---|---|---|---|
| 1 | **Automático** | Programador de tareas, cada 30 min (08:00–20:00) | Arma los avisos que corresponden y envía lo pendiente |
| 2 | **Botón "Enviar recordatorios pendientes"** | Agenda (escritorio y Android) | Lo mismo que el 1, a demanda (si el servidor estuvo apagado) |
| 3 | **Click-to-chat** | Botón WhatsApp de cada turno | Abre `wa.me` con el mensaje armado; la persona toca "Enviar" |

**Qué avisos se mandan** (la regla de siempre, configurable en Configuración → Parámetros):
el **día hábil anterior** al turno a la hora `recordatorio_hora_envio` (10:00) y **N horas antes** (`recordatorio_horas`, 2).
Si el turno se dio con poca antelación, se manda solo el aviso más cercano.

**Sin duplicados:** la tabla `whatsapp_mensajes` tiene clave única `(turno_id, aviso)`: el mismo aviso del mismo turno no
se puede crear dos veces, lo dispare quien lo dispare. Además cada mensaje se *reserva* antes de enviarse y hay un solo
proceso de envío a la vez (candado de MySQL), así que el programador y el botón no se pisan.

**Errores:** sin red / OpenWA caído / sesión no lista → se reintenta con espera creciente (2, 4, 8… hasta 60 min, máx. 5
intentos). Error definitivo (número inválido, key mala) → queda `FALLIDO` con el motivo; se puede reintentar a mano.
Antes de enviar se vuelve a verificar que el donante acepte WhatsApp, no haya pedido la baja y que el turno siga activo.

**Cuidado del número:** pausa de 20–60 s al azar entre mensajes, solo entre las 08:00 y las 20:00 (parámetros
`whatsapp_ventana_desde/hasta`), tope de 150 por día (`whatsapp_tope_diario`).

## Puesta en marcha (una sola vez)

1. **Node 22.19 o más nuevo.** Ya instalado (Node LTS 24).
2. **Instalar y compilar OpenWA** (en `apiwhatsapp\openwa`, que ya está clonada):
   ```
   cd C:\Users\maxic\Desktop\apiwhatsapp\openwa
   npm install
   npm run build
   ```
   En Windows `npm install` necesita *Visual Studio Build Tools* y *Python 3* (compila `better-sqlite3`).
3. **Arrancar OpenWA:** `.\iniciar-openwa.ps1`. La primera vez muestra una **API key** (`owa_k1_…`); si no la copiaste,
   está en `openwa\data\.api-key`. Tratala como una contraseña.
4. **Vincular el número con un código** (con OpenWA corriendo en otra ventana): `.\vincular-numero.ps1`.
   Crea la sesión, la arranca y muestra un **código de 8 caracteres**. En el celular del número **+5492235554717**:
   WhatsApp → Ajustes → Dispositivos vinculados → Vincular un dispositivo → **Vincular con el número de teléfono** →
   escribir el código (vence en pocos minutos; si no alcanzás, corré el script otra vez). Al terminar muestra el
   `SESSION_ID` para el paso siguiente.
   *Alternativa con QR:* abrí **http://localhost:2785** (dashboard), pegá la API key, entrá a *Sessions* y escaneá el QR
   desde Dispositivos vinculados → Vincular un dispositivo.
5. **Decirle a la API cómo hablar con OpenWA.** En `apiPHP\config.local.php` (no se versiona):
   ```php
   return [
       'db' => [ /* lo que ya tengas */ ],
       'whatsapp' => [
           'activo'     => true,
           'api_key'    => 'owa_k1_...',      // la del paso 3
           'session_id' => '<SESSION_ID>',    // el del paso 4
       ],
   ];
   ```
6. **Programar el envío automático:** `.\crear-tarea-whatsapp.ps1` (ya registrada; sin la clave y `activo = true` no hace nada).
7. **Probar con tu propio número** antes de usarlo con donantes (ver "Probar").

### Apagar todo de golpe
`'activo' => false` en `config.local.php` (corta el programador y el botón), o **Logout** de la sesión en el dashboard
de OpenWA (desvincula el número). `.\crear-tarea-whatsapp.ps1 -Quitar` borra la tarea programada.

## Probar

`.\probar-whatsapp.ps1` corre toda la integración contra un **OpenWA simulado** (`simulador\`) y la base `hemogestion_test`:
no envía nada real ni toca la base real. Verifica los tres caminos, reintentos, error definitivo, consentimiento y que no
haya duplicados.

Para ver lo que haría el programador sin enviar: `php apiPHP\cli\whatsapp.php dryrun`. Registro: `apiPHP\logs\whatsapp.log`.

## Archivos

| Archivo | Para qué |
|---|---|
| `openwa\` | OpenWA (Node), clonado de github.com/rmyndharis/OpenWA; `.env` ya configurado |
| `iniciar-openwa.ps1` | Arranca OpenWA |
| `vincular-numero.ps1` | Crea la sesión y pide el código de vinculación del número |
| `crear-tarea-whatsapp.ps1` | Registra/quita la tarea del Programador de tareas |
| `probar-whatsapp.ps1`, `simulador\` | Prueba de punta a punta con OpenWA simulado |
| `..\proyecto-plaquetas-cpp\apiPHP\src\Whatsapp.php` | Cliente de OpenWA, regla de avisos, cola |
| `..\proyecto-plaquetas-cpp\apiPHP\src\Rutas\whatsapp.php` | Rutas `/whatsapp/*` y `/turnos/{id}/whatsapp-enlace` |
| `..\proyecto-plaquetas-cpp\apiPHP\cli\whatsapp.php` | Programador por línea de comandos |
| `..\proyecto-plaquetas-cpp\mysql\005_whatsapp_openwa.sql` | Tablas y textos de los mensajes |

## Rutas de la API (permiso "Enviar mensajes")

| Ruta | Qué hace |
|---|---|
| `GET /whatsapp/estado` | Si está activo, si la sesión está lista, pendientes, fallidos y enviados hoy |
| `POST /whatsapp/enviar-pendientes` | Botón masivo: arma los avisos y lanza el envío en segundo plano |
| `GET /turnos/{id}/whatsapp-enlace` | Click-to-chat: `{url, mensaje, telefono, nombre}` |
| `GET /whatsapp/mensajes?donante_id=` | Historial de envíos |
| `POST /whatsapp/mensajes/{id}/reintentar` | Vuelve a poner en cola uno fallido |

## Verificado contra el código de OpenWA

Las rutas se comprobaron leyendo el código de `openwa\src` (v0.25.0): `POST /api/sessions/{id}/messages/send-text` con
`{chatId, text}` (responde 201 con `messageId`), autenticación con `X-API-Key` (la key necesita el rol *operador*), estado
de la sesión en `GET /api/sessions/{id}` (`status`, listo = `ready`) y soporte de la cabecera `Idempotency-Key`, que la
integración usa en cada envío. Un número que no tiene WhatsApp responde 400 (queda `FALLIDO`). Lo que **no** se pudo
probar sin vincular un número real es el envío de verdad y la vinculación por QR.

## Si los botones de WhatsApp no envían

1. **OpenWA tiene que estar corriendo**: `.\iniciar-openwa.ps1` en una ventana (si se cierra o se apaga la PC, hay que volver a abrirlo).
   Si la sesión figura `disconnected`, arrancarla de nuevo con `POST /api/sessions/<id>/start` (la vinculación queda guardada).
2. **Apache (XAMPP) necesita la extensión curl**: el servicio de Apache no encontraba las DLL de curl y la API respondía
   `sesion_estado: sin_configurar`. Se arregló con `LoadFile` de `libssh2`, `nghttp2` y `brotli*` en
   `C:\xampp\apache\conf\extra\httpd-xampp.conf` (hay copia `.bak-hemogestion`). Después de tocar esa configuración hay que reiniciar Apache.
3. Comprobación rápida: `GET /api/v1/whatsapp/estado` debe devolver `sesion_lista: true`.
