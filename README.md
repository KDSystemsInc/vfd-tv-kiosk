# vfd-tv-kiosk

Scripts for the RedNMX Bulletin TV kiosks. Kiosks install signed releases automatically.

| File | What it does |
|---|---|
| `update.ps1` | Every 6 h as SYSTEM: installs a new release if its signature and hashes check out; otherwise keeps the current one. Also keeps the tasks and Shell Launcher entry in place. |
| `start-bulletin.ps1` | Shell Launcher wrapper: suspend check, wait for the DB, run the Bulletin. |
| `bulletin-watchdog.ps1` | Every 5 min: restarts the Bulletin if it is stuck on "Could not connect" while the DB answers. |
| `roku-watch.ps1` | Every 5 min, only on kiosks with a Roku TV (`C:\ProgramData\KDSystems\roku.txt` holds its IP): wakes the TV and fixes input/screensaver, sending nothing when the TV is fine. |
| `suspend.json` / `suspended.html` | Remote suspend switch and the page it shows. |
| `offboard.ps1` | Removes everything above and restores the stock Bulletin launch. |
| `release.sh` | Signs and publishes a release (run on Kevin's Mac). |

Installed files live in `C:\ProgramData\KDSystems` (admin-only writes). Logs go to `C:\Data`
(`kds-update.log`, `bulletin-watchdog.log`, `start-bulletin.log`) so Syncthing carries them to the NAS.

## Releasing

```bash
./release.sh 1.2.1
```

Writes `manifest.json` (version + SHA-256 of each file), signs it with the private key in the
macOS Keychain (`kds-kiosk-signing`), tags, and pushes. Kiosks pick it up within 6 hours.
Kiosks reject anything that key did not sign and never move to an older version. If a download or
check fails they keep running what they have, so deleting files from this repo does not disable
anything. To remove the software from a kiosk, run `offboard.ps1`.

## New kiosk (once, elevated PowerShell)

Use the bootstrap line `release.sh` prints. It checks the downloaded `update.ps1` against a pinned
hash, installs, and registers the tasks. Reboot afterwards so Shell Launcher uses the new wrapper.

## Suspend switch

List a kiosk's `COMPUTERNAME` in `suspend.json` on `main` to show `suspended.html` instead of the
Bulletin (picked up within 5 minutes). Fails open: if the flag can't be fetched, the Bulletin runs.

> **Safety:** never list a machine that shows the **live dispatch call board**.

## Offboarding

```powershell
iwr https://raw.githubusercontent.com/KDSystemsInc/vfd-tv-kiosk/main/offboard.ps1 -OutFile $env:TEMP\offboard.ps1 -UseBasicParsing; powershell -ExecutionPolicy Bypass -File $env:TEMP\offboard.ps1 -Reboot
```

Removes the updater and watchdog tasks, `C:\ProgramData\KDSystems` and the custom launcher, and
points Shell Launcher back at `C:\Data\RedNMXBulletin.exe`. Leaves RedNMX, the Kiosk user,
auto-logon and Syncthing alone. Hand over the KDSystems admin password as part of the handoff.

## Roku TVs

On a kiosk whose TV is a Roku, put the TV's IP in `roku.txt` (elevated):

```powershell
Set-Content C:\ProgramData\KDSystems\roku.txt 10.3.0.44; Start-ScheduledTask 'KDS Kiosk Updater'
```

No file, no Roku task (Fire TV kiosks). An old hand-made task running `C:\Data\roku-watch.ps1` is replaced automatically and its IP carried over.
