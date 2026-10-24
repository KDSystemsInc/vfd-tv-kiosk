<#
  Restarts RedNMX Bulletin when it is stuck on "Could not connect" while the database is reachable.
  Background: after a Wi-Fi flap on 10/18/2026, 14-TV logged "Could not connect" every 15 s for
  five days while port 1433 answered; only a process restart cleared it.

  Install or update (elevated, per kiosk; set $v to the release tag):
    $v='v1.0.0'; $f="$env:TEMP\bulletin-watchdog.ps1"; iwr "https://raw.githubusercontent.com/KDSystemsInc/vfd-tv-kiosk/$v/bulletin-watchdog.ps1" -OutFile $f -UseBasicParsing; powershell -ExecutionPolicy Bypass -File $f -Install
  Copies itself to C:\ProgramData\KDSystems (C:\Data is user-writable and Syncthing-fed, so a
  SYSTEM task must not run from there) and runs every 5 minutes as SYSTEM.
  Actions are logged to C:\Data\bulletin-watchdog.log, which Syncthing carries to the NAS.

  Dry run against any log:  pwsh bulletin-watchdog.ps1 -Log sample.log -Now '10/18/2026 17:40' -DryRun
#>
param(
  [string]$Log = 'C:\Data\RedNMXBulletin.log',
  [datetime]$Now = (Get-Date),
  [switch]$DryRun,
  [switch]$Install
)
$Db = 'ALPINESOFTWARE.DATABASE.WINDOWS.NET'
$Out = 'C:\Data\bulletin-watchdog.log'

if ($Install) {
  $dir = 'C:\ProgramData\KDSystems'
  New-Item -ItemType Directory -Force $dir | Out-Null
  icacls $dir /inheritance:r /grant 'SYSTEM:(OI)(CI)F' 'Administrators:(OI)(CI)F' | Out-Null
  Copy-Item $PSCommandPath "$dir\bulletin-watchdog.ps1" -Force
  $a = New-ScheduledTaskAction -Execute powershell.exe -Argument "-NoProfile -ExecutionPolicy Bypass -File $dir\bulletin-watchdog.ps1"
  $t = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5)
  Register-ScheduledTask -TaskName 'RedNMX Bulletin Watchdog' -Action $a -Trigger $t -User SYSTEM -RunLevel Highest -Force |
    Select-Object TaskName, State
  return
}

# Leave a just-started app alone: it may still be waiting on the network.
$p = Get-Process RedNMXBulletin -ErrorAction SilentlyContinue
if (-not $DryRun -and (-not $p -or $p.StartTime -gt $Now.AddMinutes(-15))) { return }

# The app retries every 15 s, so 10 minutes stuck is ~40 failures. 30 means stuck for 7+ minutes.
# ponytail: count-based, no success marker exists in the log to look for.
$cut = $Now.AddMinutes(-10); $fails = 0; $t = [datetime]::MinValue
foreach ($l in Get-Content $Log -Tail 300) {
  if ($l.Length -ge 19 -and $l -match 'Could not connect' -and
      [datetime]::TryParseExact($l.Substring(0, 19), 'MM/dd/yyyy HH:mm:ss', [cultureinfo]::InvariantCulture, 0, [ref]$t) -and
      $t -ge $cut -and $t -le $Now) { $fails++ }
}
if ($fails -lt 30) { if ($DryRun) { "ok: $fails failures in last 10 min" }; return }

# Only restart if the DB port answers; if it does not, a restart would just come up as "Sample Fire Department".
$c = [Net.Sockets.TcpClient]::new()
try { $up = $c.ConnectAsync($Db, 1433).Wait(5000) } catch { $up = $false } finally { $c.Dispose() }

$msg = if ($up) { "RESTART: $fails failures in 10 min, DB port reachable" } else { "SKIP: $fails failures in 10 min, DB port unreachable" }
if ($DryRun) { return $msg }
"$($Now.ToString('MM/dd/yyyy HH:mm:ss'))  $msg" | Out-File $Out -Append -Encoding utf8
if ($up) { Stop-Process -Name RedNMXBulletin -Force }   # Shell Launcher relaunches it
