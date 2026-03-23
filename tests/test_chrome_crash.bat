@echo off
REM ==================================================================
REM Chrome/Edge Crash Detection Test Script
REM ==================================================================
REM This script automatically tests the Chrome crash detection feature
REM by launching the client and repeatedly killing Chrome to trigger
REM crash detection and auto-restart.
REM ==================================================================

setlocal enabledelayedexpansion

echo.
echo ============================================================
echo  Chrome/Edge Crash Detection Test
echo ============================================================
echo.

REM Configuration
set CLIENT_EXE=bin\KontentumClient.exe
set CHROME_PROCESS_NAME=chrome.exe
set EDGE_PROCESS_NAME=msedge.exe
set TEST_CYCLES=3
set WAIT_AFTER_KILL=5
set WAIT_BETWEEN_CYCLES=2

REM Check if client exists
if not exist "%CLIENT_EXE%" (
    echo ERROR: Client not found at %CLIENT_EXE%
    echo Please build the client first!
    pause
    exit /b 1
)

echo [INFO] Starting KontentumClient...
echo [INFO] Make sure config.xml is configured for browser mode!
echo.
start "" "%CLIENT_EXE%"

echo [INFO] Waiting 10 seconds for client to launch Chrome/Edge...
timeout /t 10 /nobreak >nul

REM Detect which browser is running
set BROWSER_PROCESS=
tasklist /FI "IMAGENAME eq %CHROME_PROCESS_NAME%" 2>NUL | find /I /N "%CHROME_PROCESS_NAME%">NUL
if "%ERRORLEVEL%"=="0" (
    set BROWSER_PROCESS=%CHROME_PROCESS_NAME%
    set BROWSER_NAME=Chrome
)

if "!BROWSER_PROCESS!"=="" (
    tasklist /FI "IMAGENAME eq %EDGE_PROCESS_NAME%" 2>NUL | find /I /N "%EDGE_PROCESS_NAME%">NUL
    if "%ERRORLEVEL%"=="0" (
        set BROWSER_PROCESS=%EDGE_PROCESS_NAME%
        set BROWSER_NAME=Edge
    )
)

if "!BROWSER_PROCESS!"=="" (
    echo [ERROR] No Chrome or Edge process detected!
    echo.
    echo Possible reasons:
    echo   1. config.xml is not configured for browser mode
    echo   2. Client failed to launch browser
    echo   3. Browser launched but exited immediately
    echo.
    echo Please check:
    echo   - config.xml has a web URL configured
    echo   - Chrome/Edge path is correct in config
    echo.
    pause
    exit /b 1
)

echo [INFO] Detected !BROWSER_NAME! process running
echo.

REM Run test cycles
for /L %%i in (1,1,%TEST_CYCLES%) do (
    echo ============================================================
    echo  Test Cycle %%i of %TEST_CYCLES%
    echo ============================================================
    echo.

    echo [%%i] Killing !BROWSER_NAME! process to simulate crash...
    taskkill /F /IM "!BROWSER_PROCESS!" >nul 2>&1

    if errorlevel 1 (
        echo [%%i] WARNING: Failed to kill !BROWSER_NAME! - may have already crashed
    ) else (
        echo [%%i] !BROWSER_NAME! process killed successfully
    )

    echo [%%i] Waiting %WAIT_AFTER_KILL% seconds for crash detection and restart...
    timeout /t %WAIT_AFTER_KILL% /nobreak >nul

    REM Check if browser restarted
    tasklist /FI "IMAGENAME eq !BROWSER_PROCESS!" 2>NUL | find /I /N "!BROWSER_PROCESS!">NUL
    if "%ERRORLEVEL%"=="0" (
        echo [%%i] SUCCESS: !BROWSER_NAME! restarted automatically!
        echo.
    ) else (
        echo [%%i] FAILED: !BROWSER_NAME! did not restart!
        echo [%%i] Check client logs for errors
        echo.
    )

    if %%i LSS %TEST_CYCLES% (
        echo [%%i] Waiting %WAIT_BETWEEN_CYCLES% seconds before next cycle...
        timeout /t %WAIT_BETWEEN_CYCLES% /nobreak >nul
        echo.
    )
)

echo ============================================================
echo  Test Complete
echo ============================================================
echo.
echo Test Summary:
echo   - Ran %TEST_CYCLES% crash simulation cycles
echo   - Browser: !BROWSER_NAME!
echo.
echo Next Steps:
echo   1. Check client console for crash detection messages
echo   2. Verify server received BROWSER_CRASH actions
echo   3. Check logs at C:\ProgramData\KontentumClient\logs\
echo.
echo Press Ctrl+C in the client window to stop the client.
echo.

pause