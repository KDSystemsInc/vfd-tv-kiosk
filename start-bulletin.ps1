<#
  Shell Launcher wrapper, runs as the Kiosk user. PowerShell reads the whole script at start,
  so the updater can replace this file while it runs (a .cmd file cannot be replaced safely).
    1. Suspend flag: if this PC's name is in suspend.json on the repo main branch, show
       suspended.html instead of the Bulletin and recheck every 5 min. Any fetch error means
       NOT suspended (fail open): an outage must never blank a dispatch board.
    2. Wait for the RedNMX cloud DB (up to 5 min), so a power-loss boot on Wi-Fi does not start
       the app before the network exists ("Sample Fire Department").
    3. Run the Bulletin. When it exits (or the watchdog kills it), this script ends and Shell
       Launcher starts it again.
#>
$Data = 'C:\Data'
$LogFile = "$Data\start-bulletin.log"
function L($m) { "$(Get-Date -Format 'MM/dd/yyyy HH:mm:ss')  $m" | Out-File $LogFile -Append -Encoding utf8 }
function Suspended {
  try {
    $j = Invoke-RestMethod 'https://raw.githubusercontent.com/KDSystemsInc/vfd-tv-kiosk/main/suspend.json' -TimeoutSec 10 -UseBasicParsing
    return @($j.suspended) -contains $env:COMPUTERNAME
  } catch { return $false }
}
function DbUp {
  $c = [Net.Sockets.TcpClient]::new()
  try { $c.ConnectAsync('ALPINESOFTWARE.DATABASE.WINDOWS.NET', 1433).Wait(5000) } catch { $false } finally { $c.Dispose() }
}

while (Suspended) {
  if (-not (Get-Process msedge -ErrorAction SilentlyContinue)) {
    L "SUSPENDED ($env:COMPUTERNAME)"
    Start-Process msedge "--kiosk `"$(([uri]"$PSScriptRoot\suspended.html").AbsoluteUri)`" --edge-kiosk-type=fullscreen"
  }
  Start-Sleep 300
}
Get-Process msedge -ErrorAction SilentlyContinue | Stop-Process -Force

$tries = 0
while (-not (DbUp) -and $tries -lt 60) { $tries++; Start-Sleep 5 }
L "launch after $tries waits"
Start-Process "$Data\RedNMXBulletin.exe" -WorkingDirectory $Data -Wait
