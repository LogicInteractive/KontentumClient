@echo off
cd /d "%~dp0bin"

echo Testing --install command...
echo.
KontentumClient.exe --install
echo.

echo.
echo Checking registry...
reg query HKCU\Software\Microsoft\Windows\CurrentVersion\Run /v KontentumClient
echo.

echo.
echo Testing --uninstall command...
echo.
KontentumClient.exe --uninstall
echo.

echo.
echo Verifying removal...
reg query HKCU\Software\Microsoft\Windows\CurrentVersion\Run /v KontentumClient
echo.

pause
