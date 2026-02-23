# Exception Handling & Restart Loop Protection

## Summary

Your question: **"What if there is a Haxe exception? Will the watchdog restart it or enter a loop?"**

**Answer**: ✅ **The watchdog WILL restart the app, but with intelligent loop prevention**

---

## How It Works

### Scenario: Haxe Exception Thrown

```haxe
try
{
    if (i == null)
        i = new KontentumClient();
}
catch (e:Dynamic)
{
    utils.Log.logException("[BOOT] Unhandled exception", e);
    Sys.sleep(0.1);
    Sys.exit(1);  // ← Watchdog NOT stopped intentionally
}
```

**What Happens:**

1. ✅ Exception is caught and logged to `logs/` folder
2. ✅ App calls `Sys.exit(1)` **without** stopping watchdog
3. ✅ Watchdog detects no more pings → assumes crash
4. ✅ After 10 seconds timeout, watchdog restarts the app
5. ✅ New instance starts with `APP_RESTARTED=1` environment variable

**Why we DON'T stop the watchdog on exception:**
- Production apps should recover from exceptions automatically
- Unattended operation requires auto-restart
- Manual intervention not always available

---

## Loop Prevention System

### The Problem (Before):
```
Exception → Exit → Watchdog restarts → Same exception → Exit → ...
INFINITE LOOP! 🔄
```

### The Solution (Now):

**3-Strike Rule**: App tracks consecutive restarts

| Restart # | Action | Watchdog Status |
|-----------|--------|-----------------|
| **Normal Start** | Clear counter file | ✅ Enabled |
| **Restart 1** | Log restart (1/3) | ✅ Enabled |
| **Restart 2** | Log restart (2/3) | ✅ Enabled |
| **Restart 3** | Log restart (3/3) | ✅ Enabled |
| **Restart 4** | **BLOCK** - Disable watchdog | ❌ **DISABLED** |

### Implementation Details:

**Restart Counter File**: `bin/restart_count.tmp`
```
Format: "3|1696170000.123"
        │   └─ Timestamp of last restart
        └─ Number of consecutive restarts
```

**Time Window**: 5 minutes
- If restarts are >5 minutes apart, counter resets
- Indicates app is stable between crashes
- Only rapid restarts (within 5 min) count toward limit

**Environment Variable**: `APP_RESTARTED=1`
- Set by watchdog before launching child process
- Checked on startup to detect watchdog-initiated restart
- Cleared on normal startup

---

## Example: Exception Loop Scenario

### Without Protection (Old Behavior):
```
[12:00:00] App starts
[12:00:05] Exception thrown: NullPointerError
[12:00:05] App exits
[12:00:15] Watchdog restarts app
[12:00:20] Exception thrown: NullPointerError (same bug!)
[12:00:20] App exits
[12:00:30] Watchdog restarts app
[12:00:35] Exception thrown: NullPointerError (STILL same bug!)
... LOOPS FOREVER 🔄
```

### With Protection (New Behavior):
```
[12:00:00] App starts (normal, no APP_RESTARTED env var)
[12:00:00] Restart counter cleared
[12:00:05] Exception thrown: NullPointerError
[12:00:05] Logged to file, app exits (watchdog running)
[12:00:15] Watchdog restarts app (sets APP_RESTARTED=1)
[12:00:15] ✅ Detected restart, counter = 1/3
[12:00:20] Exception thrown again (same bug)
[12:00:20] Logged to file, app exits
[12:00:30] Watchdog restarts app
[12:00:30] ✅ Detected restart, counter = 2/3
[12:00:35] Exception thrown again
[12:00:35] Logged to file, app exits
[12:00:45] Watchdog restarts app
[12:00:45] ✅ Detected restart, counter = 3/3
[12:00:50] Exception thrown again
[12:00:50] Logged to file, app exits
[12:01:00] Watchdog restarts app
[12:01:00] ❌ LOOP DETECTED! Watchdog DISABLED
[12:01:00] Console shows:
            ===============================================
            CRITICAL: Restart loop detected!
            App has restarted 3 times in 5 minutes.
            Disabling watchdog to prevent infinite restart loop.
            Please check logs for errors and fix the issue.
            ===============================================
[12:01:05] Exception thrown again
[12:01:05] App exits PERMANENTLY (no restart)
```

---

## Code Changes Made

### 1. Track Restart Count (KontentumClient.hx)
```haxe
static public var consecutiveRestarts: Int = 0;
static public var maxConsecutiveRestarts: Int = 3;

static function checkRestartCount():Void
{
    var wasRestarted = Sys.getEnv("APP_RESTARTED");
    if (wasRestarted == "1")
    {
        // Load counter from file
        // Increment counter
        // Check if limit exceeded
        if (consecutiveRestarts >= maxConsecutiveRestarts)
        {
            // DISABLE WATCHDOG
            enableWatchdog = false;
            // Show warning
        }
    }
    else
    {
        // Normal startup - clear counter
        consecutiveRestarts = 0;
    }
}
```

### 2. Pass Environment Variable (WatchDog.hx)
```cpp
// Build environment block with APP_RESTARTED=1
wchar_t* currentEnv = GetEnvironmentStringsW();
// ... copy current environment ...
// Add APP_RESTARTED=1
CreateProcessW(NULL, g_restartCommand, NULL, NULL, FALSE, 0,
               newEnv,  // ← Custom environment with APP_RESTARTED=1
               NULL, &si, &pi);
```

### 3. Exception Handler (Unchanged)
```haxe
catch (e:Dynamic)
{
    utils.Log.logException("[BOOT] Unhandled exception", e);
    Sys.sleep(0.1);
    Sys.exit(1);  // Watchdog keeps running → triggers restart
}
```

---

## Files Modified

1. **src/KontentumClient.hx**:
   - Added `consecutiveRestarts` and `maxConsecutiveRestarts` variables
   - Added `checkRestartCount()` function (lines 148-244)
   - Call `checkRestartCount()` at start of `main()` (line 69)

2. **src/utils/WatchDog.hx**:
   - Modified `KC_WatchdogThread` to build custom environment block
   - Pass `APP_RESTARTED=1` to child process via CreateProcessW (lines 95-144)

3. **WATCHDOG_README.md**:
   - Documented restart loop protection
   - Added testing scenarios
   - Added troubleshooting for restart loops

---

## Testing the Protection

### Manual Test:
```bash
# 1. Start app normally
KontentumClient.exe --skip

# 2. Kill from Task Manager
# Wait 10s - app restarts, shows "Info: App restarted by watchdog (1/3 restarts)"

# 3. Kill again from Task Manager
# Wait 10s - app restarts, shows "(2/3 restarts)"

# 4. Kill again from Task Manager
# Wait 10s - app restarts, shows "(3/3 restarts)"

# 5. Kill again from Task Manager
# Wait 10s - app restarts but with "CRITICAL: Restart loop detected!"
# Watchdog is now disabled

# 6. Kill again from Task Manager
# App exits permanently, no more restarts
```

### Check Counter File:
```bash
# View current restart count
type bin\restart_count.tmp
# Shows: "3|1696170000.123"

# Reset counter manually
del bin\restart_count.tmp
```

---

## Benefits

✅ **Automatic Recovery**: Exceptions trigger restart (desired behavior)
✅ **Loop Prevention**: Stops after 3 rapid restarts (prevents infinite loops)
✅ **Time-Based Reset**: Counter resets if app runs stably for 5+ minutes
✅ **Clear Logging**: All restarts logged to `watchdog.log` and application logs
✅ **Operator Notification**: Console shows critical warning on loop detection
✅ **Manual Override**: Can disable watchdog with `--no-watchdog` flag

---

## Production Scenarios

### Scenario 1: Transient Exception (Good)
```
Start → Exception → Restart → Runs OK for 6 minutes → Counter resets
Next exception weeks later → Restart → Counter = 1 (not 2, because time passed)
```

### Scenario 2: Persistent Bug (Protected)
```
Start → Exception → Restart (1/3)
       → Exception → Restart (2/3)
       → Exception → Restart (3/3)
       → Exception → DISABLED (stops looping)
Operator sees warning, fixes bug, manually restarts
```

### Scenario 3: Memory Leak (Prevented)
```
Start → Runs for 3 hours → Memory critical → Restart (1/3)
Counter resets after 5 min stability
Runs for 2 hours → Memory critical → Restart (1/3 again)
Pattern continues, each restart is independent (not counted as loop)
```

---

## Configuration

### Adjust Restart Limit:
```haxe
// In KontentumClient.hx
static public var maxConsecutiveRestarts: Int = 3;  // Change this
```

### Adjust Time Window:
```haxe
// In checkRestartCount() function
if (now - lastRestartTime > 300)  // 300 = 5 minutes, adjust as needed
```

### Reset Counter File:
```bash
# Manually reset if you fixed the issue
del bin\restart_count.tmp
```

---

## Summary Answer

**Your Original Question:**
> "If there is an exception; it should be logged and the app should be restarted, and we should not stop the watchdog. However, we don't want to enter a loop."

**Implementation:**
✅ Exception is logged (`utils.Log.logException`)
✅ Watchdog NOT stopped (continues running)
✅ App restarts automatically (watchdog triggers restart)
✅ Loop prevention via 3-strike counter
✅ Intelligent time-based reset (5-minute window)
✅ Automatic watchdog disable after 3 rapid restarts
✅ Clear operator notification on loop detection

**Result**: Perfect balance between automatic recovery and loop prevention! 🎯
