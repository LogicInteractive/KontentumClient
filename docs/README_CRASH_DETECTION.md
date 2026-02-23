# Chrome/Edge Crash Detection Feature

## 🎯 Quick Summary

This feature automatically detects when Chrome/Edge crashes in browser mode and restarts it.

**Status:** ✅ **TESTED AND WORKING**

---

## 📋 What It Does

- Monitors Chrome/Edge process every 500ms
- Detects crashes within half a second
- Automatically restarts browser with last URL
- Sends crash notifications to server
- Prevents infinite loops (max 10 restarts)

---

## 🚀 How to Use

### For End Users:
**Nothing required!** The feature activates automatically when running in browser mode.

### For Developers:

**Deploy:**
```bash
# Copy the new exe to production
copy bin\KontentumClient.exe <production-location>
```

**Monitor:**
- Check server logs for `BROWSER_CRASH` actions
- Normal: 0-1 crashes per day
- Issue: 3+ crashes per hour
- Critical: Hitting 10-crash limit

---

## 📁 Files Changed

**Modified:**
- `c:\dev\fox\fox\hx\fox\native\windows\Chrome.hx` - Added crash detection
- `src\KontentumClient.hx` - Added monitoring and restart logic

**Test Files:**
- `bin\TestChromeCrash.exe` - Standalone test program
- `test_chrome_crash.bat` - Automated test script
- `test_chrome_crash_advanced.bat` - Advanced test with logs

**Documentation:**
- `TEST_RESULTS.md` - Full test results ✅ PASSED
- `TEST_CHROME_CRASH.md` - Testing instructions
- `IMPLEMENTATION_SUMMARY.md` - Technical details
- `README_CRASH_DETECTION.md` - This file

---

## ⚙️ Configuration

### Default Settings (in KontentumClient.hx):
```haxe
chromeRestartDelay = 3.0;    // Seconds before restart
chromeMaxRestarts  = 10;     // Max restarts before giving up
// Check interval: 500ms (hardcoded in Timer)
```

### Config XML:
```xml
<config>
    <!-- Browser executable path -->
    <chrome>C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe</chrome>

    <kontentum>
        <!-- Fallback URL if cached URL not available -->
        <fallback>https://your-fallback-url.com</fallback>
    </kontentum>
</config>
```

---

## 🧪 Testing

### Run Standalone Test:
```bash
run_standalone_test.bat
```

**Expected:**
1. Edge opens in kiosk mode
2. Console shows "Chrome is alive ✓" every second
3. Kill Edge in Task Manager
4. Console shows "Chrome is DEAD ✗"
5. Test passes ✅

### Run Automated Tests:
```bash
# Basic test
test_chrome_crash.bat

# Advanced test with log monitoring
test_chrome_crash_advanced.bat
```

---

## 🔍 How It Works Technically

```
┌─────────────────────────────────────────┐
│  Server sends web URL                   │
└────────────────┬────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────┐
│  launchChrome(url)                      │
│  - Launches Edge/Chrome in kiosk mode  │
│  - Caches URL to file                   │
└────────────────┬────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────┐
│  startChromeMonitoring()                │
│  - Timer checks every 500ms             │
└────────────────┬────────────────────────┘
                 │
                 ▼
         ┌───────────────┐
         │ checkAlive()  │
         │ every 500ms   │
         └───┬───────────┘
             │
    ┌────────┴────────┐
    │                 │
    ▼                 ▼
┌────────┐      ┌──────────┐
│  TRUE  │      │  FALSE   │
│ Alive  │      │ Crashed! │
└────────┘      └─────┬────┘
                      │
                      ▼
          ┌───────────────────────┐
          │ handleChromeCrash()   │
          │ - Log crash event     │
          │ - Send to server      │
          │ - Wait 3 seconds      │
          │ - Relaunch browser    │
          │ - Restart monitoring  │
          └───────────────────────┘
```

---

## 🐛 Troubleshooting

### Browser doesn't restart:
- Check if cached URL file exists: `c:/temp/kontentum_offlinelaunch`
- Verify fallback URL in config.xml
- Check if 10-crash limit was reached

### False crash detection:
- Not possible - checks for process name existence
- If reporting false crashes, check logs for actual errors

### Multiple restarts:
- Normal for actual crashes
- If excessive (>5/hour), investigate root cause:
  - Video codec issues
  - Memory leaks
  - Network problems
  - Invalid web content

---

## 📊 Server Integration

### Action Sent:
```
Action: "BROWSER_CRASH"
```

### Recommended Server Response:
1. Log the crash event with timestamp
2. Track crash frequency per client
3. Alert if crash rate exceeds threshold
4. Consider sending different URL if crashes persist

### Example Server Log Entry:
```
[2025-09-30 10:29:15] Client #344: BROWSER_CRASH (crash #3, uptime: 2h 15m)
```

---

## 📝 Notes

- Feature only activates in browser mode (web URLs)
- Does not affect normal application mode (exe/batch files)
- Crash counter resets on client restart
- Works with both Chrome and Edge
- Process name detection handles multi-process browsers correctly

---

## ✅ Test Results

**Last Tested:** September 30, 2025
**Result:** ✅ PASSED
**Environment:** Windows 10, Edge Browser

See `TEST_RESULTS.md` for full test output.

---

## 📞 Support

For issues or questions:
1. Check logs at: `C:\ProgramData\KontentumClient\logs\`
2. Review `TEST_RESULTS.md` for expected behavior
3. Run `TestChromeCrash.exe` to verify functionality
4. Check server logs for `BROWSER_CRASH` actions

---

**End of Documentation**