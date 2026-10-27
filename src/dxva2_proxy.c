// dxva2.dll proxy for Lenovo LegionSpace.
//
// Problem: LegionSpace.exe -> SettingManager.dll -> MONITORCONTROL.dll calls dxva2!GetVCPFeatureAndVCPFeatureReply
// on USB-C / dock displays. The reply overflows a stack buffer in win32kfull!CPhysicalMonitorHandle::DdcciGetVCPFeature
// -> bugcheck 0x139 (KERNEL_SECURITY_CHECK_FAILURE, arg1 = 2).
//
// Fix: this DLL sits next to LegionSpace.exe, so the loader picks it before System32\dxva2.dll (dxva2 is not a
// KnownDLL). Video / OPM / physical-monitor-enumeration exports are forwarded to the real DLL. Every export that sends
// DDC/CI traffic to the monitor fails with ERROR_GRAPHICS_DDCCI_VCP_NOT_SUPPORTED, i.e. LegionSpace sees a monitor
// without DDC/CI support. Ordinals match System32\dxva2.dll of Windows 11 (10.0.26100.x).

#include <windows.h>

// ---- forwarded to the real dxva2.dll ----
#define FWD(name, ord) __pragma(comment(linker, "/export:" #name "=C:\\Windows\\System32\\dxva2." #name ",@" #ord))
FWD(GetPhysicalMonitorFromTarget, 1)
FWD(DXVA2CreateDirect3DDeviceManager9, 3)
FWD(DXVA2CreateVideoService, 4)
FWD(DXVAHD_CreateDevice, 5)
FWD(DestroyPhysicalMonitor, 7)
FWD(DestroyPhysicalMonitors, 8)
FWD(GetNumberOfPhysicalMonitorsFromHMONITOR, 19)
FWD(GetNumberOfPhysicalMonitorsFromIDirect3DDevice9, 20)
FWD(GetPhysicalMonitorsFromHMONITOR, 21)
FWD(GetPhysicalMonitorsFromIDirect3DDevice9, 22)
FWD(OPMGetVideoOutputForTarget, 25)
FWD(OPMGetVideoOutputsFromHMONITOR, 26)
FWD(OPMGetVideoOutputsFromIDirect3DDevice9Object, 27)

// ---- DDC/CI traffic: blocked ----
static volatile LONG g_logged;

static void LogBlocked(const char *name)
{
    // First 50 blocked calls per process go to %TEMP%\ddcci-block.log, so the fix can be verified.
    if (InterlockedIncrement(&g_logged) > 50)
        return;
    char path[MAX_PATH];
    DWORD n = GetTempPathA(MAX_PATH - 20, path);
    if (n == 0 || n >= MAX_PATH - 20)
        return;
    lstrcatA(path, "ddcci-block.log");
    HANDLE h = CreateFileA(path, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_ALWAYS,
                           FILE_ATTRIBUTE_NORMAL, NULL);
    if (h == INVALID_HANDLE_VALUE)
        return;
    SYSTEMTIME t;
    GetLocalTime(&t);
    char line[256];
    int len = wsprintfA(line, "%04u-%02u-%02u %02u:%02u:%02u pid=%lu blocked %s\r\n", t.wYear, t.wMonth, t.wDay,
                        t.wHour, t.wMinute, t.wSecond, GetCurrentProcessId(), name);
    DWORD written;
    WriteFile(h, line, (DWORD)len, &written, NULL);
    CloseHandle(h);
}

// All blocked APIs return BOOL. On x64 there is a single calling convention and the caller owns the stack,
// so a parameterless stub is ABI-safe for every signature.
#define BLOCK(name, ord)                                             \
    BOOL WINAPI Block_##name(void)                                   \
    {                                                                \
        LogBlocked(#name);                                           \
        SetLastError((DWORD)ERROR_GRAPHICS_DDCCI_VCP_NOT_SUPPORTED); \
        return FALSE;                                                \
    }                                                                \
    __pragma(comment(linker, "/export:" #name "=Block_" #name ",@" #ord))

BLOCK(CapabilitiesRequestAndCapabilitiesReply, 2)
BLOCK(DegaussMonitor, 6)
BLOCK(GetCapabilitiesStringLength, 9)
BLOCK(GetMonitorBrightness, 10)
BLOCK(GetMonitorCapabilities, 11)
BLOCK(GetMonitorColorTemperature, 12)
BLOCK(GetMonitorContrast, 13)
BLOCK(GetMonitorDisplayAreaPosition, 14)
BLOCK(GetMonitorDisplayAreaSize, 15)
BLOCK(GetMonitorRedGreenOrBlueDrive, 16)
BLOCK(GetMonitorRedGreenOrBlueGain, 17)
BLOCK(GetMonitorTechnologyType, 18)
BLOCK(GetTimingReport, 23)
BLOCK(GetVCPFeatureAndVCPFeatureReply, 24)
BLOCK(RestoreMonitorFactoryColorDefaults, 28)
BLOCK(RestoreMonitorFactoryDefaults, 29)
BLOCK(SaveCurrentMonitorSettings, 30)
BLOCK(SaveCurrentSettings, 31)
BLOCK(SetMonitorBrightness, 32)
BLOCK(SetMonitorColorTemperature, 33)
BLOCK(SetMonitorContrast, 34)
BLOCK(SetMonitorDisplayAreaPosition, 35)
BLOCK(SetMonitorDisplayAreaSize, 36)
BLOCK(SetMonitorRedGreenOrBlueDrive, 37)
BLOCK(SetMonitorRedGreenOrBlueGain, 38)
BLOCK(SetVCPFeature, 39)

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, LPVOID reserved)
{
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH)
        DisableThreadLibraryCalls(inst);
    return TRUE;
}
