<#
  Keeps a Roku TV awake on the kiosk's input. Installed by update.ps1 only on kiosks that have
  C:\ProgramData\KDSystems\roku.txt (the Roku TV's IP); runs every 5 min as SYSTEM.
  Sends a command only when something is wrong (TV off, wrong input, screensaver showing), so a
  healthy TV is never touched. Re-launching the input on every run made the picture blink.
  Session 0 => nothing ever renders on the TV. Log: C:\Data\roku-watch.log.

  .EXAMPLE
    powershell -File C:\ProgramData\KDSystems\roku-watch.ps1 -Roku 192.168.1.193
#>
param(
    [string]$Roku,                                # bare IP or full http:// URL; default: roku.txt beside this script
    [string]$Src = 'tvinput.hdmi1',
    [string]$Log = 'C:\Data\roku-watch.log',
    [int]$Keep   = 2000                           # lines retained when the log passes 1 MB
)

if (-not $Roku) { $Roku = (Get-Content (Join-Path (Split-Path -Parent $PSCommandPath) 'roku.txt') -ErrorAction Stop | Select-Object -First 1).Trim() }
if ($Roku -notmatch '^https?://') { $Roku = "http://$Roku" }
if ($Roku -notmatch ':\d+$')      { $Roku = "${Roku}:8060" }

function Note($m) { "{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $m | Add-Content -Path $Log }
function Post($p) { Invoke-RestMethod -Method Post -Uri "$Roku/$p" -TimeoutSec 5 | Out-Null }

try {
    $power  = (Invoke-RestMethod -Uri "$Roku/query/device-info" -TimeoutSec 5).'device-info'.'power-mode'
    $active = (Invoke-RestMethod -Uri "$Roku/query/active-app"  -TimeoutSec 5).'active-app'
    $app    = $active.app.'ui-location'
} catch {
    Note "UNREACHABLE  $Roku  $($_.Exception.Message)"
    exit 1
}

$act = @()
if ($power -ne 'PowerOn') { $act += 'WAKE'; Post 'keypress/PowerOn'; Start-Sleep -Seconds 5 }
if ($app -ne $Src)        { $act += 'INPUT' }
if ($active.screensaver)  { $act += 'SAVER' }   # Roku lists a <screensaver> element only while one is showing
if ($act) { Post "launch/$Src" }                # re-launching the input fixes all three

$tag = if ($act) { $act -join '+' } else { 'ok' }
Note "$tag  power=$power input=$app"

if ((Test-Path $Log) -and (Get-Item $Log).Length -gt 1MB) {
    Set-Content $Log -Value (Get-Content $Log -Tail $Keep)
}
