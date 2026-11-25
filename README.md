# owps

Debloat WPS Office for Windows: ads, popups, tips, "what's new", message push, the updater and background tasks.

Every change can be undone. Files are renamed to `*.owps-off` and scheduled tasks are disabled, not deleted.

## Usage

Close every WPS window first, then in PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\owps.ps1 -WhatIf        # preview only
powershell -ExecutionPolicy Bypass -File .\owps.ps1                # debloat
powershell -ExecutionPolicy Bypass -File .\owps.ps1 -BlockNetwork  # + firewall-block ad/update exes (admin)
powershell -ExecutionPolicy Bypass -File .\owps.ps1 -Restore       # undo
```

The service and firewall steps need an admin PowerShell. Without admin, the script skips them.

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
