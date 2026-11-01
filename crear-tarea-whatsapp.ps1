# Registra en el Programador de tareas de Windows el envío automático de recordatorios por WhatsApp.
# Corre "php cli\whatsapp.php ciclo" todos los días cada 30 minutos entre las 08:00 y las 20:00:
# arma los avisos que corresponden (día hábil anterior y horas antes) y envía lo pendiente, con pausas.
# Si WhatsApp está apagado en apiPHP\config.local.php, la tarea no hace nada.
#   .\crear-tarea-whatsapp.ps1            registra (o actualiza) la tarea
#   .\crear-tarea-whatsapp.ps1 -Quitar    la elimina
param([switch]$Quitar, [string]$Php = 'C:\xampp\php\php.exe', [string]$Raiz = 'C:\Users\maxic\Desktop\proyecto-plaquetas-cpp')
$ErrorActionPreference = 'Stop'
$nombre = 'HemoGestion-RecordatoriosWhatsApp'
if ($Quitar) {
    Unregister-ScheduledTask -TaskName $nombre -Confirm:$false -ErrorAction SilentlyContinue
    "Tarea '$nombre' eliminada."
    return
}
if (-not (Test-Path $Php)) { throw "No se encontró $Php" }
$script = Join-Path $Raiz 'apiPHP\cli\whatsapp.php'
if (-not (Test-Path $script)) { throw "No se encontró $script" }
$accion = New-ScheduledTaskAction -Execute $Php -Argument "`"$script`" ciclo" -WorkingDirectory (Join-Path $Raiz 'apiPHP')
$disparador = New-ScheduledTaskTrigger -Daily -At '08:00'
$repeticion = New-ScheduledTaskTrigger -Once -At '08:00' -RepetitionInterval (New-TimeSpan -Minutes 30) -RepetitionDuration (New-TimeSpan -Hours 12)
$disparador.Repetition = $repeticion.Repetition
$ajustes = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 2) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName $nombre -Action $accion -Trigger $disparador -Settings $ajustes `
    -Description 'Recordatorios de turnos por WhatsApp (OpenWA). Ver apiwhatsapp\README.md' -Force | Out-Null
"Tarea '$nombre' registrada: cada 30 minutos entre las 08:00 y las 20:00."
Get-ScheduledTask -TaskName $nombre | Get-ScheduledTaskInfo | Select-Object LastRunTime, NextRunTime | Format-List
