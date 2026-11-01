# Arranca OpenWA (el "mensajero" de WhatsApp). Dejá la ventana abierta mientras se usen los recordatorios.
# Requisito: haber corrido antes "npm install" y "npm run build" dentro de apiwhatsapp\openwa (ver README.md).
$ErrorActionPreference = 'Stop'
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
$openwa = Join-Path $PSScriptRoot 'openwa'
if (-not (Test-Path (Join-Path $openwa 'dist'))) { throw "OpenWA todavía no está compilado. Corré en $openwa : npm install ; npm run build" }
Set-Location $openwa
Write-Host 'OpenWA en http://localhost:2785  (Ctrl+C para detener)'
npm start
