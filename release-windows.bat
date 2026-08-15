@echo off
chcp 65001 >nul
setlocal EnableExtensions
cd /d "%~dp0"

REM ============================================================
REM  X-Stat Windows 发布：产出 Setup.exe + .msi
REM  用法:
REM    release-windows.bat
REM    release-windows.bat --skip-engine
REM ============================================================

echo.
echo ========================================
echo   X-Stat -^> Setup.exe + MSI
echo ========================================
echo.

echo.
echo 提示: 打包前请先手动关闭 X-Stat；脚本也会尝试结束占用 dist\windows\payload 的进程
echo.
where powershell >nul 2>&1 || (echo [ERROR] 需要 PowerShell & exit /b 1)

set EXTRA=
if /I "%~1"=="--skip-engine" set EXTRA=-SkipEngine
if /I "%~1"=="--skip-client" set EXTRA=-SkipClient
if /I "%~2"=="--skip-engine" set EXTRA=%EXTRA% -SkipEngine

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\release\build-windows-payload.ps1" %EXTRA%
set ERR=%ERRORLEVEL%

if not %ERR%==0 (
  echo.
  echo [ERROR] 构建失败，退出码 %ERR%
  echo 日志目录: dist\windows\
  exit /b %ERR%
)

echo.
echo 完成。查看:
echo   dist\windows\*-Setup.exe
echo   dist\windows\*.msi
echo   dist\windows\payload\
echo.
exit /b 0
