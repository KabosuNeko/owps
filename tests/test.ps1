# Self-check: runs owps.ps1 against a fake WPS install in %TEMP%. Touches no real WPS files,
# tasks or service (Get-Process/Get-Service are stubbed). Run: powershell -ExecutionPolicy Bypass -File tests\test.ps1
$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot '..\owps.ps1'
$t = Join-Path $env:TEMP "owps-test-$PID"
$env:LOCALAPPDATA = "$t\Local"; $env:APPDATA = "$t\Roaming"
function Get-Process { }   # pretend WPS is closed
function Get-Service { }   # pretend the service is absent

$new = "$t\Local\Kingsoft\WPS Office\12.1.0.200"
$old = "$t\Local\Kingsoft\WPS Office\12.1.0.100"
$pool = "$t\Roaming\kingsoft\wps_intl\addons\pool\win-x64"
foreach ($d in "$new\office6\addons\kwhatsnew", "$new\office6\addons\kwpsnote", "$new\wtoolex",
               "$old\office6\addons\kwhatsnew.owps-off", "$pool\kpromotionstrategy_3.1.0.1", "$pool\qing_3.1.0.1",
               # state left by the older placeholder-file version after WPS re-downloaded the addon
               "$pool\kwpsbubble_3.1.0.9", "$pool\kwpsbubble_3.1.0.9.owps-off") {
    $null = New-Item -ItemType Directory -Force $d
}
'x' | Set-Content "$new\office6\wpscenter.exe"; 'x' | Set-Content "$new\wtoolex\wpsupdate.exe"; 'x' | Set-Content "$new\office6\wps.exe"
'dll' | Set-Content "$pool\kpromotionstrategy_3.1.0.1\a.dll"

function Check($cond, $msg) { if (-not $cond) { throw "FAIL: $msg" } else { Write-Host "ok  $msg" -ForegroundColor Green } }
function Fails([scriptblock]$b) { try { & $b; $false } catch { $true } }

try {
    & $script | Out-Null
    Check (Test-Path "$new\office6\addons\kwhatsnew.owps-off") 'ad addon disabled'
    Check (Test-Path "$new\office6\addons\kwpsnote") 'other addon untouched'
    Check (Test-Path "$new\office6\wpscenter.exe.owps-off") 'wpscenter disabled'
    Check (Test-Path "$new\office6\wps.exe") 'wps.exe untouched'
    Check (Test-Path "$pool\kpromotionstrategy_3.1.0.1.owps-off\a.dll") 'pool addon backed up'
    Check (Test-Path "$pool\kpromotionstrategy_3.1.0.1\owps.lock") 'pool addon locked'
    Check (Test-Path "$pool\kwpsbubble_3.1.0.9\owps.lock") 're-downloaded pool addon replaced by lock'
    Check (Test-Path "$pool\qing_3.1.0.1" -PathType Container) 'other pool addon untouched'

    # What WPS does to a placeholder: delete it, or write the download into it.
    $lock = "$pool\kpromotionstrategy_3.1.0.1"
    Check (Fails { Remove-Item -LiteralPath $lock -Recurse -Force }) 'lock survives recursive delete'
    Check (Fails { Remove-Item -LiteralPath "$lock\owps.lock" -Force }) 'lock file cannot be deleted'
    Check (Fails { Set-Content -LiteralPath "$lock\download.7z" -Value 'x' }) 'nothing can be written into the lock'
    Check (Test-Path "$lock\owps.lock") 'lock still in place'

    & $script 3>&1 | Out-String | ForEach-Object { Check ($_ -notmatch 'FAILED|skip') 'second run is a clean no-op' }

    & $script -Restore | Out-Null
    Check (Test-Path "$new\office6\addons\kwhatsnew" -PathType Container) 'addon restored'
    Check (Test-Path "$old\office6\addons\kwhatsnew" -PathType Container) 'old version folder restored too'
    Check (Test-Path "$new\office6\wpscenter.exe" -PathType Leaf) 'wpscenter restored'
    Check (Test-Path "$pool\kpromotionstrategy_3.1.0.1\a.dll") 'pool addon restored, lock gone'
    Check (Test-Path "$pool\kwpsbubble_3.1.0.9" -PathType Container) 're-downloaded addon restored'
    Check (-not (Get-ChildItem -Recurse $t -Force | Where-Object { $_.Name -like '*.owps-off' -or $_.Name -eq 'owps.lock' })) 'nothing left disabled'
    Write-Host "`nALL PASSED" -ForegroundColor Green
} finally {
    if (Test-Path $t) { & $script -Restore *> $null; Remove-Item -Recurse -Force $t }
}
