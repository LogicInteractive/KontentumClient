@echo off
REM ==================================================================
REM Chrome/Edge Crash Detection Test Script (Advanced)
REM ==================================================================
REM This advanced version monitors the log file in real-time to verify
REM crash detection messages appear correctly.
REM ==================================================================

setlocal enabledelayedexpansion

echo.
echo ============================================================
echo  Chrome/Edge Crash Detection Test (Advanced)
echo ============================================================
echo.

REM Configuration
set CLIENT_EXE=bin\KontentumClient.exe
set CHROME_PROCESS_NAME=chrome.exe
set EDGE_PROCESS_NAME=msedge.exe
set TEST_CYCLES=3
set WAIT_AFTER_KILL=5
set WAIT_BETWEEN_CYCLES=2
set LOG_DIR=C:\ProgramData\KontentumClient\logs
set TEMP_LOG=%TEMP%\kontentum_test_log.txt

REM Check if client exists
if not exist "%CLIENT_EXE%" (
    echo [ERROR] Client not found at %CLIENT_EXE%
    echo Please build the client first!
    pause
    exit /b 1
)

REM Check if log directory exists
if not exist "%LOG_DIR%" (
    echo [WARN] Log directory not found: %LOG_DIR%
    echo Creating directory...
    mkdir "%LOG_DIR%" 2>nul
)

REM Get the latest log file before starting
set LATEST_LOG_BEFORE=
for /f "delims=" %%f in ('dir /b /o-d "%LOG_DIR%\*.log" 2^>nul') do (
    set LATEST_LOG_BEFORE=%%f
    goto :found_log_before
)
:found_log_before

echo [INFO] Configuration:
echo   - Client: %CLIENT_EXE%
echo   - Test Cycles: %TEST_CYCLES%
echo   - Log Directory: %LOG_DIR%
echo   - Latest Log: %LATEST_LOG_BEFORE%
echo.

echo [INFO] Starting KontentumClient...
echo [INFO] Make sure config.xml is configured for browser mode!
echo.

REM Start client and capture output
start "KontentumClient" "%CLIENT_EXE%"
set CLIENT_PID=!ERRORLEVEL!

echo [INFO] Waiting 10 seconds for client to initialize...
timeout /t 10 /nobreak >nul

REM Find the new log file
set LATEST_LOG=
for /f "delims=" %%f in ('dir /b /o-d "%LOG_DIR%\*.log" 2^>nul') do (
    set LATEST_LOG=%%f
    goto :found_log
)
:found_log

if "!LATEST_LOG!"=="" (
    echo [WARN] No log file found - will proceed without log monitoring
) else (
    echo [INFO] Monitoring log file: %LOG_DIR%\!LATEST_LOG!
    echo.
)

REM Detect which browser is running
set BROWSER_PROCESS=
set BROWSER_NAME=

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
    echo Troubleshooting steps:
    echo   1. Check if config.xml has ^<chrome^> tag with browser path
    echo   2. Verify URL in config is a web URL (http/https)
    echo   3. Check if Chrome/Edge is installed at the configured path
    echo.
    if not "!LATEST_LOG!"=="" (
        echo Recent log entries:
        echo -------------------
        powershell -Command "Get-Content '%LOG_DIR%\!LATEST_LOG!' -Tail 20"
        echo -------------------
    )
    echo.
    pause
    exit /b 1
)

echo [INFO] Detected !BROWSER_NAME! process
echo.

REM Initialize counters
set SUCCESS_COUNT=0
set FAIL_COUNT=0

REM Run test cycles
for /L %%i in (1,1,%TEST_CYCLES%) do (
    echo ============================================================
    echo  Test Cycle %%i of %TEST_CYCLES%
    echo ============================================================
    echo.

    echo [%%i] Killing !BROWSER_NAME! to simulate crash...
    taskkill /F /IM "!BROWSER_PROCESS!" >nul 2>&1

    if errorlevel 1 (
        echo [%%i] WARNING: Failed to kill !BROWSER_NAME!
    ) else (
        echo [%%i] !BROWSER_NAME! killed successfully
    )

    echo [%%i] Waiting %WAIT_AFTER_KILL% seconds for detection and restart...
    timeout /t %WAIT_AFTER_KILL% /nobreak >nul

    REM Check if browser restarted
    set RESTARTED=0
    tasklist /FI "IMAGENAME eq !BROWSER_PROCESS!" 2>NUL | find /I /N "!BROWSER_PROCESS!">NUL
    if "%ERRORLEVEL%"=="0" (
        echo [%%i] ✓ SUCCESS: !BROWSER_NAME! restarted
        set /a SUCCESS_COUNT+=1
        set RESTARTED=1
    ) else (
        echo [%%i] ✗ FAILED: !BROWSER_NAME! did not restart
        set /a FAIL_COUNT+=1
    )

    REM Check log for crash detection message
    if not "!LATEST_LOG!"=="" (
        echo [%%i] Checking log for crash detection message...
        findstr /C:"Chrome/Edge browser crashed" /C:"BROWSER_CRASH" /C:"Restarting Chrome" "%LOG_DIR%\!LATEST_LOG!" > "%TEMP_LOG%" 2>nul

        if exist "%TEMP_LOG%" (
            for /f %%a in ('find /c /v "" ^< "%TEMP_LOG%"') do set LINE_COUNT=%%a
            if !LINE_COUNT! GTR 0 (
                echo [%%i] ✓ Crash detection logged successfully
                echo [%%i] Recent crash-related log entries:
                type "%TEMP_LOG%" | findstr /N "^" | more +0
            ) else (
                echo [%%i] ✗ No crash detection messages in log
            )
            del "%TEMP_LOG%" 2>nul
        )
    )

    echo.

    if %%i LSS %TEST_CYCLES% (
        if !RESTARTED!==1 (
            echo [%%i] Waiting %WAIT_BETWEEN_CYCLES% seconds before next test...
            timeout /t %WAIT_BETWEEN_CYCLES% /nobreak >nul
            echo.
        ) else (
            echo [%%i] Skipping remaining tests due to restart failure
            goto :test_complete
        )
    )
)

:test_complete

echo ============================================================
echo  Test Results
echo ============================================================
echo.
echo Summary:
echo   - Total Tests: %TEST_CYCLES%
echo   - Successful Restarts: %SUCCESS_COUNT%
echo   - Failed Restarts: %FAIL_COUNT%
echo   - Browser: !BROWSER_NAME!
echo.

if %FAIL_COUNT% EQU 0 (
    echo ✓ ALL TESTS PASSED
) else (
    echo ✗ SOME TESTS FAILED
)

echo.
echo Log File: %LOG_DIR%\!LATEST_LOG!
echo.
echo To view full logs:
echo   notepad "%LOG_DIR%\!LATEST_LOG!"
echo.
echo To stop the client:
echo   taskkill /F /IM KontentumClient.exe
echo.

REM Ask if user wants to view the log
choice /C YN /M "View log file now?"
if errorlevel 2 goto :skip_log
if errorlevel 1 (
    if not "!LATEST_LOG!"=="" (
        start notepad "%LOG_DIR%\!LATEST_LOG!"
    )
)

:skip_log

echo.
pause