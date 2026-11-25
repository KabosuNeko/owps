<#
.SYNOPSIS
  owps - debloat WPS Office (ads, popups, tips, updater, background tasks).

.DESCRIPTION
  Every change is reversible: files/folders are renamed with the ".owps-off" suffix,
  scheduled tasks are disabled (not deleted). Run with -Restore to undo.
  Close all WPS windows first (the script refuses to run while WPS has documents open).
  Without switches it shows a menu, which is what `irm <url> | iex` gets.

.EXAMPLE
  irm https://raw.githubusercontent.com/KabosuNeko/owps/main/owps.ps1 | iex   # menu
  .\owps.ps1                  # menu
  .\owps.ps1 -Apply           # debloat, no menu
  .\owps.ps1 -Apply -WhatIf   # preview, changes nothing
  .\owps.ps1 -BlockNetwork    # debloat + firewall-block ad/update executables (needs admin)
  .\owps.ps1 -Restore         # undo everything
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Apply,
    [switch]$Restore,
    [switch]$BlockNetwork
)

# Everything lives in a function: under `irm | iex` the script has no $PSCmdlet of its own.
function Invoke-Owps {
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Restore,
    [switch]$BlockNetwork
)
$ErrorActionPreference = 'Stop'
$Suffix = '.owps-off'
$FwPrefix = 'owps-block-'

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
# Executables: notification center + updaters.
$Exes = @('office6\wpscenter.exe', 'wtoolex\wpsupdate.exe', 'wtoolex\updateself.exe', 'wtoolex\updatepolicy.exe')
# Blocked from the internet with -BlockNetwork (wps/et/wpp keep network for cloud/login).
$NetExes = @('office6\wpscenter.exe', 'office6\wpscloudsvr.exe', 'office6\promecefpluginhost.exe',
             'wtoolex\wpsupdate.exe', 'wtoolex\updateself.exe', 'wtoolex\updatepolicy.exe')

$Root = Join-Path $env:LOCALAPPDATA 'Kingsoft\WPS Office'
$Pool = Join-Path $env:APPDATA 'kingsoft\wps_intl\addons\pool'
$SvcExe = Join-Path $env:ProgramFiles 'Kingsoft\office6\wpscloudsvr.exe'

if (-not (Test-Path -LiteralPath $Root)) { throw "WPS Office not found at $Root" }
# All version folders: old ones stay after updates, and -Restore must reach files disabled in any of them.
$VerDirs = @(Get-ChildItem -LiteralPath $Root -Directory |
    Where-Object { $_.Name -match '^\d+(\.\d+){1,3}$' -and (Test-Path -LiteralPath (Join-Path $_.FullName 'office6')) } |
    Sort-Object { [version]$_.Name } -Descending)
if (-not $VerDirs) { throw "No WPS version folder under $Root" }
Write-Host "WPS $($VerDirs[0].Name) at $Root" -ForegroundColor Cyan

$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
$state = @{ Failed = 0 }

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
@($helpers) + @(Get-Process wpscenter, wpscloudsvr, promecefpluginhost, wpsupdate, updateself -ErrorAction SilentlyContinue) |
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
            if (Test-Path -LiteralPath $off) { Write-Warning "  skip, already disabled copy exists: $off"; return }
            if (-not $PSCmdlet.ShouldProcess($Path, 'Disable')) { return }
            Rename-Item -LiteralPath $Path -NewName ($leaf + $Suffix)
            Write-Host "  disabled $Path"
        } else {
            if (-not (Test-Path -LiteralPath $off)) { return }
            if (Test-Path -LiteralPath $Path) { throw 'original name is taken (WPS re-installed it?)' }
            if (-not $PSCmdlet.ShouldProcess($Path, 'Restore')) { return }
            Rename-Item -LiteralPath $off -NewName $leaf
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
function Remove-Lock([string]$Path) {
    Clear-Deny $Path; Clear-Deny (Join-Path $Path $LockFile); Remove-Item -LiteralPath $Path -Recurse -Force
}

function Switch-PoolItem([string]$Path) {
    $off = $Path + $Suffix
    $leaf = Split-Path $Path -Leaf
    try {
        if (-not $Restore) {
            if (Test-Lock $Path) { return }
            if (-not $PSCmdlet.ShouldProcess($Path, 'Disable and lock')) { return }
            if (Test-Path -LiteralPath $Path -PathType Leaf) { Remove-Item -LiteralPath $Path -Force }  # placeholder from older owps
            if (Test-Path -LiteralPath $Path) {
                # A copy WPS re-downloaded is a duplicate of the backup we already keep.
                if (Test-Path -LiteralPath $off) { Remove-Item -LiteralPath $Path -Recurse -Force }
                else { Rename-Item -LiteralPath $Path -NewName ($leaf + $Suffix) }
            }
            $null = New-Item -ItemType Directory -Path $Path
            Set-Content -LiteralPath (Join-Path $Path $LockFile) -Value 'Blocked by owps. Run owps.ps1 -Restore to undo.'
            Set-Deny (Join-Path $Path $LockFile) 'Delete, Write'
            Set-Deny $Path 'Delete, DeleteSubdirectoriesAndFiles, CreateFiles, CreateDirectories'
            Write-Host "  disabled $Path"
        } else {
            if (-not ((Test-Lock $Path) -or (Test-Path -LiteralPath $off) -or (Test-Path -LiteralPath $Path -PathType Leaf))) { return }
            if (-not $PSCmdlet.ShouldProcess($Path, 'Restore')) { return }
            if (Test-Lock $Path) { Remove-Lock $Path }
            elseif (Test-Path -LiteralPath $Path -PathType Leaf) { Remove-Item -LiteralPath $Path -Force }
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
# Only tasks whose action runs something from the WPS folder.
Get-ScheduledTask | Where-Object { $_.Actions | Where-Object { "$($_.Execute)".Trim('"') -like "$Root\*" } } | ForEach-Object {
    $act = if ($Restore) { 'Enable' } else { 'Disable' }
    if ($PSCmdlet.ShouldProcess($_.TaskName, "$act task")) {
        try {
            if ($Restore) { $null = $_ | Enable-ScheduledTask } else { $null = $_ | Stop-ScheduledTask; $null = $_ | Disable-ScheduledTask }
            Write-Host "  ${act}d $($_.TaskName)"
        } catch { $state.Failed++; Write-Warning "  FAILED $($_.TaskName): $($_.Exception.Message)" }
    }
}

Write-Host 'Service wpscloudsvr:' -ForegroundColor Cyan
if (-not (Get-Service wpscloudsvr -ErrorAction SilentlyContinue)) { Write-Host '  not installed' }
elseif (-not $IsAdmin) { Write-Warning '  needs admin, skipped' }
else {
    $mode = if ($Restore) { 'Manual' } else { 'Disabled' }  # Manual is the WPS default
    if ($PSCmdlet.ShouldProcess('wpscloudsvr', "Set startup $mode")) {
        try {
            if (-not $Restore) { Stop-Service wpscloudsvr -Force -ErrorAction SilentlyContinue }
            Set-Service wpscloudsvr -StartupType $mode; Write-Host "  startup = $mode"
        } catch { $state.Failed++; Write-Warning "  FAILED: $($_.Exception.Message)" }
    }
}

if ($BlockNetwork -or $Restore) {
    Write-Host 'Firewall:' -ForegroundColor Cyan
    if (-not $IsAdmin) { Write-Warning '  needs admin, skipped' }
    elseif ($Restore) {
        Get-NetFirewallRule -DisplayName "$FwPrefix*" -ErrorAction SilentlyContinue | ForEach-Object {
            if ($PSCmdlet.ShouldProcess($_.DisplayName, 'Remove firewall rule')) {
                Remove-NetFirewallRule -Name $_.Name; Write-Host "  removed $($_.DisplayName)"
            }
        }
    }
    else {
        $existing = @(Get-NetFirewallRule -DisplayName "$FwPrefix*" -ErrorAction SilentlyContinue |
            Get-NetFirewallApplicationFilter | ForEach-Object { $_.Program })
        $paths = @($NetExes | ForEach-Object { Join-Path $VerDirs[0].FullName $_ }) + $SvcExe
        foreach ($p in $paths) {
            if ($existing -contains $p) { continue }
            # Targets the original path, so the rule also covers the file after a -Restore.
            if ($PSCmdlet.ShouldProcess($p, 'Block outbound')) {
                $null = New-NetFirewallRule -DisplayName ($FwPrefix + (Split-Path $p -Leaf)) -Direction Outbound -Action Block -Program $p
                Write-Host "  blocked $p"
            }
        }
    }
}

if ($state.Failed) { Write-Host "`n$($state.Failed) item(s) failed, see warnings above. Re-run after closing WPS." -ForegroundColor Yellow; return }
Write-Host "`nDone. $(if ($Restore) { 'Restored.' } else { 'Run with -Restore to undo.' })" -ForegroundColor Green
}

function Show-OwpsMenu {
    $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    while ($true) {
        Write-Host ''
        Write-Host '  owps - WPS Office debloat' -ForegroundColor Cyan
        if (-not $admin) { Write-Host '  (not admin: the service and firewall steps will be skipped)' -ForegroundColor Yellow }
        Write-Host '  [1] Debloat'
        Write-Host '  [2] Debloat + block internet for background exes (admin)'
        Write-Host '  [3] Preview, change nothing'
        Write-Host '  [4] Restore everything'
        Write-Host '  [0] Exit'
        $choice = Read-Host '  Choose'
        try {
            switch ($choice) {
                '1' { Invoke-Owps }
                '2' { Invoke-Owps -BlockNetwork }
                '3' { Invoke-Owps -WhatIf }
                '4' { Invoke-Owps -Restore }
                '0' { return }
            }
        } catch { Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red }
    }
}

if ($Apply -or $Restore -or $BlockNetwork -or $WhatIfPreference) {
    $opts = @{} + $PSBoundParameters; $opts.Remove('Apply')
    Invoke-Owps @opts
} else {
    Show-OwpsMenu
}
