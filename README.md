# LegionSpace DDC/CI crash fix

Fixes the **blue screen (`KERNEL_SECURITY_CHECK_FAILURE`, 0x139)** that Lenovo Legion laptops hit when a monitor or
USB-C dock is connected while **LegionSpace** is running. It keeps LegionSpace installed and needs no monitor settings
changed.

## Symptoms

- Plug in a USB-C monitor or a USB-C dock (even **without** a screen attached) → instant BSOD.
- The PC may crash in a loop after reboot while the cable stays plugged in.
- Uninstalling LegionSpace or turning off DDC/CI in the monitor menu makes it go away.

### Is it this bug?

- **Event Viewer → Windows Logs → System**, event **1001** (`BugCheck` / `WER-SystemErrorReporting`):
  `The bugcheck was: 0x00000139 (0x0000000000000002, ...)`. The first argument is `2`.
- If you open the minidump (`C:\Windows\Minidump\*.dmp`) in [WinDbg](https://aka.ms/windbg/download) and run `!analyze -v`:
  ```
  PROCESS_NAME:  LegionSpace.exe
  win32kfull!_report_gsfailure+0x5
  win32kfull!CPhysicalMonitorHandle::DdcciGetVCPFeature+0x122
  ```

If you see `LegionSpace.exe` and `DdcciGetVCPFeature`, this fix is for you.

## Cause

LegionSpace reads monitor settings (brightness, contrast, ...) over **DDC/CI** for its Lenovo monitor features:

```
LegionSpace.exe
 └─ SettingManager.dll
     └─ MONITORCONTROL.dll            (Lenovo "Monitor Control Library")
         └─ dxva2!GetVCPFeatureAndVCPFeatureReply
             └─ win32kfull!DdcciGetVCPFeature  ← stack buffer overrun → bugcheck 0x139
```

The reply that comes back over the USB-C / DisplayPort path makes the Windows kernel driver detect a stack buffer
overrun, so Windows stops on purpose. A dock is enough to trigger it, because its DisplayPort converter shows up as a
monitor even with nothing plugged in.

## How the fix works

The fix is a small `dxva2.dll` placed **only in the LegionSpace program folder**. Windows loads it for LegionSpace
instead of `C:\Windows\System32\dxva2.dll`. `dxva2` is not a protected "KnownDLL", so a DLL next to the program wins.

- **Forwarded:** all 13 video / OPM / monitor-enumeration functions are passed straight to the real System32 DLL.
- **Blocked:** all 26 DDC/CI functions (`GetVCPFeatureAndVCPFeatureReply`, `SetVCPFeature`, capability queries,
  brightness/contrast, ...) return `ERROR_GRAPHICS_DDCCI_VCP_NOT_SUPPORTED`. To LegionSpace, every monitor looks like
  one without DDC/CI support, which it already handles.
- The fix changes no Lenovo or Windows files and touches nothing outside the LegionSpace folder. To undo it, delete one
  file.

**What you lose:** controlling an external monitor's settings from inside LegionSpace (only relevant for Lenovo/Legion
monitors). Everything else keeps working: power profiles, fan curves, driver updates, lighting and so on.

## Install

1. Download `legionspace-ddcci-fix.zip` from the [Releases](../../releases) page and extract it. Or build it yourself
   (see below).
2. Open **PowerShell as Administrator** in the extracted folder and run:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\install.ps1 -AutoReinstall
   ```
3. Restart LegionSpace or reboot.

`-AutoReinstall` is recommended. LegionSpace updates install into a new version folder
(`C:\Program Files\Lenovo\LegionSpace\<version>\`), which would not have the fix. The option copies the fix to
`C:\Program Files\LegionSpace-DDCCI-Fix\` and registers a scheduled task that re-applies it at every boot. Without
it, re-run `install.ps1` after each LegionSpace update.

### Verify

After LegionSpace has started, the first blocked calls are logged to `%TEMP%\ddcci-block.log`:

```
2026-10-27 21:51:06 pid=18344 blocked GetVCPFeatureAndVCPFeatureReply
2026-10-27 21:51:07 pid=18344 blocked GetCapabilitiesStringLength
```

LegionSpace usually does this right at startup, even with only the laptop screen. Only the first 50 calls per process
are logged; the blocking itself has no limit.

## Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Uninstall
```

This removes the DLL from all LegionSpace folders, plus the scheduled task and the program folder.

## Build from source

You need Visual Studio 2022+ or the
[Build Tools](https://visualstudio.microsoft.com/visual-cpp-build-tools/) with the *Desktop development with C++*
workload.

```cmd
build.cmd
```

This builds `build\dxva2.dll`; `install.ps1` picks it up from there automatically. The GitHub Actions workflow builds
the same file on every push and attaches the zip to each release, so the binary can be traced back to the source.

## Tested on

| | |
|---|---|
| Laptop | Legion 5 15IRX10 (RTX 5070 Laptop) |
| LegionSpace | 2.0.11.6 |
| Windows | 11 (build 26100 / 26300), x64 |
| Trigger | USB-C dock (GL hubs + RTL8153 LAN, DP alt mode) with and without a Dell S2421HGF |

Other models are very likely affected too (it's the same LegionSpace code). Reports are welcome as issues.

## Other workarounds (without this fix)

- Turn off **DDC/CI** in the monitor's on-screen menu. This doesn't help with docks or monitors you don't control.
- Uninstall LegionSpace.

## Notes

- Some antivirus tools flag an unsigned DLL sitting next to a signed program ("DLL side-loading"), because the same
  technique is used by malware. The source is ~100 lines in `src/dxva2_proxy.c`; read it, or build it yourself.
- x64 only, like LegionSpace.
- Not affiliated with or endorsed by Lenovo or Microsoft. Use at your own risk. The real fix belongs in LegionSpace
  (don't poll DDC/CI on USB-C/dock displays) and in `win32kfull.sys`, which shouldn't bugcheck on a malformed
  monitor reply.
