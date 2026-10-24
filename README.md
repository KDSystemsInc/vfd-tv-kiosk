# vfd-tv-kiosk

Deploy + control scripts for the RedNMX Bulletin TV kiosks.

- **bulletin-watchdog.ps1** — restarts the Bulletin if it stays stuck on "Could not connect"
  for 7+ min while the DB port answers (the app does not recover from a mid-session Wi-Fi drop).
- **start-bulletin.cmd** — the Shell Launcher wrapper: checks the suspend flag, waits for the
  DB, then launches the Bulletin.
- **suspend.json** — the remote off switch (see below).
- **suspended.html** — the page shown while suspended.

## Remote off switch

`suspend.json` on the **main** branch lists kiosks (by Windows COMPUTERNAME) that should be
suspended. A suspended kiosk shows `suspended.html` instead of the Bulletin and rechecks every
5 minutes, so toggling is just an edit to that file:

```json
{ "suspended": ["SOME-PC"] }
```

Empty list = everything runs. **Fail-open by design:** if the kiosk cannot fetch the flag
(GitHub down, no internet), it launches the Bulletin normally. The switch is nonpayment
leverage, not DRM; someone with local access can defeat it, and that tradeoff is deliberate so
an outage can never blank a board on its own.

> **Safety:** never list a machine that shows the **live dispatch call board**. Firefighters use
> that board to respond to active incidents. Suspend only informational boards (weather / history
> / events). Find a machine's name with `$env:COMPUTERNAME`.

## Install / update (elevated PowerShell, per kiosk)

Pin to a release tag. Re-run with a newer tag to update.

```powershell
$v='v1.1.0'
$b="https://raw.githubusercontent.com/KDSystemsInc/vfd-tv-kiosk/$v"
foreach ($f in 'start-bulletin.cmd','suspended.html') { iwr "$b/$f" -OutFile "C:\Data\$f" -UseBasicParsing }
iwr "$b/bulletin-watchdog.ps1" -OutFile "$env:TEMP\wd.ps1" -UseBasicParsing
powershell -ExecutionPolicy Bypass -File "$env:TEMP\wd.ps1" -Install
```

Shell Launcher already points at `C:\Data\start-bulletin.cmd`, so no Shell Launcher change is
needed. If Syncthing also feeds `C:\Data`, put the new `start-bulletin.cmd` / `suspended.html` on
the NAS too, or stop syncing them, so Syncthing does not overwrite the installed copies.

The **code** is pinned by tag; only `suspend.json` is read live from `main`.

## Release

Tag every change (`git tag v1.1.1 && git push --tags`) and install by tag, not `main`.
