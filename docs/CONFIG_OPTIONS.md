# KontentumClient Configuration Options

## Overview

KontentumClient can be configured via `config.xml` file located in the same directory as the executable.

---

## Configuration Structure

```xml
<config>
    <kontentum>
        <!-- Kontentum-specific settings -->
    </kontentum>

    <!-- Global application settings -->
    <killexplorer>false</killexplorer>
    <debug>false</debug>
    <watchdog>true</watchdog>
    <disableStartupInstall>false</disableStartupInstall>
    <overridelaunch></overridelaunch>
    <chrome>C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe</chrome>
</config>
```

---

## New Configuration Options

### `<watchdog>` - Watchdog Control

**Purpose**: Enable or disable the watchdog monitoring system

**Type**: Boolean (`true` / `false`)

**Default**: `true` (enabled)

**Behavior**:
- `true`: Watchdog monitors app and restarts on crash/freeze
- `false`: Watchdog disabled, app won't auto-restart

**Example**:
```xml
<watchdog>false</watchdog><!-- Disable watchdog via config -->
```

**Equivalent CLI Flag**: `--no-watchdog`

**Priority**:
1. `--no-watchdog` CLI flag (highest priority)
2. `<watchdog>false</watchdog>` in config.xml
3. Default: enabled

**Use Cases**:
- Development/testing environments where restarts are not desired
- Debugging scenarios where you need app to exit on errors
- Controlled environments where restart behavior is handled externally

---

### `<disableStartupInstall>` - Startup Installation Prompt

**Purpose**: Disable the interactive prompt asking user to install auto-startup

**Type**: Boolean (`true` / `false`)

**Default**: `false` (prompt shown)

**Behavior**:
- `false`: On first run, prompts user: "Do you want KontentumClient to start automatically at login? (Y/N)"
- `true`: Skips the prompt entirely, no installation check performed

**Example**:
```xml
<disableStartupInstall>true</disableStartupInstall><!-- Skip startup prompt -->
```

**Equivalent CLI Flag**: `--skip`

**Priority**:
1. `--skip` CLI flag (highest priority)
2. `<disableStartupInstall>true</disableStartupInstall>` in config.xml
3. Default: show prompt if not installed

**Use Cases**:
- **Shell:Startup scenarios**: When app is placed in `shell:startup` folder, no need for registry entry
- **Managed deployments**: IT departments installing app via GPO/scripts
- **Kiosk mode**: Auto-start handled by system, not registry
- **Portable installations**: Running from USB/network drives

**Important**: This only disables the *prompt*. You can still install via `--install` flag manually.

---

## Complete Example Config

```xml
<config>
    <kontentum>
        <ip>https://kontentum.link</ip>
        <api>rest/pingClient</api>
        <clientID>344</clientID>
        <exhibitToken>s3sxqb</exhibitToken>
        <download>true</download>
        <localFiles>c:/Logic/files</localFiles>
        <forceRebuildCache>false</forceRebuildCache>
        <downloadAllFiles>false</downloadAllFiles>
        <delay>5</delay>
        <fallback>c:/fallback.json</fallback>
        <fallbackdelay>10.0</fallbackdelay>
        <appMonitor>true</appMonitor>
        <restartdelay>2.0</restartdelay>
        <maxCrashesPerMinute>5</maxCrashesPerMinute>
        <maxTotalRestarts>20</maxTotalRestarts>
    </kontentum>

    <!-- Application Settings -->
    <killexplorer>false</killexplorer>
    <debug>false</debug>

    <!-- NEW: Watchdog control -->
    <watchdog>true</watchdog>

    <!-- NEW: Startup installation control -->
    <disableStartupInstall>false</disableStartupInstall>

    <overridelaunch></overridelaunch>
    <chrome>C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe</chrome>
</config>
```

---

## Configuration Scenarios

### Scenario 1: Production Kiosk (Default)
```xml
<watchdog>true</watchdog>
<disableStartupInstall>false</disableStartupInstall>
```
- Watchdog enabled → auto-restart on crash
- Prompts user to install auto-start on first run
- **Use case**: Standard installation on dedicated kiosk PC

### Scenario 2: Development/Testing
```xml
<watchdog>false</watchdog>
<disableStartupInstall>true</disableStartupInstall>
```
- Watchdog disabled → app exits on error (no restart)
- No startup prompt → clean testing environment
- **Use case**: Developer workstation, QA testing
- **Alternative**: Use `--no-watchdog --skip` CLI flags

### Scenario 3: Shell:Startup Deployment
```xml
<watchdog>true</watchdog>
<disableStartupInstall>true</disableStartupInstall>
```
- Watchdog enabled → auto-restart on crash
- No startup prompt → not needed because app is in shell:startup folder
- **Use case**: IT department places shortcut in `shell:startup`
- Registry entry not needed when using shell:startup

### Scenario 4: Managed Enterprise Deployment
```xml
<watchdog>true</watchdog>
<disableStartupInstall>true</disableStartupInstall>
```
- Watchdog enabled → auto-restart on crash
- No startup prompt → IT handles auto-start via GPO
- **Use case**: Centrally managed deployment via Active Directory

---

## CLI Flags vs Config File

| Feature | CLI Flag | Config Option | Priority |
|---------|----------|---------------|----------|
| Disable watchdog | `--no-watchdog` | `<watchdog>false</watchdog>` | CLI wins |
| Skip startup prompt | `--skip` | `<disableStartupInstall>true</disableStartupInstall>` | CLI wins |
| Install startup | `--install` | (none) | Only CLI |
| Uninstall startup | `--uninstall` | (none) | Only CLI |

**Note**: CLI flags always override config file settings

---

## Shell:Startup vs Registry Run Key

### Shell:Startup Folder
**Path**: `C:\Users\<username>\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup`

**Pros**:
- ✅ Simple: Just drop a shortcut
- ✅ Visible: User can see shortcuts in folder
- ✅ Easy to disable: Delete shortcut

**Cons**:
- ❌ Per-user only
- ❌ Depends on Explorer.exe running
- ❌ Easy to break/remove accidentally

**Config for Shell:Startup**:
```xml
<disableStartupInstall>true</disableStartupInstall>
```

### Registry Run Key (Recommended)
**Path**: `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`

**Pros**:
- ✅ Self-managed via `--install` / `--uninstall`
- ✅ More robust than folder shortcuts
- ✅ Survives Explorer crashes
- ✅ Scriptable/automated

**Cons**:
- ❌ Less visible to end user
- ❌ Requires registry editing to remove manually

**Config for Registry**:
```xml
<disableStartupInstall>false</disableStartupInstall>
```
Then run `KontentumClient.exe --install` or respond "Y" to prompt

---

## Debugging Config Issues

### Check Current Config Values:
Run with debug mode:
```xml
<debug>true</debug>
```

Then check logs for:
- `"Watchdog disabled via config.xml"` → watchdog config applied
- `"Startup installation prompt disabled via config.xml"` → disableStartupInstall applied

### Test Config Changes:
```bash
# Test with watchdog disabled in config
# 1. Edit config.xml: <watchdog>false</watchdog>
# 2. Run app
# 3. Check logs - no "Watchdog thread started" message

# Test with startup prompt disabled
# 1. Edit config.xml: <disableStartupInstall>true</disableStartupInstall>
# 2. Run app (without --skip flag)
# 3. Should NOT see "Do you want to install..." prompt
```

### Override Config for Testing:
```bash
# Override config to enable watchdog
KontentumClient.exe
# (remove --no-watchdog flag, config.xml watchdog=true takes effect)

# Override config to skip startup prompt
KontentumClient.exe --skip
# (overrides config.xml disableStartupInstall setting)
```

---

## Migration Guide

### From Shortcut-Based Startup → Registry-Based:

1. Remove shortcut from `shell:startup` folder
2. Edit `config.xml`:
   ```xml
   <disableStartupInstall>false</disableStartupInstall>
   ```
3. Run `KontentumClient.exe` and answer "Y" to prompt
   OR run `KontentumClient.exe --install`
4. Verify: `reg query HKCU\Software\Microsoft\Windows\CurrentVersion\Run /v KontentumClient`

### From Registry-Based → Shortcut-Based:

1. Run `KontentumClient.exe --uninstall` to remove registry entry
2. Edit `config.xml`:
   ```xml
   <disableStartupInstall>true</disableStartupInstall>
   ```
3. Create shortcut to `KontentumClient.exe` in:
   `C:\Users\<username>\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup`
4. Test: Log off and back in

---

## Best Practices

### Production Deployments:
```xml
<watchdog>true</watchdog>
<disableStartupInstall>false</disableStartupInstall>
```
✅ Watchdog protects against crashes
✅ User prompted to install auto-start (one-time)
✅ Self-healing system

### Development Environments:
```xml
<watchdog>false</watchdog>
<disableStartupInstall>true</disableStartupInstall>
```
✅ Clean exit on errors (no restart loops)
✅ No startup prompts during testing
✅ Manual control over app lifecycle

### IT-Managed Deployments:
```xml
<watchdog>true</watchdog>
<disableStartupInstall>true</disableStartupInstall>
```
✅ Watchdog enabled for unattended operation
✅ No user prompts (IT handles startup via GPO/script)
✅ Centrally managed configuration

---

## Files Referenced

- **Config File**: `bin/config.xml` (same directory as exe)
- **Type Definitions**: `src/KontentumClient.hx` (lines 980-990: ConfigXML typedef)
- **Config Loading**: `src/KontentumClient.hx` (lines 397-419: onLoadXMLComplete)
- **Config Application**: `src/KontentumClient.hx` (lines 423-458: initSettings)

---

## Troubleshooting

### Watchdog setting not applied:
- Check `<watchdog>` tag spelling in config.xml
- Ensure value is `true` or `false` (lowercase)
- Check if `--no-watchdog` CLI flag is being used (overrides config)
- Look for log message: "Watchdog disabled via config.xml"

### Startup prompt still showing:
- Check `<disableStartupInstall>` tag spelling
- Ensure value is `true` (not `True` or `TRUE`)
- Check if `--skip` CLI flag is missing
- Verify config.xml is in same directory as exe

### Config changes not taking effect:
- Restart the application after editing config.xml
- Check XML syntax (use XML validator)
- Ensure config.xml is not read-only
- Check file permissions
