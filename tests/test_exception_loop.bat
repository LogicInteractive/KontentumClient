@echo off
echo ========================================
echo Testing Exception Restart Loop Protection
echo ========================================
echo.

cd /d "%~dp0bin"

:: Clean up any old restart counter
if exist restart_count.tmp del restart_count.tmp

:: Set the environment variable to simulate a watchdog restart
echo Simulating watchdog restart by setting APP_RESTARTED=1
set APP_RESTARTED=1

echo.
echo Test 1: First restart (should allow)
echo.
timeout /t 2 /nobreak > nul
:: You would normally run the app here, but we can't easily test
:: without actually modifying the code to throw an exception

echo.
echo Test 2: Creating restart counter file manually...
echo 2^|%TIME:~0,8% > restart_count.tmp
echo.

echo.
echo Test 3: Checking if restart limit kicks in...
echo Note: Actual testing requires running the app 3 times with APP_RESTARTED=1
echo.

echo ========================================
echo Manual Test Instructions:
echo ========================================
echo 1. Set environment: set APP_RESTARTED=1
echo 2. Run: KontentumClient.exe --skip
echo 3. Watch for restart count message
echo 4. On 3rd restart, watchdog should be disabled
echo 5. Check bin\restart_count.tmp file
echo ========================================

pause
