# Vincula el número de WhatsApp a OpenWA con un CÓDIGO de 8 caracteres (alternativa al QR).
# Requisitos: OpenWA instalado y corriendo (.\iniciar-openwa.ps1 en otra ventana).
#   .\vincular-numero.ps1
#
# Qué hace: crea la sesión "recordatorios" si no existe, la arranca, pide el código para el número y te lo muestra.
# Después, en el celular de ese número: WhatsApp > Ajustes > Dispositivos vinculados > Vincular un dispositivo >
# "Vincular con el número de teléfono" > escribir el código. El código vence en pocos minutos.
param(
    [string]$Numero = '5492235554717',      # solo dígitos, con código de país (+54 9 223 555-4717)
    [string]$Nombre = 'recordatorios',
    [string]$ApiKey = '',
    [string]$Url = 'http://localhost:2785'
)
$ErrorActionPreference = 'Stop'

if (-not $ApiKey) {
    $archivo = Join-Path $PSScriptRoot 'openwa\data\.api-key'
    if (Test-Path $archivo) { $ApiKey = (Get-Content $archivo -Raw).Trim() }
}
if (-not $ApiKey) { throw "No encontré la API key. Pasala con -ApiKey o buscala en $PSScriptRoot\openwa\data\.api-key (aparece al primer arranque de OpenWA)." }

function Api($metodo, $ruta, $cuerpo = $null) {
    $a = @{ Uri = "$Url/api$ruta"; Method = $metodo; Headers = @{ 'X-API-Key' = $ApiKey }; ContentType = 'application/json' }
    if ($null -ne $cuerpo) { $a.Body = ($cuerpo | ConvertTo-Json -Compress) }
    try { Invoke-RestMethod @a } catch { throw "$metodo $ruta -> $($_.Exception.Message) $($_.ErrorDetails.Message)" }
}

try { Api GET '/health' | Out-Null } catch { throw "OpenWA no responde en $Url. Arrancalo con .\iniciar-openwa.ps1 (en otra ventana) y volvé a probar." }

# 1) La sesión: se reutiliza si ya existe una con ese nombre.
$lista = Api GET '/sessions'
if ($lista -isnot [array]) { $lista = @($lista.data) + @($lista.items) | Where-Object { $_ } }
$sesion = $lista | Where-Object { $_.name -eq $Nombre } | Select-Object -First 1
if (-not $sesion) { $sesion = Api POST '/sessions' @{ name = $Nombre } }
$id = $sesion.id
"Sesión '$Nombre': $id"

# 2) Arrancarla y esperar a que pida vincular.
try { Api POST "/sessions/$id/start" | Out-Null } catch { "(la sesión ya estaba arrancada)" }
$estado = ''
for ($i = 0; $i -lt 30; $i++) {
    $estado = (Api GET "/sessions/$id").status
    if ($estado -in @('qr_ready', 'ready')) { break }
    Start-Sleep 2
}
if ($estado -eq 'ready') { "La sesión ya está vinculada y lista. No hace falta ningún código."; $listo = $true }
elseif ($estado -ne 'qr_ready') { throw "La sesión quedó en estado '$estado' (se esperaba 'qr_ready'). Mirá los logs en http://localhost:2785" }
else {
    # 3) El código de vinculación para el número.
    $r = Api POST "/sessions/$id/pairing-code" @{ phoneNumber = $Numero }
    ""
    "  CÓDIGO DE VINCULACIÓN:  $($r.pairingCode)"
    ""
    "En el celular de +${Numero}:"
    "  WhatsApp > Ajustes > Dispositivos vinculados > Vincular un dispositivo > 'Vincular con el número de teléfono'"
    "  y escribí el código. Vence en pocos minutos: si no alcanzás, volvé a correr este script."
    "Esperando la vinculación..."
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep 3
        if ((Api GET "/sessions/$id").status -eq 'ready') { $listo = $true; break }
    }
}
""
if ($listo) { "VINCULADO. La sesión está lista." } else { "Todavía no figura vinculada. Revisá el celular y, si hace falta, repetí el script." }
""
"Para activar los recordatorios, en apiPHP\config.local.php:"
"  'whatsapp' => [ 'activo' => true, 'api_key' => '<la API key de OpenWA>', 'session_id' => '$id' ],"
