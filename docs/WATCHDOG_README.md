# KontentumClient Watchdog System

## Overview

The watchdog is a background thread that monitors the application's health and automatically restarts it if it crashes or freezes.

## How It Works

### Detection Methods:

1. **Heartbeat Timeout** (10 seconds)
   - Application pings the watchdog every ~3 seconds
   - If no ping is received for 10 seconds, watchdog assumes crash/freeze
   - Logs crash reason and restarts the application

2. **Memory Critical**
   - Monitors system memory usage
   - Triggers restart if memory load >90% OR virtual memory >95%
   - Prevents out-of-memory crashes

### Restart Behavior:

When crash/freeze detected:
1. Logs event to `logs/watchdog.log` with timestamp
2. Sets environment variable `APP_RESTARTED=1` for child process
3. Launches new instance: `"C:\path\to\KontentumClient.exe"`
4. Terminates current process

### Restart Loop Protection:

**Critical Feature**: Prevents infinite restart loops from buggy code

**How it works:**
1. On startup, checks if `APP_RESTARTED=1` environment variable is set
2. Tracks consecutive restarts in `bin/restart_count.tmp` file
3. Resets counter if >5 minutes pass between restarts (indicates stability)
4. After **3 consecutive restarts within 5 minutes**:
   - Displays warning message on console
   - **Disables watchdog** to prevent further restarts
   - Logs critical error
   - App stays running but won't restart again
5. On normal startup (not watchdog restart), restart counter is cleared

**Limits:**
- **Max consecutive restarts**: 3
- **Time window**: 5 minutes
- **Counter file**: `bin/restart_count.tmp`

**Example Scenario:**
```
Restart 1: Exception thrown → Watchdog restarts (1/3)
Restart 2: Same exception → Watchdog restarts (2/3)
Restart 3: Same exception → Watchdog restarts (3/3)
Restart 4: BLOCKED - Watchdog disabled, app exits permanently

Message shown:
===============================================
CRITICAL: Restart loop detected!
App has restarted 3 times in 5 minutes.
Disabling watchdog to prevent infinite restart loop.
Please check logs for errors and fix the issue.
===============================================
```

## CLI Flags

### Disable Watchdog for Testing
```bash
KontentumClient.exe --no-watchdog
```
Use this when:
- Testing/debugging locally
- Running automated tests
- Performing maintenance
- You need the app to exit cleanly without restart

### Other Flags
```bash
KontentumClient.exe --skip              # Skip startup prompt
KontentumClient.exe --install           # Install auto-start
KontentumClient.exe --uninstall         # Remove auto-start
```

Flags can be combined:
```bash
KontentumClient.exe --skip --no-watchdog
```

## Clean Shutdown

The watchdog is **automatically stopped** before exit in these scenarios:

✅ Tray menu "Quit" button
✅ `--install` command
✅ `--uninstall` command
✅ Duplicate instance detection
✅ Normal `exit()` / `exitWithError()` calls

**Result**: Application exits cleanly without triggering a restart.

## Force Kill Behavior

### Task Manager Kill (without --no-watchdog):
- ❌ Watchdog detects as crash
- ❌ Restarts application in ~10 seconds
- **Solution**: Use tray "Quit" button or run with `--no-watchdog`

### Windows Shutdown:
- ✅ OS terminates all processes forcefully
- ✅ No restart (system is shutting down)

### With --no-watchdog flag:
- ✅ Task Manager kill works cleanly
- ✅ No restart triggered
- ✅ Application exits permanently

## Watchdog Log

**Location**: `bin/logs/watchdog.log`

**Format**:
```
[2025-10-01 12:00:09] Watchdog thread started
[2025-10-01 12:00:19] Watchdog: Heartbeat timeout (err=0x00000000)
[2025-10-01 12:00:19] Restart command launched
[2025-10-01 12:00:20] Watchdog thread exiting
```

**Log Events**:
- `Watchdog thread started` - Monitoring started
- `Heartbeat timeout` - No ping received for 10s (crash/freeze)
- `Memory critical` - System memory critically low
- `Restart command launched` - New instance started successfully
- `CreateProcessW failed for restart` - Restart failed (check permissions)
- `Watchdog thread exiting` - Clean shutdown

## Testing Scenarios

### Test Clean Exit (No Restart):
```bash
# Start with watchdog
KontentumClient.exe --skip

# Wait a few seconds, then quit via tray menu
# Check logs/watchdog.log - should show clean exit, no restart
```

### Test Crash Detection (Should Restart):
```bash
# Start with watchdog
KontentumClient.exe --skip

# Kill from Task Manager
# Wait 10 seconds - app should restart automatically
# Check logs/watchdog.log for "Heartbeat timeout" entry
```

### Test No Watchdog (Clean Kill):
```bash
# Start without watchdog
KontentumClient.exe --skip --no-watchdog

# Kill from Task Manager
# App exits permanently, no restart
# No watchdog.log file created
```

### Test Restart Loop Protection:
```bash
# Simulate a crashing app by killing it repeatedly
# This tests the 3-restart limit

# Start app normally
KontentumClient.exe --skip

# Kill from Task Manager (1st restart)
# Wait 10s - app restarts automatically
# Shows: "Info: App restarted by watchdog (1/3 restarts)"

# Kill from Task Manager again (2nd restart)
# Wait 10s - app restarts automatically
# Shows: "Info: App restarted by watchdog (2/3 restarts)"

# Kill from Task Manager again (3rd restart)
# Wait 10s - app restarts automatically
# Shows: "Info: App restarted by watchdog (3/3 restarts)"

# Kill from Task Manager again (4th time)
# Wait 10s - app restarts but watchdog is DISABLED
# Shows: "CRITICAL: Restart loop detected!"
# App runs but won't restart if killed again

# Check bin/restart_count.tmp for counter value
```

## Common Issues

### App keeps restarting after Task Manager kill:
**Cause**: Watchdog is running and detects the kill as a crash
**Solution**:
1. Use tray "Quit" button for clean exit, OR
2. Run with `--no-watchdog` flag during testing

### App doesn't restart after real crash:
**Cause**: Watchdog might be disabled or not running
**Solution**:
- Check if `--no-watchdog` flag was used
- Verify `logs/watchdog.log` exists and shows "Watchdog thread started"
- Ensure ping timer is running (check for pings every ~3s)

### Restart loop (keeps restarting immediately):
**Cause**: Application crashes during startup, before first ping (Haxe exception, null pointer, etc.)
**Built-in Protection**:
- App automatically limits restarts to 3 within 5 minutes
- After 3rd restart, watchdog is disabled automatically
- Console shows "CRITICAL: Restart loop detected!" message
**Manual Solution During Development**:
- Use `--no-watchdog` flag to prevent any restarts
- Fix the underlying crash/exception issue
- Check application logs for exception details
- Delete `bin/restart_count.tmp` to reset counter after fixing

## Architecture

### Thread Safety:
- Watchdog runs in separate C++ thread (`_beginthreadex`)
- Uses Win32 Event object for ping synchronization
- Mutex prevents multiple watchdog instances

### Process Isolation:
- Watchdog is internal to the process
- If main process crashes, watchdog goes with it (by design)
- New instance gets fresh watchdog thread

### Mutex Coordination:
- Application mutex: `Local\KontentumClient_SingleInstance`
- Watchdog mutex: `Local\KontentumClient_Watchdog_Mutex`
- Both released automatically on process termination

## Best Practices

### Development:
```bash
# Always use --no-watchdog during development
KontentumClient.exe --skip --no-watchdog
```

### Production:
```bash
# Let watchdog run normally (default)
KontentumClient.exe
```

### Automated Testing:
```bash
# Disable watchdog for test scripts
KontentumClient.exe --skip --no-watchdog
```

### Scheduled Task/Service:
```bash
# Enable watchdog for unattended operation
KontentumClient.exe --skip
```

## Implementation Files

- `src/utils/WatchDog.hx` - Core watchdog implementation (C++ thread)
- `src/KontentumClient.hx` - Integration and CLI flags
- Lines 243-255: Watchdog start (only if `enableWatchdog == true`)
- Lines 405-423: Clean shutdown (stops watchdog before exit)
- Lines 852-860: Tray quit (stops watchdog + releases mutex)

## Future Enhancements

Potential improvements:
- Configurable timeout (currently hardcoded 10s)
- Restart count limit (prevent infinite restart loops)
- Email/webhook notification on crash
- Graceful degradation (disable after N consecutive crashes)
- Configuration file for watchdog settings
