# owps

Debloat WPS Office for Windows: ads, popups, tips, "what's new", message push and background tasks. Updates stay on, so WPS keeps getting security fixes.

Every change can be undone. Files are renamed to `*.owps-off` and scheduled tasks are disabled, not deleted.

## Usage

Close every WPS window first. Then open PowerShell **as administrator** and run:

```powershell
irm https://raw.githubusercontent.com/KabosuNeko/owps/main/owps.ps1 | iex
```

A menu opens: **[1]** debloat, **[2]** preview (changes nothing), **[3]** restore everything.

Admin is only needed for the scheduled tasks: WPS creates them so that only admins can change them. Without admin, everything else still works and the script tells you which tasks it skipped.

Run it again after WPS updates: an update installs a fresh copy with the ads back.

### Without the menu

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/KabosuNeko/owps/main/owps.ps1))) -Apply
```

Or from a local copy:

```powershell
powershell -ExecutionPolicy Bypass -File .\owps.ps1 -Apply -WhatIf   # preview only
powershell -ExecutionPolicy Bypass -File .\owps.ps1 -Apply           # debloat
powershell -ExecutionPolicy Bypass -File .\owps.ps1 -Restore         # undo
```

## What it does

- Renames ad, popup, tip and push addons in `office6\addons` (the list is at the top of `owps.ps1`).
- Renames ad and popup addons that WPS downloads at runtime into `%APPDATA%\kingsoft\wps_intl\addons\pool`. WPS deletes and re-downloads these within seconds, so the old name is replaced by a locked folder (`owps.lock` inside, with NTFS deny rules for Everyone on delete and write). A newer version of an addon gets a new folder name, so run the script again if WPS fetches one.
- Renames `wpscenter.exe` (the notification center).
- Disables the WPS background launcher tasks (`WpsExternal_*`). The update tasks stay on.

The locked folders cannot be deleted by hand. If you uninstall WPS, run restore afterwards (or before): it still cleans them up when WPS is gone.

## Self-check

Uses a fake WPS install in `%TEMP%` and fake processes and tasks, so it touches nothing real:

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\test.ps1
```
