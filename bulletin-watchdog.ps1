<#
  Watches C:\Data\RedNMXBulletin.log and restarts the Bulletin when it is in a state it does not
  recover from on its own. Installed and kept up to date by update.ps1; runs every 5 minutes as
  SYSTEM from C:\ProgramData\KDSystems. Actions are logged to C:\Data\bulletin-watchdog.log, which
  Syncthing carries to the NAS. Only log lines written since the current Bulletin started count,
  so a restart is never repeated for the same problem.

  Restarts when:
    1. Stuck: 30+ "Could not connect" in 10 min while the DB port answers. After a Wi-Fi drop
       on 10/18/2026, 14-TV looped like this for five days; only a restart cleared it.
    2. Reconnect failed: "Error in ReconnectSingleConnection" with no "Done with
       ReconnectSingleConnection" within 10 min, while the DB port answers.
    3. Hung: the log has not been written for 45 min (the app logs memory use every 30 min).
       Process.Responding cannot be used: from SYSTEM's session it always reads True.
  Warns only (a restart cannot fix it): the latest startup loaded a demo profile (FDID 12345),
  a blank PROFILE, or a server other than Alpine's. Logged once per startup.

  Dry run against any log:  pwsh bulletin-watchdog.ps1 -Log sample.log -Now '10/18/2026 17:40' -DryRun
#>
param(
  [string]$Log = 'C:\Data\RedNMXBulletin.log',
  [datetime]$Now = (Get-Date),
  [datetime]$Since = [datetime]::MinValue,   # dry runs only; live runs use the Bulletin's start time
  [switch]$DryRun
)
$Db = 'ALPINESOFTWARE.DATABASE.WINDOWS.NET'
$Out = 'C:\Data\bulletin-watchdog.log'
$Inv = [cultureinfo]::InvariantCulture

function Note($m) { if ($DryRun) { $m } else { "$($Now.ToString('MM/dd/yyyy HH:mm:ss'))  $m" | Out-File $Out -Append -Encoding utf8 } }
function DbUp {
  $c = [Net.Sockets.TcpClient]::new()
  try { $c.ConnectAsync($Db, 1433).Wait(5000) } catch { $false } finally { $c.Dispose() }
}
function Stamp($l) {
  $t = [datetime]::MinValue
  if ($l.Length -ge 19 -and [datetime]::TryParseExact($l.Substring(0, 19), 'MM/dd/yyyy HH:mm:ss', $Inv, 0, [ref]$t)) { $t } else { $null }
}

# Leave a just-started app alone: it may still be waiting on the network.
if (-not $DryRun) {
  $p = Get-Process RedNMXBulletin -ErrorAction SilentlyContinue
  if (-not $p -or $p.StartTime -gt $Now.AddMinutes(-15)) { return }
  $Since = $p.StartTime
}

# Timestamped lines written since the app started (continuation lines have no timestamp; skipped).
$recent = foreach ($l in Get-Content $Log -Tail 3000) {
  $t = Stamp $l
  if ($t -and $t -ge $Since -and $t -le $Now) { [pscustomobject]@{ T = $t; L = $l } }
}

# Warn once per startup if the app loaded the wrong profile.
$cfg = @{}
foreach ($m in Select-String $Log -Pattern '\[INFO\] (FDID|PROFILE|IPADDRESS) = (.*)$' | Select-Object -Last 3) {
  $cfg[$m.Matches[0].Groups[1].Value] = $m.Matches[0].Groups[2].Value.Trim()
  $cfg.At = $m.Line.Substring(0, 19)
}
if ($cfg.At -and ($cfg.FDID -eq '12345' -or -not $cfg.PROFILE -or $cfg.IPADDRESS -ne $Db)) {
  $warn = "PROFILE WARN for startup $($cfg.At): FDID=$($cfg.FDID) PROFILE='$($cfg.PROFILE)' SERVER=$($cfg.IPADDRESS)"
  if ($DryRun -or -not (Test-Path $Out) -or -not (Select-String $Out -SimpleMatch $warn -Quiet)) { Note $warn }
}

$reason = $null; $needDb = $true
$fails = @($recent | Where-Object { $_.T -ge $Now.AddMinutes(-10) -and $_.L -match 'Could not connect' }).Count
if ($fails -ge 30) { $reason = "stuck: $fails 'Could not connect' in 10 min" }

$err = $recent | Where-Object L -match 'Error in ReconnectSingleConnection' | Select-Object -Last 1
if (-not $reason -and $err -and $err.T -le $Now.AddMinutes(-10) -and
    -not ($recent | Where-Object { $_.T -gt $err.T -and $_.L -match 'Done with ReconnectSingleConnection' })) {
  $reason = "reconnect failed at $($err.T.ToString('HH:mm:ss')) and never completed"
}

$silent = ($Now - (Get-Item $Log).LastWriteTime).TotalMinutes
if (-not $reason -and $silent -ge 45) { $reason = "log silent for $([int]$silent) min (app hung)"; $needDb = $false }

if (-not $reason) { if ($DryRun) { "ok: $fails failures in last 10 min, log written $([int]$silent) min ago" }; return }

# A DB problem a restart cannot fix: restarting would only bring up "Sample Fire Department".
if ($needDb -and -not (DbUp)) { Note "SKIP: $reason, but DB port unreachable"; return }
Note "RESTART: $reason"
if (-not $DryRun) { Stop-Process -Name RedNMXBulletin -Force }   # Shell Launcher relaunches it
