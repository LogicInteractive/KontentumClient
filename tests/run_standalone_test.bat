@echo off
echo.
echo =================================================
echo Chrome Crash Detection - Standalone Test
echo =================================================
echo.
echo This test will:
echo   1. Launch Edge/Chrome with Google
echo   2. Monitor if the process is alive
echo   3. Ask you to KILL Edge in Task Manager
echo   4. Verify crash detection works
echo.
echo Press any key to start...
pause >nul

cd bin
TestChromeCrash.exe

echo.
echo Test completed!
pause