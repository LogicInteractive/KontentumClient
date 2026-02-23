# Chrome/Edge Crash Detection Testing

## Overview
The client now monitors Chrome/Edge browser processes and automatically restarts them if they crash.

## What Was Added

### 1. Chrome Library Fix (`c:\dev\fox\fox\hx\fox\native\windows\Chrome.hx`)
- Fixed bug in `dispose()` method (was setting `isRunning = true` instead of `false`)
- Added `checkAlive()` method to properly detect if Chrome process is still running

### 2. Client Monitoring (`KontentumClient.hx`)
- Added Chrome crash monitoring timer (checks every 500ms)
- Sends `BROWSER_CRASH` action to server when crash detected
- Automatically restarts Chrome with cached URL or fallback URL
- Safety limit: max 10 restarts (configurable via `chromeMaxRestarts`)
- 3-second delay between restarts (configurable via `chromeRestartDelay`)

## How to Test

### Automated Testing (Recommended)

**Basic Test:**
```bash
test_chrome_crash.bat
```
- Automatically launches client and simulates 3 crashes
- Verifies browser restarts after each crash
- Simple output, good for quick testing

**Advanced Test:**
```bash
test_chrome_crash_advanced.bat
```
- Launches client and simulates 3 crashes
- Monitors log files in real-time
- Verifies crash detection messages appear in logs
- Shows detailed test results and statistics
- Offers to open log file at the end

**Prerequisites for automated tests:**
- Ensure `config.xml` has a web URL configured for browser mode
- Chrome or Edge must be properly configured in the `<chrome>` tag

### Manual Testing

1. **Start the client in browser mode:**
   ```bash
   cd "d:\Logic interactive Dropbox\tommy _\projects\Logic\KontentumClient_n\bin"
   KontentumClient.exe
   ```
   Make sure your `config.xml` has a web URL configured to trigger browser mode.

2. **Simulate a crash:**
   - Wait for Chrome/Edge to launch
   - Open Task Manager (Ctrl+Shift+Esc)
   - Find the Chrome/Edge process
   - Right-click → End Task

3. **Expected behavior:**
   - Client detects the crash within 500ms
   - Logs: "Chrome/Edge browser crashed or exited unexpectedly."
   - Logs: "Restarting Chrome/Edge in 3.0s (crash #1)"
   - After 3 seconds, Chrome relaunches automatically
   - Server receives `BROWSER_CRASH` action

4. **Test crash limit:**
   - Repeat step 2 multiple times (>10 times)
   - After 10 crashes, client should stop auto-restarting
   - Log: "Chrome crash limit reached (10/10). Stopping auto-restart."

### Automated Test Scenario

You can modify the config temporarily to test with debug mode:

```xml
<debug>true</debug>
```

This will show all crash detection logs in the console.

### Check Server Notifications

Check your server logs for `BROWSER_CRASH` actions being received from the client.

## Configuration Options

You can customize the behavior by modifying static variables in `KontentumClient.hx`:

```haxe
static var chromeRestartDelay  : Float = 3.0;   // Delay before restart (seconds)
static var chromeCrashCount    : Int   = 0;     // Current crash count
static var chromeMaxRestarts   : Int   = 10;    // Max restart attempts
```

## Technical Details

### Crash Detection Flow
1. Timer checks `chrome.checkAlive()` every 500ms
2. `checkAlive()` calls `chrome.exitCode(false)` (non-blocking)
3. If exitCode != null, process has terminated
4. Crash handler is triggered

### Restart Flow
1. Stop monitoring timer
2. Increment crash counter
3. Check if crash limit exceeded
4. Wait `chromeRestartDelay` seconds
5. Read cached URL from `c:/temp/kontentum_offlinelaunch`
6. Launch Chrome with cached URL (or fallback URL)
7. Restart monitoring

## Known Limitations

- Cannot detect Chrome GPU process crashes (only main process)
- Cannot restart if no cached URL and no fallback URL configured
- Maximum 10 restarts per client session (resets on client restart)

## Debugging

If crash detection isn't working:

1. Check if `chrome.checkAlive()` is being called
2. Verify Chrome process is actually terminating
3. Enable debug mode in config.xml
4. Check logs at: `C:\ProgramData\KontentumClient\logs\`