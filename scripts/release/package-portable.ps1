#Requires -Version 5.1
<#
.SYNOPSIS
  Build a portable X-Stat (jamovi-based) distribution for Windows.

.DESCRIPTION
  Produces dist\<Product>-<Version>-portable\ with:
    - Docker image archive
    - docker-compose.yml
    - start.bat / stop.bat / open.bat
  End users need Docker Desktop. This is the shippable path until a
  native Electron+NSIS pipeline is wired up.
#>
param(
    [string]$ProductName = "X-Stat",
    [string]$ImageName = "jamovi/jamovi:28.1",
    [string]$RepoRoot = "",
    [switch]$SkipBuild,
    [switch]$SkipZip
)

$ErrorActionPreference = "Stop"

if (-not $RepoRoot) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}

Set-Location $RepoRoot
$env:HOME = $env:USERPROFILE

$versionFile = Join-Path $RepoRoot "version"
$version = if (Test-Path $versionFile) {
    (Get-Content $versionFile -Raw).Trim()
} else {
    Get-Date -Format "yyyy.M.d"
}
if (-not $version) { $version = Get-Date -Format "yyyy.M.d" }

$stamp = Get-Date -Format "yyyyMMdd-HHmm"
$distRoot = Join-Path $RepoRoot "dist"
$pkgName = "$ProductName-$version-portable"
$pkgDir = Join-Path $distRoot $pkgName
$imgDir = Join-Path $pkgDir "images"
$imgTar = Join-Path $imgDir "xstat-image.tar"

Write-Host "========================================"
Write-Host " $ProductName portable release"
Write-Host " version : $version"
Write-Host " image   : $ImageName"
Write-Host " out     : $pkgDir"
Write-Host "========================================"

function Assert-Docker {
    docker version --format "{{.Server.Version}}" 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Docker engine is not running. Start Docker Desktop and retry."
    }
}

Assert-Docker

if (-not $SkipBuild) {
    Write-Host "`n[1/4] Building image $ImageName ..."
    docker compose --profile main build
    if ($LASTEXITCODE -ne 0) { throw "docker compose build failed" }
} else {
    Write-Host "`n[1/4] SkipBuild: reuse existing image"
}

$found = docker images -q $ImageName
if (-not $found) {
    throw "Image not found: $ImageName. Run without -SkipBuild."
}

Write-Host "`n[2/4] Preparing package folder ..."
if (Test-Path $pkgDir) { Remove-Item $pkgDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $imgDir | Out-Null

Write-Host "`n[3/4] Saving Docker image (large, may take several minutes) ..."
docker save -o $imgTar $ImageName
if ($LASTEXITCODE -ne 0) { throw "docker save failed" }
$sizeMb = [math]::Round((Get-Item $imgTar).Length / 1MB, 1)
Write-Host "  saved $imgTar ($sizeMb MB)"

# --- package files ---
$compose = @"
services:
  xstat:
    image: $ImageName
    container_name: xstat
    ports:
      - "41337:41337"
      - "41338:41338"
      - "41339:41339"
    command: ["/usr/bin/python3 -u -m jamovi.server 41337 --if=*"]
    environment:
      JAMOVI_ALLOW_ARBITRARY_CODE: "false"
      JAMOVI_HOST_A: "127.0.0.1:41337"
      JAMOVI_HOST_B: "127.0.0.1:41338"
      JAMOVI_HOST_C: "127.0.0.1:41339"
      JAMOVI_ACCESS_KEY: ""
    volumes:
      - ./data:/root/Documents
    stdin_open: true
    stop_grace_period: 1s
"@
Set-Content -Path (Join-Path $pkgDir "docker-compose.yml") -Value $compose -Encoding UTF8

$startBat = @"
@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
set PRODUCT=$ProductName
set IMAGE=$ImageName
set TAR=%~dp0images\xstat-image.tar

where docker >nul 2>&1
if errorlevel 1 (
  echo [ERROR] 未检测到 Docker。请先安装并启动 Docker Desktop。
  echo https://www.docker.com/products/docker-desktop/
  pause
  exit /b 1
)

docker info >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Docker 引擎未运行，请先打开 Docker Desktop。
  pause
  exit /b 1
)

docker image inspect %IMAGE% >nul 2>&1
if errorlevel 1 (
  echo [INFO] 首次运行，正在导入镜像（可能需要几分钟）...
  docker load -i "%TAR%"
  if errorlevel 1 (
    echo [ERROR] 镜像导入失败
    pause
    exit /b 1
  )
)

if not exist "data" mkdir data

echo [INFO] 启动 %PRODUCT% ...
docker compose up -d
if errorlevel 1 (
  echo [ERROR] 启动失败
  pause
  exit /b 1
)

timeout /t 3 /nobreak >nul
start "" "http://127.0.0.1:41337/"
echo.
echo %PRODUCT% 已启动: http://127.0.0.1:41337/
echo 关闭请运行 stop.bat
echo.
pause
"@
Set-Content -Path (Join-Path $pkgDir "start.bat") -Value $startBat -Encoding ASCII

$stopBat = @"
@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo [INFO] 停止 $ProductName ...
docker compose down
echo 已停止。
pause
"@
Set-Content -Path (Join-Path $pkgDir "stop.bat") -Value $stopBat -Encoding ASCII

$openBat = @"
@echo off
start "" "http://127.0.0.1:41337/"
"@
Set-Content -Path (Join-Path $pkgDir "open.bat") -Value $openBat -Encoding ASCII

$readme = @"
# $ProductName $version（便携版）

基于 jamovi 二次开发的桌面统计环境（当前发行形态：Docker 便携包）。

## 用户要求

1. 已安装 [Docker Desktop](https://www.docker.com/products/docker-desktop/)（Windows）
2. Docker Desktop 处于 Running 状态

## 使用

1. 双击 ``start.bat``
   - 首次会自动 ``docker load`` 导入镜像
   - 随后启动服务并打开浏览器
2. 访问地址：http://127.0.0.1:41337/
3. 结束时双击 ``stop.bat``

数据目录：``data\``（映射到容器内文档目录）

## 说明

- 本包是 **可交付给用户** 的发行物，不依赖本机源码树。
- 原生 Windows ``.exe`` 安装包（Electron + NSIS，无 Docker）需要单独的本机编译流水线；见仓库根目录 ``release-native.bat`` 脚手架。

构建信息：
- 镜像：$ImageName
- 打包时间：$stamp
"@
Set-Content -Path (Join-Path $pkgDir "README.txt") -Value $readme -Encoding UTF8

New-Item -ItemType Directory -Force -Path (Join-Path $pkgDir "data") | Out-Null
Set-Content -Path (Join-Path $pkgDir "data\.gitkeep") -Value "" -Encoding ASCII

Write-Host "`n[4/4] Packaging zip ..."
$zipPath = Join-Path $distRoot "$pkgName.zip"
if (-not $SkipZip) {
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Compress-Archive -Path $pkgDir -DestinationPath $zipPath -Force
    $zipMb = [math]::Round((Get-Item $zipPath).Length / 1MB, 1)
    Write-Host "  zip: $zipPath ($zipMb MB)"
} else {
    Write-Host "  SkipZip"
}

Write-Host ""
Write-Host "DONE"
Write-Host "  folder: $pkgDir"
if (-not $SkipZip) { Write-Host "  zip   : $zipPath" }
Write-Host ""
Write-Host "给用户：解压 zip -> 安装 Docker Desktop -> 双击 start.bat"
