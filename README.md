# owps

Debloat WPS Office for Windows: ads, popups, tips, "what's new", message push, the updater and background tasks.

Every change can be undone. Files are renamed to `*.owps-off` and scheduled tasks are disabled, not deleted.

## Usage

Close every WPS window first. Then open PowerShell **as administrator** and run:

```powershell
irm https://raw.githubusercontent.com/KabosuNeko/owps/main/owps.ps1 | iex
```

A menu opens: debloat, debloat + block network, preview, or restore.

Without admin, the script still works but skips the service and firewall steps.

### Without the menu

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/KabosuNeko/owps/main/owps.ps1))) -Apply
```

Or from a local copy:

```powershell
powershell -ExecutionPolicy Bypass -File .\owps.ps1 -Apply -WhatIf     # preview only
powershell -ExecutionPolicy Bypass -File .\owps.ps1 -Apply             # debloat
powershell -ExecutionPolicy Bypass -File .\owps.ps1 -BlockNetwork      # + firewall-block ad/update exes (admin)
powershell -ExecutionPolicy Bypass -File .\owps.ps1 -Restore           # undo
```

## What it does

- Renames ad, popup, tip and push addons in `office6\addons` (the list is at the top of `owps.ps1`).
- Renames ad and popup addons that WPS downloads at runtime into `%APPDATA%\kingsoft\wps_intl\addons\pool`. WPS deletes and re-downloads these within seconds, so the old name is replaced by a locked folder (`owps.lock` inside, with NTFS deny rules for Everyone on delete and write). `-Restore` removes the locks. A newer version of an addon gets a new folder name, so run the script again if WPS fetches one.
- Renames `wpscenter.exe` (the notification center) and the updaters in `wtoolex`.
- Disables the `Wps*` scheduled tasks (updates and the external launcher).
- Sets the `wpscloudsvr` service to Disabled (admin).
- `-BlockNetwork` blocks outbound traffic for those background exes. `wps`, `et` and `wpp` keep network access for cloud and login.

Self-check (uses a fake WPS install in `%TEMP%` and touches nothing real):

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\test.ps1
```

Updates are turned off. To update WPS: run `-Restore`, update, then run the script again.
