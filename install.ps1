#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs the DDC/CI-blocking dxva2.dll next to LegionSpace.exe (every installed version folder).

.PARAMETER AutoReinstall
    Also copies the fix to "C:\Program Files\LegionSpace-DDCCI-Fix" and registers a scheduled task that re-applies it
    at every boot, so LegionSpace updates (which create a new version folder) stay fixed.

.PARAMETER Uninstall
    Removes the DLL from all LegionSpace version folders, the scheduled task and the program folder.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\install.ps1 -AutoReinstall
#>
param(
    [switch]$AutoReinstall,
    [switch]$Uninstall,
    [string]$LegionSpaceRoot = (Join-Path $env:ProgramFiles 'Lenovo\LegionSpace')
)

$ErrorActionPreference = 'Stop'
$TaskName = 'LegionSpace DDC-CI Fix'
$FixDir = Join-Path $env:ProgramFiles 'LegionSpace-DDCCI-Fix'

function Get-LegionSpaceDirs {
    if (-not (Test-Path $LegionSpaceRoot)) { return @() }
    Get-ChildItem $LegionSpaceRoot -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'LegionSpace.exe') }
}

# Copies or deletes a file in a LegionSpace folder; if LegionSpace has the old DLL loaded, close it and retry.
function Invoke-WithLegionSpaceClosed([scriptblock]$Action) {
    try { & $Action }
    catch [System.IO.IOException], [System.UnauthorizedAccessException] {
        Write-Host '  file in use, closing LegionSpace and retrying...'
        Get-Process LegionSpace -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Seconds 2
        & $Action
    }
}

if ($Uninstall) {
    foreach ($d in Get-LegionSpaceDirs) {
        $dst = Join-Path $d.FullName 'dxva2.dll'
        if (Test-Path $dst) {
            Invoke-WithLegionSpaceClosed { Remove-Item $dst -Force }
            Write-Host "removed  $dst"
        }
    }
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "removed  scheduled task '$TaskName'"
    }
    if ((Test-Path $FixDir) -and ($PSScriptRoot -ne $FixDir)) {
        Remove-Item $FixDir -Recurse -Force
        Write-Host "removed  $FixDir"
    }
    Write-Host 'Done. Restart LegionSpace (or reboot).'
    return
}

$src = @((Join-Path $PSScriptRoot 'dxva2.dll'), (Join-Path $PSScriptRoot 'build\dxva2.dll')) |
    Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $src) { throw 'dxva2.dll not found next to install.ps1 or in .\build - download a release or run build.cmd first.' }

$dirs = @(Get-LegionSpaceDirs)
if (-not $dirs) { throw "No LegionSpace.exe found under $LegionSpaceRoot (use -LegionSpaceRoot)." }

$srcHash = (Get-FileHash $src).Hash
foreach ($d in $dirs) {
    $dst = Join-Path $d.FullName 'dxva2.dll'
    if ((Test-Path $dst) -and (Get-FileHash $dst).Hash -eq $srcHash) {
        Write-Host "up to date $dst"
        continue
    }
    Invoke-WithLegionSpaceClosed { Copy-Item $src $dst -Force }
    Write-Host "installed  $dst"
}

if ($AutoReinstall) {
    New-Item -ItemType Directory -Force $FixDir | Out-Null
    if ($PSScriptRoot -ne $FixDir) {
        Copy-Item $src (Join-Path $FixDir 'dxva2.dll') -Force
        Copy-Item $PSCommandPath (Join-Path $FixDir 'install.ps1') -Force
    }
    # Runs from Program Files (admin-only writable) as SYSTEM at boot, before LegionSpace starts at logon.
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$FixDir\install.ps1`""
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
    Write-Host "registered scheduled task '$TaskName' (re-applies the fix at every boot)"
}

Write-Host 'Done. Restart LegionSpace (or reboot) so it loads the fixed DLL.'
