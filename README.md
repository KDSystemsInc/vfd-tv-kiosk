# vfd-tv-kiosk

Watchdog for the RedNMX Bulletin TV kiosks. If the Bulletin keeps logging "Could not connect" for
7+ minutes while the database port answers (the app does not recover from a mid-session Wi-Fi drop),
it restarts the app. Runs every 5 minutes as SYSTEM from `C:\ProgramData\KDSystems`, never from this
repo directly. Actions are logged to `C:\Data\bulletin-watchdog.log`.

## Install or update

Elevated PowerShell on the kiosk. Pin to a release tag; re-run with a newer tag to update.

```powershell
$v='v1.0.0'; $f="$env:TEMP\bulletin-watchdog.ps1"; iwr "https://raw.githubusercontent.com/KDSystemsInc/vfd-tv-kiosk/$v/bulletin-watchdog.ps1" -OutFile $f -UseBasicParsing; powershell -ExecutionPolicy Bypass -File $f -Install
```

Check: `Get-ScheduledTask 'RedNMX Bulletin Watchdog' | Get-ScheduledTaskInfo`

Remove: `Unregister-ScheduledTask 'RedNMX Bulletin Watchdog' -Confirm:$false`

## Release

Tag every change (`git tag v1.0.1 && git push --tags`) and install by tag, not `main`.
