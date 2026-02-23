# Chrome/Edge Crash Handling Enhancements

## Overview
Enhanced the Chrome crash handler with exponential backoff, crash history tracking, and stability-based recovery - matching the robust SubProcess crash handling system.

---

## What Was Added

### 1. Crash History Tracking
```haxe
static var chromeCrashHistory: Array<Float> = [];        // Track crash timestamps
static var chromeMaxCrashesPerMinute: Int = 5;           // Rate limit
static var chromeStartTime: Float = 0.0;                 // Track browser start time
```

**Purpose:** Track crashes over time to detect rapid crash loops

### 2. Exponential Backoff
```haxe
// Restart delays based on recent crashes (last 60 seconds):
0-1 crashes: 3s   (default)
2-3 crashes: 5s
4-5 crashes: 15s
6-7 crashes: 60s
8+ crashes:  300s (5 minutes!)
```

**Purpose:** Prevent rapid restart loops by increasing delay with each crash

### 3. Rate Limiting
```haxe
if (chromeCrashHistory.length >= 5) {
    // 5+ crashes in 60 seconds
    // Pause for 60 seconds before next restart attempt
}
```

**Purpose:** Prevent server flooding and give browser/system time to recover

### 4. Stability-Based Reset
```haxe
if (uptime > 600 && chromeCrashCount > 0) {
    // Browser stable for 10 minutes
    // Reset crash counter to 0
}
```

**Purpose:** Allow recovery from temporary issues without permanent penalty

### 5. Enhanced Logging
```haxe
trace('Chrome crashed after 45s uptime.')
trace('Crash loop detected. Restarting in 60s (crash #6, total: 6/10)')
trace('Chrome stable for 10min, resetting crash counter (was: 3)')
```

**Purpose:** Better visibility into crash patterns for debugging

---

## Behavior Examples

### Scenario 1: Single Occasional Crash
```
[10:00:00] Chrome started
[10:15:30] Chrome crashed (uptime: 930s)
[10:15:30] Restarting in 3s (crash #1)
[10:15:33] Chrome restarted
[10:25:33] Chrome stable for 10min, reset counter
```
**Result:** Quick recovery, no penalty

### Scenario 2: Rapid Crash Loop
```
[10:00:00] Chrome started
[10:00:05] Chrome crashed (uptime: 5s)
[10:00:05] Restarting in 3s (crash #1)
[10:00:08] Chrome started
[10:00:13] Chrome crashed (uptime: 5s)
[10:00:13] Restarting in 5s (crash #2)
[10:00:18] Chrome started
[10:00:23] Chrome crashed (uptime: 5s)
[10:00:23] Crash loop detected. Restarting in 15s (crash #3)
[10:00:38] Chrome started
[10:00:43] Chrome crashed (uptime: 5s)
[10:00:43] Crash loop detected. Restarting in 60s (crash #4)
```
**Result:** Exponential backoff prevents rapid restarts

### Scenario 3: Rate Limit Hit
```
[10:00:00-10:00:30] 5 crashes in 30 seconds
[10:00:30] WARNING: Crash rate limit exceeded (5 crashes in 60s)
[10:00:30] Pausing restarts for 60s
[10:01:30] Resuming after rate limit pause...
```
**Result:** 60-second pause gives system time to recover

### Scenario 4: Absolute Limit
```
[10:00:00-10:15:00] 10 crashes total
[10:15:00] CRITICAL: Chrome crash limit reached (10/10)
[10:15:00] Disabling auto-restart
```
**Result:** Stops attempting restarts, requires manual intervention

---

## Comparison: Before vs After

### Before (Simple Restart)
| Feature | Status |
|---------|--------|
| Fixed 3s delay | ✅ |
| Max 10 restarts | ✅ |
| Exponential backoff | ❌ |
| Rate limiting | ❌ |
| Crash history | ❌ |
| Counter reset | ❌ |
| **Worst case:** | 10 crashes in 30 seconds |

### After (Smart Restart)
| Feature | Status |
|---------|--------|
| Dynamic delay (3s-300s) | ✅ |
| Max 10 restarts | ✅ |
| Exponential backoff | ✅ |
| Rate limiting (5/min) | ✅ |
| 60s crash history | ✅ |
| 10min stability reset | ✅ |
| **Worst case:** | 5 crashes, then 60s pause |

---

## Configuration

### Current Defaults:
```haxe
chromeRestartDelay = 3.0;              // Initial delay
chromeMaxRestarts = 10;                // Absolute limit
chromeMaxCrashesPerMinute = 5;         // Rate limit
// Stability reset: 10 minutes (hardcoded)
```

### Adjustable via Code:
To change defaults, edit `KontentumClient.hx` lines 52-56:
```haxe
static var chromeRestartDelay        : Float = 3.0;   // Change initial delay
static var chromeMaxRestarts         : Int   = 10;    // Change max restarts
static var chromeMaxCrashesPerMinute : Int   = 5;     // Change rate limit
```

---

## Technical Implementation

### New Functions:

1. **checkChromeStability()** - Called every 500ms when browser alive
   - Checks if uptime > 10 minutes
   - Resets crash counter if stable

2. **cleanChromeCrashHistory()** - Removes old entries
   - Filters crashes older than 60 seconds
   - Called before delay calculation

3. **getChromeRestartDelay()** - Calculates delay
   - Checks recent crash count
   - Returns appropriate delay (3s-300s)

4. **restartChrome()** - Handles restart
   - Gets delay from getChromeRestartDelay()
   - Logs with context
   - Launches and resumes monitoring

### Crash Detection Flow:
```
Monitor (500ms) → checkAlive() → Dead?
                                    ↓
                         handleChromeCrash()
                                    ↓
                    Record timestamp in history
                                    ↓
                    Check absolute limit (10)
                                    ↓
                    Check rate limit (5/min)
                                    ↓
                         restartChrome()
                                    ↓
                  Calculate delay (3s-300s)
                                    ↓
                      Launch → Start monitoring
```

---

## Testing Recommendations

### Test 1: Single Crash
1. Launch browser
2. Wait 2 minutes
3. Kill browser
4. **Expected:** Restarts in 3s, crash #1

### Test 2: Rapid Crashes
1. Launch browser
2. Kill immediately (repeat 4 times within 30s)
3. **Expected:**
   - Crash #1: 3s delay
   - Crash #2: 5s delay
   - Crash #3: 15s delay
   - Crash #4: 60s delay

### Test 3: Rate Limit
1. Launch browser
2. Kill immediately (repeat 5 times within 30s)
3. **Expected:** "Pausing restarts for 60s" message

### Test 4: Stability Reset
1. Launch browser
2. Wait 10+ minutes
3. Kill browser
4. **Expected:** "resetting crash counter" message, restarts in 3s

### Test 5: Absolute Limit
1. Trigger 10 crashes
2. **Expected:** "CRITICAL: Chrome crash limit reached" message, no restart

---

## Benefits

✅ **Prevents Rapid Restart Loops**
- Exponential backoff gives system time to recover
- 300s max delay prevents overwhelming the system

✅ **Protects Server**
- Rate limiting prevents flooding server with BROWSER_CRASH actions
- 60s pause gives server time to respond

✅ **Allows Recovery**
- Stability reset rewards good behavior
- After 10 minutes stable, treated as "fresh start"

✅ **Better Debugging**
- Enhanced logging shows crash patterns
- Uptime included in crash messages

✅ **Production Safe**
- Absolute 10-crash limit prevents infinite loops
- Multiple safety mechanisms work together

---

## Migration Notes

### Breaking Changes
❌ None - fully backward compatible

### Behavioral Changes
✅ Restart delays now dynamic (3s-300s) instead of fixed 3s
✅ Crash counter resets after 10min stability
✅ New rate limiting can pause restarts for 60s

### Log Changes
New log messages to watch for:
- `"Chrome crashed after Xs uptime"`
- `"Crash loop detected. Restarting in Xs"`
- `"Chrome stable for 10min, resetting crash counter"`
- `"Crash rate limit exceeded"`
- `"Pausing restarts for 60s"`

---

## Files Modified

**Single file changed:**
- `src\KontentumClient.hx` (lines 51-502)

**Lines added:** ~100 lines
**Functions added:** 4 new helper functions
**Build status:** ✅ SUCCESS (no errors)

---

## Next Steps

1. ✅ **Code Complete** - All features implemented
2. ✅ **Build Successful** - No compilation errors
3. ⏳ **Testing** - Ready for production testing
4. ⏳ **Monitoring** - Watch logs for crash patterns
5. ⏳ **Tuning** - Adjust delays based on real-world data

---

**Status:** READY FOR DEPLOYMENT
**Confidence:** HIGH - Mirrors proven SubProcess implementation