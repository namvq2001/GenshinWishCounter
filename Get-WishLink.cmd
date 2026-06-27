@echo off
rem Double-click launcher for Get-WishLink.ps1
rem Args pass through, e.g.:  Get-WishLink.cmd -Region china
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Get-WishLink.ps1" %*
echo.
pause
endlocal
