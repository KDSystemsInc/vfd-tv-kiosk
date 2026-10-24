<#
  Offboarding: removes everything KD Systems installed on a kiosk and puts it back on the stock
  RedNMX Bulletin launch, so the District can run it without us. Run elevated; takes effect at
  the next reboot (pass -Reboot to do it now).
  Leaves in place: RedNMX itself, C:\Data, the Kiosk user and auto-logon, Syncthing, and the
  KDSystems admin account (hand its password to the District, or remove it once they have their
  own admin; removing it here could lock them out).
#>
param([switch]$Reboot)
foreach ($t in 'KDS Kiosk Updater', 'RedNMX Bulletin Watchdog', 'KDS Roku Keep-Awake') {
  Unregister-ScheduledTask $t -Confirm:$false -ErrorAction SilentlyContinue
}

$sid = (Get-LocalUser Kiosk).SID.Value
$wesl = [wmiclass]"\\localhost\root\standardcimv2\embedded:WESL_UserSetting"
$wesl.RemoveCustomShell($sid) | Out-Null
$wesl.SetCustomShell($sid, 'cmd.exe /c "cd /d C:\Data && C:\Data\RedNMXBulletin.exe"', $null, $null, 0) | Out-Null

Remove-Item 'C:\ProgramData\KDSystems' -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item 'C:\Data\start-bulletin.cmd', 'C:\Data\suspended.html' -ErrorAction SilentlyContinue   # v1.1 leftovers

[pscustomobject]@{
  Shell        = $wesl.GetCustomShell($sid).Shell
  TasksLeft    = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object TaskName -in 'KDS Kiosk Updater', 'RedNMX Bulletin Watchdog', 'KDS Roku Keep-Awake').Count
  KDSFilesLeft = Test-Path 'C:\ProgramData\KDSystems'
} | Format-List
if ($Reboot) { Restart-Computer -Force } else { 'Offboarded. Reboot to apply.' }
