#Requires -Version 5.1
<#
enable-auto-punctuation.ps1 — Windows 11 voice typing (Win+H): turns ON
"Automatic punctuation" (автоматическая расстановка знаков препинания)
and optionally schedules re-apply, because Windows resets the toggle
after reboot/hibernate (known MS bug, Q&A 3915596).

Usage:
  powershell -ExecutionPolicy Bypass -File .\enable-auto-punctuation.ps1              # apply punct_ON.reg + verify
  powershell -ExecutionPolicy Bypass -File .\enable-auto-punctuation.ps1 -Check       # print ON/OFF state only
  powershell -ExecutionPolicy Bypass -File .\enable-auto-punctuation.ps1 -Schedule    # + scheduled task: logon + screen unlock
  powershell -ExecutionPolicy Bypass -File .\enable-auto-punctuation.ps1 -RemoveSchedule
#>
param(
    [switch]$Check,
    [switch]$Schedule,
    [switch]$RemoveSchedule
)
$ErrorActionPreference = 'Stop'

$TaskName = 'VoiceTyping-AutoPunctuation-ON'
$KeyPath  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CloudStore\Store\DefaultAccount\Current\default$windows.data.settings.voice.voicesystemsettings\windows.data.settings.voice.voicesystemsettings'
$OnMarker = [byte[]](0x0b, 0x0a, 0x01, 0x0b, 0x02, 0x01, 0x01)

function Test-OnMarker([byte[]]$Data) {
    if (-not $Data) { return $false }
    for ($i = 0; $i -le $Data.Length - $OnMarker.Length; $i++) {
        $match = $true
        for ($j = 0; $j -lt $OnMarker.Length; $j++) {
            if ($Data[$i + $j] -ne $OnMarker[$j]) { $match = $false; break }
        }
        if ($match) { return $true }
    }
    return $false
}

function Get-State {
    try { $data = (Get-ItemProperty -LiteralPath $KeyPath -Name Data -ErrorAction Stop).Data }
    catch { return $false }
    return Test-OnMarker $data
}

if ($Check) {
    if (Get-State) { Write-Host 'Automatic punctuation: ON' }
    else            { Write-Host 'Automatic punctuation: OFF' }
    exit 0
}

$regFile = Join-Path $PSScriptRoot 'punct_ON.reg'
if (-not (Test-Path -LiteralPath $regFile)) { throw "Not found: $regFile" }
& reg.exe import $regFile
if ($LASTEXITCODE -ne 0) { throw "reg import failed, exit code $LASTEXITCODE" }
Start-Sleep -Milliseconds 800

if (Get-State) { Write-Host 'Automatic punctuation: ON (verified)' }
else { Write-Warning 'Value written, but ON marker not detected — check the toggle in the Win+H panel' }

if ($RemoveSchedule) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "Scheduled task '$TaskName' removed"
}

if ($Schedule) {
    $action   = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath)
    $logon    = New-ScheduledTaskTrigger -AtLogOn
    $unlock   = New-CimInstance -Namespace 'Root/Microsoft/Windows/TaskScheduler' -ClassName MSFT_TaskSessionStateChangeTrigger -ClientOnly -Property @{ StateChange = 6 }
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 2)
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $logon, $unlock -Settings $settings -Description 'Win+H: re-enable Automatic punctuation (CloudStore fix)' -Force | Out-Null
    Write-Host "Scheduled task '$TaskName' registered: at logon + screen unlock"
}
