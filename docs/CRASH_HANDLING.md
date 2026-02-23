# KontentumClient Crash Handling System

This document describes the crash handling and recovery system implemented for KontentumClient.

## Overview

The crash handling system provides:
1. **Native crash detection** (ACCESS_VIOLATION, STACK_OVERFLOW, etc.) via Windows VEH
2. **Haxe exception handling** via try-catch blocks
3. **Automatic restart** after any crash
4. **Crash event submission** to the Kontentum server
5. **Minidump creation** for native crashes

## Architecture

```
+------------------+     +-------------------+     +------------------+
|  Native Crash    | --> |  VEH Handler      | --> |  KC_HandleCrash  |
|  (ACCESS_VIOL.)  |     |  (C++ / Win32)    |     |  - Write dump    |
+------------------+     +-------------------+     |  - Submit event  |
                                                   |  - Restart app   |
+------------------+     +-------------------+     +------------------+
|  Haxe Exception  | --> |  catch (e:Dynamic)| --> | handleException  |
|  (throw, null)   |     |  (Haxe code)      |     |  - Log exception |
+------------------+     +-------------------+     |  - Release mutex |
                                                   |  - Submit event  |
                                                   |  - Restart app   |
                                                   +------------------+
```

## Key Files

| File | Purpose |
|------|---------|
| `src/utils/CrashHandler.hx` | Main crash handling - VEH, exception handler, restart logic |
| `src/utils/Mutex.hx` | Single-instance mutex to prevent duplicate processes; exposes `getHandle()` for watchdog |
| `src/utils/WatchDog.hx` | Watchdog thread for detecting freezes/hangs; releases app mutex before restart |
| `src/KontentumClient.hx` | Main app - sets up crash handler, contains catch blocks |
| `src/utils/Tray.hx` | System tray with debug menu items for testing crashes |

## Native Crash Handling (VEH)

### How it Works

1. **Vectored Exception Handler (VEH)** is installed at startup via `AddVectoredExceptionHandler()`
2. VEH runs FIRST, before any other exception handlers (including hxcpp's SEH)
3. When a fatal exception occurs (ACCESS_VIOLATION, etc.):
   - Write a minidump file to the log directory
   - Submit crash event to server via HTTP
   - Spawn restart process with `--forcedrestart` flag
   - Call `TerminateProcess()` to kill the crashed process immediately

### Fatal Exception Codes Handled

- `0xC0000005` - ACCESS_VIOLATION
- `0xC0000006` - IN_PAGE_ERROR
- `0xC00000FD` - STACK_OVERFLOW
- `0xC0000094` - INTEGER_DIVIDE_BY_ZERO
- `0xC0000095` - INTEGER_OVERFLOW
- `0xC000001D` - ILLEGAL_INSTRUCTION
- And more (see `KC_IsFatalException()`)

### C++ Code Location

In `CrashHandler.hx`, inside the `@:cppFileCode` block:
- `KC_VectoredExceptionHandler()` - The VEH callback
- `KC_HandleCrash()` - Core crash handling (dump, submit, restart)
- `KC_SubmitCrashEvent()` - HTTP POST to server

## Haxe Exception Handling

### How it Works

1. Critical code sections are wrapped in try-catch blocks
2. When an exception is caught:
   - Log the exception with stack trace
   - Stop the watchdog thread
   - Release the single-instance mutex
   - Submit crash event to server
   - Spawn restart process
   - Exit the current process

### Catch Blocks

Located in `KontentumClient.hx`:

```haxe
// Boot exception handler (line ~248)
try {
    if (i == null)
        i = new KontentumClient();
}
catch (e:Dynamic) {
    utils.CrashHandler.handleException("[BOOT] Unhandled exception", e);
}

// Tray timer exception handler (line ~1308)
catch (e:Dynamic) {
    utils.CrashHandler.handleException("[TrayTimer] Unhandled exception", e);
}
```

### The handleException Function

```haxe
public static function handleException(label:String, e:Dynamic):Void
{
    // 1. Log the exception
    utils.Log.logException(label, e);

    // 2. Build crash message for server
    var msg = "[CLIENT_EXCEPTION] : " + label + " - " + Std.string(e);

    // 3. Release resources BEFORE spawning restart
    utils.WatchDog.stop();
    utils.Mutex.release();

    // 4. Submit event and restart via C++
    untyped __cpp__("KC_HandleHaxeException({0}.c_str())", msg);

    // 5. Wait for restart process to spawn
    Sys.sleep(0.5);

    // 6. Exit this process
    Sys.exit(1);
}
```

## Restart Mechanism

### Command Line Flag

The restart process is launched with `--forcedrestart` which sets:
```haxe
KontentumClient.skipAppLaunch = true;
```

This prevents the restarted client from launching the monitored app again (it may still be running).

### Process Creation

```cpp
DWORD creationFlags = DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP;
CreateProcessW(NULL, g_crashRestartCommand, NULL, NULL, FALSE, creationFlags, NULL, NULL, &si, &pi);
```

- `DETACHED_PROCESS` - New process doesn't inherit console
- `CREATE_NEW_PROCESS_GROUP` - Survives parent termination

### Single-Instance Mutex

The client uses a named mutex (`Local\KontentumClient_SingleInstance`) to prevent multiple instances.

**Critical**: For Haxe exceptions, the mutex MUST be released BEFORE spawning the restart process, otherwise the new process will fail to acquire it and exit silently.

## Crash Event Submission

### URL Format

```
https://kontentum.link/rest/submitEvent/{exhibitToken}/{clientID}/{URL-encoded-message}
```

### Message Formats

- **Native crash**: `[NATIVE_CRASH] : (VEH) ACCESS_VIOLATION @ 0xC0000005`
- **Haxe exception**: `[CLIENT_EXCEPTION] : [TrayTimer] Unhandled exception - Error message`

### URL Encoding

Special characters are percent-encoded. Spaces use `%20` (not `+`) because the message is in the URL path, not query string.

## Console Behavior

### Debug Mode (debug=true)

- Normal start: Console is allocated via `AllocConsole()` + stdout/stderr redirect
- After crash restart (`skipAppLaunch=true`): No console allocation - runs silently

### Production Mode (debug=false)

- No console in either case

## Debug Menu

The system tray provides debug options (in `Tray.hx`):

| Menu Item | Command | Action |
|-----------|---------|--------|
| Test Native Crash (DEBUG) | `CMD_TEST_CRASH` (1004) | Triggers null pointer dereference |
| Test Haxe Exception (DEBUG) | `CMD_TEST_HAXE_EX` (1005) | Throws Haxe exception |

## Log Files

| File | Contents |
|------|----------|
| `client.log` | Main application log, exception stack traces |
| `veh_debug.log` | VEH handler debug output, crash event submissions |
| `watchdog.log` | Watchdog thread activity |
| `client-crash-YYYYMMDD-HHMMSS.dmp` | Minidump files for native crashes |

## Configuration

In `config.xml`:

```xml
<kontentum>
    <clientID>344</clientID>
    <exhibitToken>s3sxqb</exhibitToken>
    <!-- Used to build crash event URL -->
</kontentum>
<debug>true</debug>
<watchdog>true</watchdog>
```

## Setup in Code

In `KontentumClient.initSettings()`:

```haxe
// Set environment variables for C++ crash handler
Sys.putEnv("KC_LOG_DIR", logDir);
Sys.putEnv("KC_LOG_FILE", logPath);

// Install crash handlers
CrashHandler.install();

// Configure restart command
var restartCmd = '"' + Sys.programPath() + '" --forcedrestart';
CrashHandler.setRestartCommand(restartCmd);

// Configure crash event URL
var submitEventURL = ip + "/rest/submitEvent/" + token + "/" + clientID + "/";
CrashHandler.setSubmitEventURL(submitEventURL);

// Start watchdog and pass app mutex so it can release before restart
var timeoutMs = 10000;
WatchDog.start(timeoutMs, restartCmd);
WatchDog.setAppMutex(Mutex.getHandle());
WatchDog.setSubmitEventURL(submitEventURL);
```

## Flow Diagrams

### Native Crash Flow

```
1. ACCESS_VIOLATION occurs
2. VEH handler called (KC_VectoredExceptionHandler)
3. Check if fatal exception -> YES
4. KC_HandleCrash():
   a. Write minidump to disk
   b. Write to client.log
   c. KC_SubmitCrashEvent() -> HTTP to server
   d. CreateProcessW() with --forcedrestart
5. TerminateProcess() kills crashed process
6. New process starts, acquires mutex, continues running
```

### Haxe Exception Flow

```
1. Exception thrown (throw "error" or null access)
2. Caught by catch (e:Dynamic) block
3. CrashHandler.handleException():
   a. Log.logException() -> write to client.log
   b. WatchDog.stop() -> stop watchdog thread
   c. Mutex.release() -> release single-instance mutex
   d. KC_HandleHaxeException():
      - KC_SubmitCrashEvent() -> HTTP to server
      - CreateProcessW() with --forcedrestart
   e. Sys.sleep(0.5) -> wait for new process
   f. Sys.exit(1) -> terminate this process
4. New process starts, acquires mutex, continues running
```

## Troubleshooting

### New process doesn't start after Haxe exception

**Cause**: Single-instance mutex not released before spawning new process.

**Solution**: Ensure `Mutex.release()` is called BEFORE `KC_HandleHaxeException()`.

### Crash events not reaching server

**Check**:
1. `veh_debug.log` for HTTP response
2. URL encoding - special characters must be percent-encoded
3. Network connectivity

### Minidump not created

**Check**:
1. `KC_LOG_DIR` environment variable is set
2. Directory exists and is writable
3. dbghelp.dll is available

### New process doesn't start after watchdog timeout

**Cause**: The watchdog triggers a restart but doesn't release the app's single-instance mutex. The new process tries to acquire the mutex, fails, and exits silently.

**Solution**: The watchdog must be given the app mutex handle via `WatchDog.setAppMutex(Mutex.getHandle())` after starting. The watchdog C++ code will release this mutex before spawning the restart process.

**Example setup**:
```haxe
utils.WatchDog.start(timeoutMs, restartCmd);
utils.WatchDog.setAppMutex(utils.Mutex.getHandle());
```

### Watchdog timeout when tray menu is open

**Cause**: `TrackPopupMenu()` is a blocking Win32 call that freezes the Haxe event loop. While the menu is open, the watchdog ping timer cannot run, causing a heartbeat timeout.

**Solution**: Increase the watchdog timeout to allow for reasonable menu interaction time (e.g., 30+ seconds instead of 10 seconds), or pause the watchdog while the menu is active.

## Testing

1. Start the client
2. Right-click tray icon
3. Select "Test Native Crash (DEBUG)" or "Test Haxe Exception (DEBUG)"
4. Observe:
   - Client restarts automatically
   - Crash event appears in server logs
   - `veh_debug.log` shows the crash handling sequence
