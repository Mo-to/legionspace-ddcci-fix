@echo off
rem Builds build\dxva2.dll (x64). Needs Visual Studio or the VS Build Tools with the "Desktop development with C++" workload.
setlocal
cd /d "%~dp0"

set "VSINSTALLER=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer"
if not exist "%VSINSTALLER%\vswhere.exe" goto :novs
set "PATH=%PATH%;%VSINSTALLER%"
for /f "usebackq delims=" %%i in (`vswhere.exe -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSDIR=%%i"
if not defined VSDIR goto :novs

call "%VSDIR%\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1
if not exist build mkdir build
cl /nologo /O2 /W4 /MT /LD src\dxva2_proxy.c /Fobuild\ /Febuild\dxva2.dll /link /NOLOGO kernel32.lib user32.lib || exit /b 1
del /q build\*.obj build\*.exp build\*.lib 2>nul
echo Built %CD%\build\dxva2.dll
exit /b 0

:novs
echo Visual Studio / Build Tools with the C++ x64 toolset not found.
exit /b 1
