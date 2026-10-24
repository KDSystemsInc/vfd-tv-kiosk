@echo off
rem Shell Launcher wrapper. Order each launch:
rem   1. Check the GitHub suspend flag (suspend.json on the repo main branch).
rem      If this PC's COMPUTERNAME is listed, show C:\Data\suspended.html instead of
rem      the Bulletin and recheck every 5 min. ANY fetch error = NOT suspended
rem      (fail open): a GitHub or internet outage must never blank a dispatch board.
rem   2. Wait until the RedNMX cloud DB answers, so a power-loss boot on Wi-Fi does not
rem      start the app before the network exists (that is what shows "Sample Fire Department").
rem   3. Launch the Bulletin.
rem Logs each decision to C:\Data\start-bulletin.log.
cd /d C:\Data

:suspend
powershell -NoProfile -Command "try { $j = Invoke-RestMethod 'https://raw.githubusercontent.com/KDSystemsInc/vfd-tv-kiosk/main/suspend.json' -TimeoutSec 10; exit ([int](@($j.suspended) -contains $env:COMPUTERNAME)) } catch { exit 0 }"
if not errorlevel 1 goto wait
echo %date% %time%  SUSPENDED (flag set for %COMPUTERNAME%) >> C:\Data\start-bulletin.log
tasklist /fi "imagename eq msedge.exe" | find /i "msedge.exe" >nul || start "" msedge --kiosk "file:///C:/Data/suspended.html" --edge-kiosk-type=fullscreen
timeout /t 300 /nobreak >nul
goto suspend

:wait
taskkill /im msedge.exe /f >nul 2>&1
set /a tries=0
:waitloop
powershell -NoProfile -Command "exit [int](-not (Test-NetConnection ALPINESOFTWARE.DATABASE.WINDOWS.NET -Port 1433 -InformationLevel Quiet -WarningAction SilentlyContinue))"
if not errorlevel 1 goto go
set /a tries+=1
if %tries% geq 60 (
  echo %date% %time%  GAVE UP after %tries% tries, launching anyway >> C:\Data\start-bulletin.log
  goto go
)
echo Waiting for network ... (%tries%)
timeout /t 5 /nobreak >nul
goto waitloop
:go
echo %date% %time%  launch after %tries% waits >> C:\Data\start-bulletin.log
C:\Data\RedNMXBulletin.exe
