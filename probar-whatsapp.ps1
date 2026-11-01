# Prueba de punta a punta de los recordatorios por WhatsApp con un OpenWA SIMULADO.
# Usa la base de pruebas hemogestion_test (se reinicia) y nunca toca la base real ni envía mensajes de verdad.
#   .\probar-whatsapp.ps1
$ErrorActionPreference = 'Stop'
$php = 'C:\xampp\php\php.exe'
$mysql = 'C:\xampp\mysql\bin\mysql.exe'
$aw = $PSScriptRoot
$raiz = 'C:\Users\maxic\Desktop\proyecto-plaquetas-cpp'

$env:HEMO_API_DB = 'hemogestion_test'; $env:HEMO_API_DB_PUERTO = '3307'; $env:HEMO_API_MODO_PRUEBAS = '1'
$env:HEMO_WHATSAPP_ACTIVO = '1'; $env:HEMO_WHATSAPP_URL = 'http://127.0.0.1:2799'
$env:HEMO_WHATSAPP_API_KEY = 'clave-de-prueba'; $env:HEMO_WHATSAPP_SESSION = 'prueba'; $env:HEMO_WHATSAPP_PAUSA_MAX = '1'

$fallos = 0
function Verificar($condicion, $texto) {
    if ($condicion) { "  OK   $texto" } else { "  FALLO $texto"; $script:fallos++ }
}
function Sql($consulta) {
    (& $mysql --host=127.0.0.1 --port=3307 --user=root hemogestion_test -N -B -e $consulta) -join "`n"
}

& $php "$raiz\apiPHP\migrar.php" | Select-Object -Last 2
$sim = Start-Process $php -ArgumentList @('-S', '127.0.0.1:2799', "$aw\simulador\openwa_simulado.php") -PassThru -WindowStyle Hidden
$api = Start-Process $php -ArgumentList @('-S', '127.0.0.1:8098', '-t', "$raiz\apiPHP", "$raiz\apiPHP\index.php") -PassThru -WindowStyle Hidden
try {
    Start-Sleep 2
    $tok = (& $php "$raiz\apiPHP\crear_clave_servicio.php" prueba_whatsapp | Select-Object -Last 1).Trim()
    function Api($metodo, $ruta, $cuerpo = $null) {
        $a = @{ Uri = "http://127.0.0.1:8098/api/v1$ruta"; Method = $metodo; Headers = @{ Authorization = "Bearer $tok" }; ContentType = 'application/json; charset=utf-8' }
        if ($null -ne $cuerpo) { $a.Body = [Text.Encoding]::UTF8.GetBytes(($cuerpo | ConvertTo-Json -Depth 8 -Compress)) }
        try { Invoke-RestMethod @a } catch { throw "$metodo $ruta -> $($_.ErrorDetails.Message)" }
    }
    Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:2799/_reiniciar' | Out-Null
    Api POST /pruebas/reiniciar | Out-Null

    $ahora = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $hash = & $php -r "echo password_hash('0123456789', PASSWORD_ARGON2ID);"
    $admin = (Api POST /usuarios @{ nombre = 'admin'; apellido = 'admin'; usuario = 'admin'; password_hash = $hash; rol = 'SUPERADMIN'; activo = $true; debe_cambiar_password = $false; intentos_fallidos = 0; creado_en = $ahora }).id
    function Donante($doc, $nombre, $telefono, $acepta) {
        $d = @{ tipo_documento = 'DNI'; numero_documento = $doc; nombre = $nombre; apellido = 'Prueba'; busqueda_normalizada = "prueba $nombre".ToLower(); fecha_nacimiento = '1990-01-01'; sexo = 'F'; peso_kg = 70
            grupo_sanguineo = 'A'; factor_rh = '+'; restricciones = @(); email = $null; telefono_e164 = $telefono; domicilio = $null; localidad = $null
            acepta_email = $false; acepta_whatsapp = $acepta; diferido_permanente = $false; activo = $true; fecha_alta = $ahora; creado_por = $admin }
        if ($acepta) { $d.fecha_consentimiento = $ahora }
        (Api POST /donantes $d).id
    }
    $a = Donante '30000001' 'Ana'    '+5492235550001' $true    # se le manda bien
    $b = Donante '30000002' 'Beto'   '+5490000000001' $true    # el simulado falla con 500 (transitorio): se reintenta
    $c = Donante '30000003' 'Cacho'  '+5492235550003' $false   # no aceptó WhatsApp: no se le escribe
    $d = Donante '30000004' 'Delia'  '+5491111000001' $true    # el simulado rechaza con 400 (definitivo)
    $enUnaHora = (Get-Date).ToUniversalTime().AddHours(1).ToString('yyyy-MM-dd HH:mm:ss')
    $turnos = @{}
    foreach ($par in @(@($a, 'a'), @($b, 'b'), @($c, 'c'), @($d, 'd'))) {
        Sql "INSERT INTO turnos (donante_id, fecha_hora, tipo_donacion, estado, origen, creado_en) VALUES ($($par[0]), '$enUnaHora', 'PLAQUETAS', 'PENDIENTE', 'PRESENCIAL', UTC_TIMESTAMP())" | Out-Null
        $turnos[$par[1]] = [int](Sql "SELECT id FROM turnos WHERE donante_id = $($par[0]) ORDER BY id DESC LIMIT 1")
    }

    "1) Estado antes de enviar"
    $estado = Api GET /whatsapp/estado
    Verificar ($estado.activo -eq $true) 'WhatsApp figura activo'
    Verificar ($estado.sesion_lista -eq $true) 'la sesión de OpenWA figura lista'
    Verificar ($estado.pendientes -eq 0) 'no hay pendientes todavía'

    "2) Botón: enviar recordatorios pendientes"
    $r = Api POST /whatsapp/enviar-pendientes
    Verificar ($r.programados -eq 3) "se programaron 3 avisos (Ana, Beto, Delia) -> $($r.programados)"
    Verificar ($r.omitidos -eq 1) "se omitió 1 (Cacho no aceptó WhatsApp) -> $($r.omitidos)"
    Verificar ($r.lanzado -eq $true) 'el envío se lanzó en segundo plano'
    for ($i = 0; $i -lt 30; $i++) { if ((Sql "SELECT COUNT(*) FROM whatsapp_mensajes WHERE estado = 'PENDIENTE' AND intentos = 0") -eq '0') { break }; Start-Sleep 1 }
    Start-Sleep 2
    $enviados = Invoke-RestMethod 'http://127.0.0.1:2799/_enviados'
    Verificar (@($enviados).Count -eq 1) "OpenWA recibió 1 mensaje -> $(@($enviados).Count)"
    Verificar ($enviados[0].chatId -eq '5492235550001@c.us') 'el mensaje fue al número de Ana (formato 549...@c.us)'
    Verificar ($enviados[0].text -match 'Ana') 'el texto lleva el nombre'
    Verificar ($enviados[0].text -match 'a las \d\d:\d\d') 'el texto lleva la hora del turno'
    Verificar ((Sql "SELECT estado FROM whatsapp_mensajes WHERE donante_id = $a") -eq 'ENVIADO') 'Ana quedó ENVIADO'
    Verificar ((Sql "SELECT CONCAT(estado, ':', intentos) FROM whatsapp_mensajes WHERE donante_id = $b") -eq 'PENDIENTE:1') 'Beto quedó para reintentar (PENDIENTE, 1 intento)'
    Verificar ((Sql "SELECT estado FROM whatsapp_mensajes WHERE donante_id = $d") -eq 'FALLIDO') 'Delia quedó FALLIDO (error definitivo)'
    Verificar ((Sql "SELECT COUNT(*) FROM whatsapp_mensajes WHERE donante_id = $c") -eq '0') 'a Cacho no se le creó nada'

    "3) Sin duplicados"
    $r2 = Api POST /whatsapp/enviar-pendientes
    Verificar ($r2.programados -eq 0) "segundo clic: no se programa nada nuevo -> $($r2.programados)"
    Start-Sleep 3
    Verificar (@(Invoke-RestMethod 'http://127.0.0.1:2799/_enviados').Count -eq 1) 'OpenWA sigue con 1 solo mensaje (Beto espera su próximo intento)'
    Verificar ((Sql 'SELECT COUNT(*) FROM whatsapp_mensajes') -eq '3') 'la cola sigue con 3 filas'

    "4) Programador por línea de comandos (ciclo)"
    $salida = & $php "$raiz\apiPHP\cli\whatsapp.php" dryrun
    Verificar ($LASTEXITCODE -eq 0) 'dryrun termina bien'
    Verificar (($salida -join "`n") -match 'Beto|5490000000001') 'dryrun muestra el mensaje pendiente de Beto'
    & $php "$raiz\apiPHP\cli\whatsapp.php" ciclo | Out-Null
    Verificar ($LASTEXITCODE -eq 0) 'ciclo termina bien'
    Verificar ((Sql 'SELECT COUNT(*) FROM whatsapp_mensajes') -eq '3') 'el ciclo tampoco duplica'

    "5) Click-to-chat"
    $e = Api GET "/turnos/$($turnos.a)/whatsapp-enlace"
    Verificar ($e.url -like 'https://wa.me/5492235550001?text=*') 'el enlace apunta al número de Ana'
    Verificar ($e.mensaje -match 'Ana' -and $e.mensaje -match 'a las \d\d:\d\d') 'el mensaje viene armado con nombre y hora'
    Verificar ([uri]::UnescapeDataString($e.url.Split('=', 2)[1]) -eq $e.mensaje) 'el texto del enlace es el mismo mensaje (con tildes y saltos)'
    $sinNumero = Donante '30000005' 'Sin' $null $true
    Sql "INSERT INTO turnos (donante_id, fecha_hora, tipo_donacion, estado, origen, creado_en) VALUES ($sinNumero, '$enUnaHora', 'PLAQUETAS', 'PENDIENTE', 'PRESENCIAL', UTC_TIMESTAMP())" | Out-Null
    $t5 = [int](Sql "SELECT id FROM turnos WHERE donante_id = $sinNumero ORDER BY id DESC LIMIT 1")
    try { Api GET "/turnos/$t5/whatsapp-enlace" | Out-Null; Verificar $false 'sin celular debería dar error' } catch { Verificar $true 'un donante sin celular da error claro' }
}
finally {
    Stop-Process -Id $sim.Id, $api.Id -Force -ErrorAction SilentlyContinue
}
"`n$(if ($fallos -eq 0) { 'TODO OK' } else { "$fallos FALLO(S)" })"
exit $fallos
