<#
.SYNOPSIS
  owps - debloat WPS Office (ads, popups, tips, background tasks). Updates stay on.

.DESCRIPTION
  Every change is reversible: files/folders are renamed with the ".owps-off" suffix,
  scheduled tasks are disabled (not deleted). Run with -Restore to undo.
  Close all WPS windows first (the script refuses to run while WPS has documents open).
  Without switches it shows a menu, which is what `irm <url> | iex` gets.
  Run as admin: WPS's scheduled tasks can only be changed by admins. Everything else works without.

.EXAMPLE
  irm https://raw.githubusercontent.com/KabosuNeko/owps/main/owps.ps1 | iex   # menu
  .\owps.ps1                  # menu
  .\owps.ps1 -Apply           # debloat, no menu
  .\owps.ps1 -Apply -WhatIf   # preview, changes nothing
  .\owps.ps1 -Restore         # undo everything (also works after WPS is uninstalled)
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Apply,
    [switch]$Restore
)

# Everything lives in a function: under `irm | iex` the script has no $PSCmdlet of its own.
function Invoke-Owps {
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Restore
)
$ErrorActionPreference = 'Stop'
$Suffix = '.owps-off'

# Built-in addons (<version>\office6\addons\<name>) that only serve ads, popups, tips, promos or push messages.
$Addons = @(
    'kwebmemberrenewalpopup', 'kcorppromotipsmgr', 'ktipsmanager', 'ktipsclientmanager',
    'kwhatsnew', 'kwebwhatsnew', 'koperationstrategy', 'koperationdocstrategy',
    'kmessagecentersdk', 'kmessagecentersrv', 'kwebmessagecenterpanel', 'messagepush',
    'cloudpushsdk', 'kaipushsdk', 'kwebknovicetask', 'kloginwelcome',
    'kpromeappmarket', 'kappmarket', 'kfileradarguide', 'kassosettingguide'
)
# Addons WPS downloads at runtime into %APPDATA%\kingsoft\wps_intl\addons\pool\<arch>\<name>_<version>.
$PoolAddons = @(
    'koperationstrategy', 'kpromotionstrategy', 'kwebstartupoperation', 'kwebdocumentoperation',
    'klearningtips', 'kstartguide', 'kwpsbubble', 'kpromeforceclosedlg'
)
# Executables: the notification center.
$Exes = @('office6\wpscenter.exe')

$Root = Join-Path $env:LOCALAPPDATA 'Kingsoft\WPS Office'
$Pool = Join-Path $env:APPDATA 'kingsoft\wps_intl\addons\pool'

# All version folders: old ones stay after updates, and -Restore must reach files disabled in any of them.
$VerDirs = @(if (Test-Path -LiteralPath $Root) {
    Get-ChildItem -LiteralPath $Root -Directory |
        Where-Object { $_.Name -match '^\d+(\.\d+){1,3}$' -and (Test-Path -LiteralPath (Join-Path $_.FullName 'office6')) } |
        Sort-Object { [version]$_.Name } -Descending
})
# Restore must still unlock the pool after WPS is uninstalled, or the locked folders can never be deleted.
if ($VerDirs) { Write-Host "WPS $($VerDirs[0].Name) at $Root" -ForegroundColor Cyan }
elseif ($Restore) { Write-Host "WPS not installed, cleaning up leftovers only" -ForegroundColor Cyan }
else { throw "WPS Office not found at $Root" }

$state = @{ Failed = 0; NeedsAdmin = $false }

# WPS also runs windowless helpers as `wps.exe Run -Entry=...` (CEF, cloud, aspcenter); those are safe to stop.
# Anything else with an editor name is a real window that may hold unsaved documents: never kill it.
$helpers = @(); $editors = @()
foreach ($p in @(Get-Process wps, et, wpp, wpspdf, wpsoffice -ErrorAction SilentlyContinue)) {
    $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId=$($p.Id)" -ErrorAction SilentlyContinue).CommandLine
    if ($p.MainWindowHandle -eq 0 -and $cmd -match '\.exe"?\s+Run\s') { $helpers += $p } else { $editors += $p }
}
if ($editors) {
    if ($WhatIfPreference) { Write-Warning 'WPS is open (fine for -WhatIf; close it before the real run).' }
    else { throw 'WPS is open. Save your work, close every WPS window, then run again.' }
}
@($helpers) + @(Get-Process wpscenter, wpscloudsvr, promecefpluginhost -ErrorAction SilentlyContinue) |
    Where-Object { $_ -and $_.Path -like '*\Kingsoft\*' } | ForEach-Object {
        if ($PSCmdlet.ShouldProcess("$($_.Name) ($($_.Id))", 'Stop process')) {
            try { Stop-Process -Id $_.Id -Force } catch { Write-Warning "  cannot stop $($_.Name): $_" }
        }
    }

# Disable: rename to <name>.owps-off. Restore: rename back.
function Switch-Item([string]$Path) {
    $off = $Path + $Suffix
    $leaf = Split-Path $Path -Leaf
    try {
        if (-not $Restore) {
            if (-not (Test-Path -LiteralPath $Path)) { return }
            if (-not $PSCmdlet.ShouldProcess($Path, 'Disable')) { return }
            # Both exist after a WPS repair/reinstall: the old backup is stale, the fresh copy becomes the backup.
            if (Test-Path -LiteralPath $off) { Remove-Item -LiteralPath $off -Recurse -Force }
            Rename-Item -LiteralPath $Path -NewName ($leaf + $Suffix)
            Write-Host "  disabled $Path"
        } else {
            if (-not (Test-Path -LiteralPath $off)) { return }
            if (-not $PSCmdlet.ShouldProcess($Path, 'Restore')) { return }
            if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $off -Recurse -Force }  # WPS already has a live copy
            else { Rename-Item -LiteralPath $off -NewName $leaf }
            Write-Host "  restored $Path"
        }
    } catch { $state.Failed++; Write-Warning "  FAILED $Path : $($_.Exception.Message)" }
}

# Downloaded addons come back within seconds (WPS deletes any plain placeholder and re-downloads),
# so the old name gets a folder that Everyone is denied to delete, rename-into or write.
# The owner (you) can still change permissions, which is how -Restore removes it.
$Everyone = New-Object Security.Principal.SecurityIdentifier 'S-1-1-0'
$LockFile = 'owps.lock'
function Set-Deny([string]$Path, [Security.AccessControl.FileSystemRights]$Rights) {
    $i = Get-Item -LiteralPath $Path -Force
    $acl = $i.GetAccessControl('Access')
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($Everyone, $Rights, 'Deny')))
    $i.SetAccessControl($acl)
}
function Clear-Deny([string]$Path) {
    $i = Get-Item -LiteralPath $Path -Force
    $acl = $i.GetAccessControl('Access'); $acl.PurgeAccessRules($Everyone); $i.SetAccessControl($acl)
}
function Test-Lock([string]$Path) { Test-Path -LiteralPath (Join-Path $Path $LockFile) }

function Switch-PoolItem([string]$Path) {
    $off = $Path + $Suffix
    $leaf = Split-Path $Path -Leaf
    try {
        if (-not $Restore) {
            if (Test-Lock $Path) { return }
            if (-not $PSCmdlet.ShouldProcess($Path, 'Disable and lock')) { return }
            if (Test-Path -LiteralPath $Path) {
                # WPS re-downloaded it (e.g. after a lock was removed by hand): the backup already has it.
                if (Test-Path -LiteralPath $off) { Remove-Item -LiteralPath $Path -Recurse -Force }
                else { Rename-Item -LiteralPath $Path -NewName ($leaf + $Suffix) }
            }
            $null = New-Item -ItemType Directory -Path $Path
            Set-Content -LiteralPath (Join-Path $Path $LockFile) -Value 'Blocked by owps. Run owps.ps1 -Restore to undo.'
            Set-Deny (Join-Path $Path $LockFile) 'Delete, Write'
            Set-Deny $Path 'Delete, DeleteSubdirectoriesAndFiles, CreateFiles, CreateDirectories'
            Write-Host "  disabled $Path"
        } else {
            if (-not ((Test-Lock $Path) -or (Test-Path -LiteralPath $off))) { return }
            if (-not $PSCmdlet.ShouldProcess($Path, 'Restore')) { return }
            if (Test-Lock $Path) {
                Clear-Deny $Path; Clear-Deny (Join-Path $Path $LockFile); Remove-Item -LiteralPath $Path -Recurse -Force
            }
            if (Test-Path -LiteralPath $off) {
                if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $off -Recurse -Force }  # WPS already has a live copy
                else { Rename-Item -LiteralPath $off -NewName $leaf }
            }
            Write-Host "  restored $Path"
        }
    } catch { $state.Failed++; Write-Warning "  FAILED $Path : $($_.Exception.Message)" }
}

Write-Host 'Built-in addons and executables:' -ForegroundColor Cyan
# Debloat touches the newest version only; restore walks every version folder.
foreach ($v in $(if ($Restore) { $VerDirs } else { $VerDirs[0] })) {
    $Addons | ForEach-Object { Switch-Item (Join-Path $v.FullName "office6\addons\$_") }
    $Exes | ForEach-Object { Switch-Item (Join-Path $v.FullName $_) }
}

Write-Host 'Downloaded addons:' -ForegroundColor Cyan
if (Test-Path -LiteralPath $Pool) {
    $pattern = '^(' + (($PoolAddons | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')_[\d.]+$'
    Get-ChildItem -LiteralPath $Pool -Directory | ForEach-Object {
        $arch = $_.FullName
        $names = Get-ChildItem -LiteralPath $arch -Force | ForEach-Object { $_.Name -replace ([regex]::Escape($Suffix) + '$'), '' } | Sort-Object -Unique
        $names | Where-Object { $_ -match $pattern } | ForEach-Object { Switch-PoolItem (Join-Path $arch $_) }
    }
}

Write-Host 'Scheduled tasks:' -ForegroundColor Cyan
# Only tasks whose action runs something from the WPS folder. Update tasks stay on, so WPS gets security fixes.
Get-ScheduledTask | Where-Object { $_.Actions | Where-Object { "$($_.Execute)".Trim('"') -like "$Root\*" } } | ForEach-Object {
    $enable = $Restore -or ($_.Actions | Where-Object { "$($_.Arguments)" -match 'wpsupdate' })
    if ([bool]$enable -eq ($_.State -ne 'Disabled')) { return }  # already as wanted
    $act = if ($enable) { 'Enable' } else { 'Disable' }
    $task = $_
    if ($PSCmdlet.ShouldProcess($task.TaskName, "$act task")) {
        try {
            if ($enable) { $null = $task | Enable-ScheduledTask } else { $null = $task | Stop-ScheduledTask; $null = $task | Disable-ScheduledTask }
            Write-Host "  ${act}d $($task.TaskName)"
        } catch {
            # WPS creates its tasks so that only admins can change them; re-running without admin never helps.
            if ($_.CategoryInfo.Category -eq 'PermissionDenied' -or "$($_.FullyQualifiedErrorId)" -like '*0x80070005*') {
                $state.NeedsAdmin = $true; Write-Warning "  $($task.TaskName): needs admin, skipped"
            } else { $state.Failed++; Write-Warning "  FAILED $($task.TaskName): $($_.Exception.Message)" }
        }
    }
}

if ($state.NeedsAdmin) { Write-Host "`nWPS scheduled tasks can only be changed as admin. Open PowerShell as administrator and run again." -ForegroundColor Yellow }
if ($state.Failed) { Write-Host "`n$($state.Failed) item(s) failed, see warnings above. Re-run after closing WPS." -ForegroundColor Yellow }
if ($state.NeedsAdmin -or $state.Failed) { return }
Write-Host "`nDone. $(if ($Restore) { 'Restored.' } else { 'Run with -Restore to undo.' })" -ForegroundColor Green
}

function Show-OwpsMenu {
    while ($true) {
        Write-Host ''
        Write-Host '  owps - WPS Office debloat' -ForegroundColor Cyan
        Write-Host '  [1] Debloat'
        Write-Host '  [2] Preview, change nothing'
        Write-Host '  [3] Restore everything'
        Write-Host '  [0] Exit'
        $choice = Read-Host '  Choose'
        try {
            switch ($choice) {
                '1' { Invoke-Owps }
                '2' { Invoke-Owps -WhatIf }
                '3' { Invoke-Owps -Restore }
                '0' { return }
            }
        } catch { Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red }
    }
}

if ($Apply -or $Restore -or $WhatIfPreference) {
    $opts = @{} + $PSBoundParameters; $opts.Remove('Apply')
    Invoke-Owps @opts
} else {
    Show-OwpsMenu
}
