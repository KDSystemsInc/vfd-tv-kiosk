<#
  KD Systems kiosk updater. Runs every 6 hours as SYSTEM from C:\ProgramData\KDSystems.
  Installs a new release only if manifest.json carries a valid signature from the KD Systems
  release key and every file matches its hash. Any failure (no internet, GitHub down, bad
  signature, file missing from the repo) leaves the current install running untouched.
  Each run also makes sure the watchdog task, this task and the Shell Launcher entry are in place.
  Log: C:\Data\kds-update.log (Syncthing carries it to the NAS).

  First install (elevated, once per kiosk): use the bootstrap line release.sh prints.
  Remove everything: offboard.ps1.
  Test without installing:  pwsh update.ps1 -Source <dir> -Dir <dir> -NoApply
#>
param(
  [string]$Source = 'https://raw.githubusercontent.com/KDSystemsInc/vfd-tv-kiosk',
  [string]$Dir = 'C:\ProgramData\KDSystems',
  [switch]$Install,
  [switch]$NoApply
)
$ErrorActionPreference = 'Stop'
$PubKey = '<RSAKeyValue><Modulus>qxQdhGOgXm8xOi5nFuMAPqcIKO8MPAIfIFGF2TXn61UdVRh7qzJXOiKO/v/c1OGyuI/yzoW2ccL7UCXS1zknZGp83jg4ipMNpFoOFod8ysHsPFI8qLf9+9oyRjKMoFMS3Rr6HbjgEoR+KqNVzVCWxqD2wxF163GCpWSv9DOBoXRl/vNsAtun1an3ahmyhFedGA7NAZoiGKStI11lqDxl4vOIFFFNooOfdocOBL7/ppkXRtPQ1qmBthRo0MRndp/D/fbi+PlyHRHg4IEuWytcsWkUmaD4g28nQmhvTwAoXc5hBWxVEdtKgq/xLkRpYbMZA2yn6DEzPMY8TcJiGXqqKkq+0bTCG0BkbLEvhADIKxv8EjS+h5h9GKgsRjpKzFX2cq1tYfrhpWjlRk6q0VfnILLNTgIvAOcuGLO92UEAg1AXEL6/DnWi+l7uhVAUsN39CyrwnG7EtxTORVvVv59xpbvbMSEUodwILoaxrBZ+7wuNgK/352fNyN5wLaP6PgF3</Modulus><Exponent>AQAB</Exponent></RSAKeyValue>'
$Log = 'C:\Data\kds-update.log'

function L($m) { $l = "$(Get-Date -Format 'MM/dd/yyyy HH:mm:ss')  $m"; $l; try { $l | Out-File $Log -Append -Encoding utf8 } catch {} }
function Fetch($path, $out) {
  # The query string skips GitHub's ~5 min raw cache, so a kiosk never installs the previous release right after a new one.
  if ($Source -match '^https?://') { Invoke-WebRequest "$Source/${path}?t=$([DateTime]::UtcNow.Ticks)" -OutFile $out -UseBasicParsing -TimeoutSec 30 }
  else { Copy-Item (Join-Path $Source $path) $out }
}
function Ensure-Task($name, $script, $every) {
  if (Get-ScheduledTask $name -ErrorAction SilentlyContinue) { return }
  $a = New-ScheduledTaskAction -Execute powershell.exe -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$script`""
  $t = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval $every
  Register-ScheduledTask $name -Action $a -Trigger $t -User SYSTEM -RunLevel Highest -Force | Out-Null
  L "registered task: $name"
}

if ($Install) {
  New-Item -ItemType Directory -Force $Dir | Out-Null
  # Admin-only writes (SYSTEM runs these files); the Kiosk user needs read to run the launcher.
  icacls $Dir /inheritance:r /grant 'SYSTEM:(OI)(CI)F' 'Administrators:(OI)(CI)F' 'Users:(OI)(CI)RX' | Out-Null
  Copy-Item $PSCommandPath "$Dir\update.ps1" -Force
}

$have = [version]'0.0'
try { $have = [version](Get-Content "$Dir\version.txt" -Raw).Trim() } catch {}

try {
  $tmp = Join-Path ([IO.Path]::GetTempPath()) 'kds-update'
  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory $tmp | Out-Null
  Fetch 'main/manifest.json' "$tmp/manifest.json"
  Fetch 'main/manifest.sig' "$tmp/manifest.sig"
  $bytes = [IO.File]::ReadAllBytes("$tmp/manifest.json")
  $sig = [Convert]::FromBase64String((Get-Content "$tmp/manifest.sig" -Raw).Trim())
  $rsa = [Security.Cryptography.RSA]::Create(); $rsa.FromXmlString($PubKey)
  if (-not $rsa.VerifyData($bytes, $sig, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)) {
    throw 'manifest signature is not valid'
  }
  $man = [Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json
  $new = [version]$man.version
  if ($new -le $have) {
    if ($NoApply) { return "up to date: $have" }
    L "up to date: $have"
  } else {
    $files = $man.files.PSObject.Properties
    foreach ($f in $files) {
      if ($f.Name -notmatch '^[\w.-]+$') { throw "bad file name in manifest: $($f.Name)" }
      Fetch "v$($man.version)/$($f.Name)" "$tmp/$($f.Name)"
      if ((Get-FileHash "$tmp/$($f.Name)" -Algorithm SHA256).Hash -ne $f.Value) { throw "hash mismatch: $($f.Name)" }
    }
    if ($NoApply) { return "verified: $have -> $new" }
    foreach ($f in $files) { Copy-Item "$tmp/$($f.Name)" (Join-Path $Dir $f.Name) -Force }
    Set-Content "$Dir\version.txt" $man.version
    L "updated: $have -> $new"
  }
} catch {
  if ($NoApply) { return "skipped: $($_.Exception.Message)" }
  L "update skipped, keeping $have : $($_.Exception.Message)"
}

# Self-heal the install (runs even when the update was skipped).
if (-not (Test-Path "$Dir\start-bulletin.ps1")) { L 'no release installed yet'; return }
Ensure-Task 'KDS Kiosk Updater' "$Dir\update.ps1" (New-TimeSpan -Hours 6)
Ensure-Task 'RedNMX Bulletin Watchdog' "$Dir\bulletin-watchdog.ps1" (New-TimeSpan -Minutes 5)

# Roku keep-awake, only on kiosks whose TV is a Roku: roku.txt holds the TV's IP (some TVs are Fire TVs).
# Replace any hand-made task that ran C:\Data\roku-watch.ps1, carrying its -Roku IP over.
foreach ($t in @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { "$($_.Actions.Arguments)" -match 'C:\\Data\\roku-watch\.ps1' })) {
  if (-not (Test-Path "$Dir\roku.txt") -and "$($t.Actions.Arguments)" -match '-Roku\s+"?([^"\s]+)') { Set-Content "$Dir\roku.txt" $Matches[1] }
  Unregister-ScheduledTask $t.TaskName -Confirm:$false
  L "replaced old Roku task: $($t.TaskName)"
}
if ((Test-Path "$Dir\roku.txt") -and (Test-Path "$Dir\roku-watch.ps1")) { Ensure-Task 'KDS Roku Keep-Awake' "$Dir\roku-watch.ps1" (New-TimeSpan -Minutes 5) }
elseif (Get-ScheduledTask 'KDS Roku Keep-Awake' -ErrorAction SilentlyContinue) {
  Unregister-ScheduledTask 'KDS Roku Keep-Awake' -Confirm:$false; L 'removed Roku task (no roku.txt)'
}
$want = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Dir\start-bulletin.ps1`""
$sid = (Get-LocalUser Kiosk).SID.Value
$wesl = [wmiclass]"\\localhost\root\standardcimv2\embedded:WESL_UserSetting"
if ($wesl.GetCustomShell($sid).Shell -ne $want) {
  $wesl.RemoveCustomShell($sid) | Out-Null   # SetCustomShell refuses to overwrite an existing entry
  $wesl.SetCustomShell($sid, $want, $null, $null, 0) | Out-Null
  L 'Shell Launcher now runs start-bulletin.ps1 (takes effect at next reboot)'
}
