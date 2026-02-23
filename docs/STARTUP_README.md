# KontentumClient - Self-Managed Startup System

## Overview

KontentumClient now includes a robust, self-managed startup system that uses the Windows Registry Run key instead of the brittle Startup folder shortcut.

## Features

✅ **Self-Installing** - Manages its own startup via Windows Registry
✅ **CLI Control** - Install, uninstall, or skip via command-line flags
✅ **Interactive Prompt** - Asks user on first run if not installed
✅ **Duplicate Prevention** - Uses named mutex to prevent multiple instances
✅ **Per-User** - Uses HKCU (no admin rights required)
✅ **Unicode Safe** - Proper wide-string handling for all paths

## Command-Line Interface

### Installation Commands

**Install Startup (Force)**
```cmd
KontentumClient.exe --install
```
Writes registry key: `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\KontentumClient`
Command: `"C:\full\path\KontentumClient.exe"`

**Uninstall Startup (Force)**
```cmd
KontentumClient.exe --uninstall
```
Removes the registry key entirely.

**Skip Startup Prompt**
```cmd
KontentumClient.exe --skip
```
Runs normally but doesn't check or prompt for startup installation.

## Default Behavior

When run without flags:

1. **Mutex Check** - Ensures only one instance is running
2. **Startup Check** - If not installed, prompts:
   ```
   Startup is not installed.
   Do you want KontentumClient to start automatically at login? (Y/N):
   ```
3. **User Choice**:
   - **Y/yes** → Installs startup immediately
   - **N/no** → Skips, shows install command for later

## Technical Implementation

### Files Created

- `src/utils/WindowsRegistry.hx` - WinAPI bridge for registry operations
- `src/utils/Mutex.hx` - Named mutex for single-instance enforcement
- Updated `src/KontentumClient.hx` - CLI parsing and startup logic

### Registry Details

**Key:** `HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run`
**Value Name:** `KontentumClient`
**Value Type:** `REG_SZ` (Unicode string)
**Value Data:** `"D:\path\to\KontentumClient.exe"`

### Mutex Details

**Name:** `Local\KontentumClient_SingleInstance`
**Scope:** Per-user (matches HKCU registry scope)
**Auto-Release:** Windows automatically releases the mutex if the process crashes
**Behavior:** If another instance is running, exits with message:
```
Another instance of KontentumClient is already running.
```

**Important:** The mutex is automatically released by Windows when the process terminates (even on crash), so the watchdog can successfully restart the application.

## Testing

Run the included test script:
```cmd
test_startup.bat
```

This will:
1. Test `--install` command
2. Verify registry entry exists
3. Test `--uninstall` command
4. Verify registry entry removed

### Manual Testing

**Test Install:**
```cmd
KontentumClient.exe --install
reg query HKCU\Software\Microsoft\Windows\CurrentVersion\Run /v KontentumClient
```

**Test Auto-Start:**
1. Install with `--install`
2. Log off and log back in
3. Verify KontentumClient is running

**Test Duplicate Prevention:**
1. Start KontentumClient.exe normally
2. Try to start another instance
3. Second instance should exit with error message

**Test Uninstall:**
```cmd
KontentumClient.exe --uninstall
reg query HKCU\Software\Microsoft\Windows\CurrentVersion\Run /v KontentumClient
```
Should show "ERROR: The system was unable to find the specified registry key or value."

## Acceptance Criteria

✅ App starts automatically after user logon without Startup shortcut
✅ No duplicate instances on reboot (mutex prevents this)
✅ `--install` and `--uninstall` work reliably on standard user accounts (HKCU)
✅ Rollback is just `--uninstall` or deleting the registry value manually

## Future Enhancements

When needed, you can upgrade to:

- **Scheduled Task** - For delayed start, system account, or ONSTART triggers
- **Windows Service** - For pre-login start and automatic crash recovery

The CLI pattern (`--install`, `--uninstall`) can remain the same while swapping the backend implementation.

## Why This Approach?

| Feature | Startup Folder | Registry Run | Scheduled Task | Service |
|---------|----------------|--------------|----------------|---------|
| No Admin Required | ✅ | ✅ | ❌ | ❌ |
| Survives User Changes | ❌ | ✅ | ✅ | ✅ |
| Self-Managed | ❌ | ✅ | ⚠️ | ⚠️ |
| Per-User | ✅ | ✅ | ✅ | ❌ |
| Simple to Implement | ✅ | ✅ | ❌ | ❌ |

The Registry Run key is the sweet spot for per-user, self-managed startup that's more robust than shortcuts but simpler than tasks or services.

## Troubleshooting

**"Another instance is already running"**
- Check Task Manager for `KontentumClient.exe`
- Kill the process or reboot

**Startup not working after reboot**
- Verify registry entry exists:
  ```cmd
  reg query HKCU\Software\Microsoft\Windows\CurrentVersion\Run /v KontentumClient
  ```
- Re-run `KontentumClient.exe --install`

**Can't uninstall**
- Manual removal:
  ```cmd
  reg delete HKCU\Software\Microsoft\Windows\CurrentVersion\Run /v KontentumClient /f
  ```

## Code Reference

- CLI parsing: [KontentumClient.hx:64-131](src/KontentumClient.hx#L64)
- Install handler: [KontentumClient.hx:143-162](src/KontentumClient.hx#L143)
- Uninstall handler: [KontentumClient.hx:164-180](src/KontentumClient.hx#L164)
- Startup check: [KontentumClient.hx:182-219](src/KontentumClient.hx#L182)
- Registry operations: [WindowsRegistry.hx](src/utils/WindowsRegistry.hx)
- Mutex management: [Mutex.hx](src/utils/Mutex.hx)
