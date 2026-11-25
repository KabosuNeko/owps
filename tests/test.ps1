# Self-check: runs owps.ps1 against a fake WPS install in %TEMP%. Processes and scheduled tasks are
# stubbed with fakes, so nothing real is touched. Run: powershell -ExecutionPolicy Bypass -File tests\test.ps1
$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot '..\owps.ps1'
$t = Join-Path $env:TEMP "owps-test-$PID"
$env:LOCALAPPDATA = "$t\Local"; $env:APPDATA = "$t\Roaming"

$root = "$t\Local\Kingsoft\WPS Office"
$new = "$root\12.1.0.200"
$old = "$root\12.1.0.100"
$pool = "$t\Roaming\kingsoft\wps_intl\addons\pool\win-x64"
foreach ($d in "$new\office6\addons\kwhatsnew", "$new\office6\addons\kwpsnote",
               "$old\office6\addons\kwhatsnew.owps-off", "$pool\kpromotionstrategy_3.1.0.1", "$pool\qing_3.1.0.1",
               # WPS re-downloaded an addon whose backup we already keep (e.g. a lock removed by hand)
               "$pool\kwpsbubble_3.1.0.9", "$pool\kwpsbubble_3.1.0.9.owps-off") {
    $null = New-Item -ItemType Directory -Force $d
}
'x' | Set-Content "$new\office6\wpscenter.exe"; 'x' | Set-Content "$new\office6\wps.exe"
'dll' | Set-Content "$pool\kpromotionstrategy_3.1.0.1\a.dll"

# Fake processes. Command lines are real ones seen on a WPS 12.1 machine.
$exe = "$new\office6\wps.exe"
function P($id, $name, $window, $cmd) { [pscustomobject]@{ Id = $id; Name = $name; MainWindowHandle = $window; Path = "$new\office6\$name.exe"; Cmd = $cmd } }
$cefRenderer = P 101 wps 0 "`"$exe`" Run /AppUserModelID=Kingsoft.Office.cefhomepage -Entry=CefRenderEntryPoint --type=renderer"
$aspcenter   = P 102 wps 0 "`"$exe`"  Run -Entry=EntryPoint C:\pool\aspcenter_3.1.0.1264/aspcenter.dll --host"
$center      = P 103 wpscenter 0 "`"$new\office6\wpscenter.exe`""
$editor      = P 201 wps 4242 "`"$exe`" `"C:\Users\me\Documents\Run report.docx`""
$noWindowDoc = P 202 et 0 "`"$new\office6\et.exe`" `"C:\Users\me\Run.xlsx`""
# Plain names (not $script:): owps.ps1 is its own script scope, so the stubs find these by normal lookup.
$FakeProcs = @(); $Stopped = [System.Collections.ArrayList]::new()
function Get-Process { param([Parameter(Position = 0)][string[]]$Name) $FakeProcs | Where-Object { $Name -contains $_.Name } }
function Get-CimInstance { param($ClassName, $Filter, $ErrorAction)
    $id = [int]($Filter -replace '\D', ''); [pscustomobject]@{ CommandLine = ($FakeProcs | Where-Object Id -eq $id).Cmd } }
function Stop-Process { param($Id, [switch]$Force) $null = $Stopped.Add($Id) }

# Fake scheduled tasks, shaped like the real WPS ones.
function T($name, $state, $exePath, $arguments) { [pscustomobject]@{ TaskName = $name; State = $state; Actions = @([pscustomobject]@{ Execute = $exePath; Arguments = $arguments }) } }
$updateTask = T WpsUpdateTask_me Disabled "$root\ksolaunch.exe" '/wpsupdate -from=task -source=task'
$extTask    = T WpsExternal_me_interval Ready "$new\office6\wpscloudsvr.exe" '/wpscloudlaunch /run_plugin /task=wpsexternal'
$otherTask  = T SomeOtherApp Ready 'C:\Other\app.exe' '/wpsupdate'
$FakeTasks = @($updateTask, $extTask, $otherTask)
function Get-ScheduledTask { $FakeTasks }
function Enable-ScheduledTask { process { $_.State = 'Ready' } }
$Deny = @{ Tasks = $false }  # true: behave like a non-admin, whom WPS's task permissions refuse
function Disable-ScheduledTask { process {
    if ($Deny.Tasks) { Write-Error -Message 'Access is denied.' -Category PermissionDenied -ErrorId 'HRESULT 0x80070005' -ErrorAction Stop }
    $_.State = 'Disabled' } }
function Stop-ScheduledTask { process { } }

function Check($cond, $msg) { if (-not $cond) { throw "FAIL: $msg" } else { Write-Host "ok  $msg" -ForegroundColor Green } }
function Fails([scriptblock]$b) { try { & $b; $false } catch { $true } }

try {
    # An open document must stop the run before anything is touched.
    foreach ($ed in $editor, $noWindowDoc) {
        $FakeProcs = @($cefRenderer, $ed); $Stopped.Clear()
        Check (Fails { & $script -Apply *> $null }) "refuses to run while '$($ed.Cmd)' is open"
        Check (-not $Stopped) '  ...and stops no process'
    }
    Check (Test-Path "$new\office6\addons\kwhatsnew") 'nothing renamed while WPS was open'

    # Without admin: addons still get disabled, the task is skipped with a clear hint, nothing counts as failed.
    $FakeProcs = @(); $Deny.Tasks = $true
    $out = & $script -Apply 3>&1 6>&1 | Out-String
    $Deny.Tasks = $false
    Check ($out -match 'Open PowerShell as administrator' -and $out -notmatch 'FAILED|Re-run after closing') 'non-admin gets the admin hint, not a failure'
    Check ($extTask.State -eq 'Ready' -and (Test-Path "$new\office6\addons\kwhatsnew.owps-off")) '  ...task untouched, addons still disabled'

    $FakeProcs = @($cefRenderer, $aspcenter, $center); $Stopped.Clear()
    & $script -Apply | Out-Null
    Check (($Stopped | Sort-Object) -join ',' -eq '101,102,103') 'windowless helpers and wpscenter stopped'
    Check (Test-Path "$new\office6\addons\kwhatsnew.owps-off") 'ad addon disabled'
    Check (Test-Path "$new\office6\addons\kwpsnote") 'other addon untouched'
    Check (Test-Path "$new\office6\wpscenter.exe.owps-off") 'wpscenter disabled'
    Check (Test-Path "$new\office6\wps.exe") 'wps.exe untouched'
    Check (Test-Path "$pool\kpromotionstrategy_3.1.0.1.owps-off\a.dll") 'pool addon backed up'
    Check (Test-Path "$pool\kpromotionstrategy_3.1.0.1\owps.lock") 'pool addon locked'
    Check (Test-Path "$pool\kwpsbubble_3.1.0.9\owps.lock") 're-downloaded pool addon replaced by lock'
    Check (Test-Path "$pool\qing_3.1.0.1" -PathType Container) 'other pool addon untouched'
    Check ($updateTask.State -eq 'Ready') 'update task turned on'
    Check ($extTask.State -eq 'Disabled') 'background launcher task disabled'
    Check ($otherTask.State -eq 'Ready') 'task of another app untouched'

    # What WPS does to a placeholder: delete it, or write the download into it.
    $lock = "$pool\kpromotionstrategy_3.1.0.1"
    Check (Fails { Remove-Item -LiteralPath $lock -Recurse -Force }) 'lock survives recursive delete'
    Check (Fails { Remove-Item -LiteralPath "$lock\owps.lock" -Force }) 'lock file cannot be deleted'
    Check (Fails { Set-Content -LiteralPath "$lock\download.7z" -Value 'x' }) 'nothing can be written into the lock'
    Check (Test-Path "$lock\owps.lock") 'lock still in place'

    $FakeProcs = @()
    & $script -Apply 3>&1 | Out-String | ForEach-Object { Check ($_ -notmatch 'FAILED|skip|abled ') 'second run is a clean no-op' }

    & $script -Restore | Out-Null
    Check (Test-Path "$new\office6\addons\kwhatsnew" -PathType Container) 'addon restored'
    Check (Test-Path "$old\office6\addons\kwhatsnew" -PathType Container) 'old version folder restored too'
    Check (Test-Path "$new\office6\wpscenter.exe" -PathType Leaf) 'wpscenter restored'
    Check (Test-Path "$pool\kpromotionstrategy_3.1.0.1\a.dll") 'pool addon restored, lock gone'
    Check (Test-Path "$pool\kwpsbubble_3.1.0.9" -PathType Container) 're-downloaded addon restored'
    Check ($extTask.State -eq 'Ready' -and $updateTask.State -eq 'Ready') 'tasks turned back on'
    Check (-not (Get-ChildItem -Recurse $t -Force | Where-Object { $_.Name -like '*.owps-off' -or $_.Name -eq 'owps.lock' })) 'nothing left disabled'

    # Uninstalling WPS without restoring first must not strand undeletable locks.
    & $script -Apply | Out-Null
    Remove-Item -Recurse -Force "$t\Local"
    & $script -Restore | Out-Null
    Check (-not (Get-ChildItem -Recurse $pool -Force -Filter owps.lock)) 'restore removes locks after WPS is uninstalled'
    Check (Test-Path "$pool\kpromotionstrategy_3.1.0.1\a.dll") '  ...and puts the addon back'
    Write-Host "`nALL PASSED" -ForegroundColor Green
} finally {
    # Not via owps -Restore: if the script under test is broken, its locks would stay in %TEMP% forever.
    if (Test-Path $t) { icacls $t /reset /T /C /Q *> $null; Remove-Item -Recurse -Force $t }
}
