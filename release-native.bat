@echo off
chcp 65001 >nul
setlocal EnableExtensions
cd /d "%~dp0"

REM ============================================================
REM  X-Stat 原生 Windows EXE 发布脚手架（Electron + 安装包）
REM
REM  说明:
REM  - 公开 jamovi 仓库不含完整 NSIS/MSIX 流水线
REM  - 本脚本检查本机工具链，并生成 dist\native-checklist\
REM  - 真正打出 .exe 需: 编过 server core / engine / 嵌入 R / Electron 壳
REM  - 当前可交付路径请先用根目录 release.bat（Docker 便携包）
REM ============================================================

echo.
echo ========================================
echo   X-Stat 原生 EXE 脚手架检查
echo ========================================
echo.

set OK=1
set OUT=dist\native-checklist
if not exist "%OUT%" mkdir "%OUT%"

echo [检查] MSVC cl.exe ...
where cl >nul 2>&1 && (echo   OK) || (echo   缺 - 需 VS Build Tools C++ 并配置 PATH & set OK=0)

echo [检查] Boost 1.88 ...
if exist "C:\local\boost_1_88_0\lib64-msvc-14.3" (echo   OK) else (echo   缺 - C:\local\boost_1_88_0 & set OK=0)

echo [检查] R ...
where R >nul 2>&1 && (echo   OK) || (where Rscript >nul 2>&1 && (echo   OK) || (echo   缺 - 需安装 R 4.6+ & set OK=0))

echo [检查] Rtools45 / protoc ...
if exist "C:\rtools45\x86_64-w64-mingw32.static.posix\bin\protoc.exe" (echo   OK) else (echo   缺 - C:\rtools45 & set OK=0)

echo [检查] nanomsg ...
if exist "C:\nanomsg\include\nanomsg\nn.h" (echo   OK) else (echo   缺 - C:\nanomsg & set OK=0)

echo [检查] Node.js ...
where node >nul 2>&1 && (echo   OK) || (echo   缺 - Node.js & set OK=0)

echo [检查] electron 目录 ...
if exist "electron\app\main.js" (echo   OK) else (echo   缺 - electron\ & set OK=0)

(
  echo X-Stat native Windows EXE checklist
  echo Generated: %DATE% %TIME%
  echo.
  echo Target layout ^(typical jamovi Windows tree^):
  echo   bin\X-Stat.exe              ^(Electron shell^)
  echo   bin\jamovi-engine.exe
  echo   bin\env.conf
  echo   Frameworks\R\...
  echo   Resources\client\
  echo   Resources\modules\
  echo   python runtime + jamovi.core.pyd
  echo.
  echo Build stages to implement in scripts\release\native\:
  echo   1. compile server jamovi.core ^(python setup.py / MSVC + Boost^)
  echo   2. compile engine ^(engine\configure.bat + make^)
  echo   3. build client ^(cd client ^&^& npm ci ^&^& npm run build^)
  echo   4. install R packages / jmv modules via jamovi-compiler
  echo   5. pack electron app asar
  echo   6. NSIS or MSIX installer
  echo.
  echo Until the above is automated, ship with release.bat ^(Docker portable^).
) > "%OUT%\README.txt"

echo.
if "%OK%"=="1" (
  echo 工具链基本齐全。下一步实现 scripts\release\native\ 下的分步编译脚本。
  echo 清单已写入 %OUT%\README.txt
) else (
  echo 工具链仍有缺失。可先用 release.bat 打 Docker 便携包交付。
  echo 清单已写入 %OUT%\README.txt
)

echo.
echo 当前推荐交付命令:
echo   release.bat
echo.
pause
exit /b 0
