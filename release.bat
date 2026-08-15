@echo off
chcp 65001 >nul
setlocal EnableExtensions
cd /d "%~dp0"

REM ============================================================
REM  X-Stat / jamovi 一键发布（便携版）
REM  产物: dist\X-Stat-<version>-portable\  与  .zip
REM  用户需安装 Docker Desktop；双击包内 start.bat 即可用
REM ============================================================

set PRODUCT=X-Stat
set SKIP_BUILD=
set SKIP_ZIP=

if /I "%~1"=="--skip-build" set SKIP_BUILD=-SkipBuild
if /I "%~1"=="--skip-zip" set SKIP_ZIP=-SkipZip
if /I "%~2"=="--skip-build" set SKIP_BUILD=-SkipBuild
if /I "%~2"=="--skip-zip" set SKIP_ZIP=-SkipZip

echo.
echo ========================================
echo   %PRODUCT% 一键发布
echo ========================================
echo.

where docker >nul 2>&1
if errorlevel 1 (
  echo [ERROR] 未找到 docker，请先安装并启动 Docker Desktop。
  exit /b 1
)

docker info >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Docker 引擎未运行，请先打开 Docker Desktop。
  exit /b 1
)

where powershell >nul 2>&1
if errorlevel 1 (
  echo [ERROR] 未找到 powershell。
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\release\package-portable.ps1" -ProductName "%PRODUCT%" %SKIP_BUILD% %SKIP_ZIP%
set ERR=%ERRORLEVEL%

if not %ERR%==0 (
  echo.
  echo [ERROR] 发布失败，退出码 %ERR%
  exit /b %ERR%
)

echo.
echo 发布完成。产物在 dist\ 目录。
echo 用法: 把 zip 发给用户，解压后双击 start.bat
echo.
exit /b 0
