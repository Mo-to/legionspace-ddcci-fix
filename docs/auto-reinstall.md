# How `-AutoReinstall` works

LegionSpace installs each update into a new version folder (`C:\Program Files\Lenovo\LegionSpace\<version>\`). That
folder doesn't contain the fix, so after an update the crash would come back. `-AutoReinstall` takes care of that.

## What gets installed

| What | Where |
|---|---|
| A copy of `dxva2.dll` and `install.ps1` | `C:\Program Files\LegionSpace-DDCCI-Fix\` |
| Scheduled task **"LegionSpace DDC-CI Fix"** | Task Scheduler (root folder) |
| Log of every install the task makes | `C:\Program Files\LegionSpace-DDCCI-Fix\install.log` |

## What the task does

Windows Task Scheduler starts `install.ps1` from that folder **at boot, at logon and every 10 minutes**. Each run:

1. Lists the folders under `C:\Program Files\Lenovo\LegionSpace\` that contain `LegionSpace.exe`.
2. Compares the hash of each folder's `dxva2.dll` with the fix.
3. If they match, which is almost always, it **exits right away**.
4. If a folder is missing the fix (a new LegionSpace version), it copies the DLL in and writes a line to `install.log`.

**Nothing stays running in the background.** There's no service and no resident process: each run is a short,
hidden PowerShell start (about a second) that then exits. 144 runs a day cost practically nothing.

The task runs as **SYSTEM** (writing to `C:\Program Files` needs admin rights), also on battery. It runs the copy in
`C:\Program Files\LegionSpace-DDCCI-Fix\`, which only administrators can change, so the task can't be abused to run
someone else's code with SYSTEM rights.

## Why every 10 minutes?

The boot run (before LegionSpace starts at logon) covers most cases. The 10-minute repetition is for LegionSpace
updates installed **mid-session**, so the new version gets the fix soon after, not only at the next reboot.

**One gap remains:** a LegionSpace instance that is already running only picks up the fix when it restarts. If
LegionSpace updated and restarted itself in the last few minutes, restart it once more, or reboot, before you connect
a dock or USB-C monitor.

## Check it

In an admin PowerShell:

```powershell
Get-ScheduledTask 'LegionSpace DDC-CI Fix' | Get-ScheduledTaskInfo   # last/next run, last result (0 = OK)
Get-Content 'C:\Program Files\LegionSpace-DDCCI-Fix\install.log'      # installs the task has made
```

Without admin rights the task is not visible (`schtasks` says "access denied"). That is expected.

## Only at boot and logon, no repetition

If you'd rather not have the 10-minute repetition, remove that trigger in Task Scheduler (task → Properties →
Triggers). The trade-off: after a LegionSpace update the fix only arrives at the next logon or reboot.

## Remove it

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Uninstall
```

This removes the task, `C:\Program Files\LegionSpace-DDCCI-Fix\`, and the DLL from all LegionSpace folders.
