#Requires -Version 5.1
<#
.SYNOPSIS
  Assemble X-Stat Windows payload and build Setup.exe + .msi

.DESCRIPTION
  Layout (jamovi-compatible):
    dist/windows/payload/
      bin/X-Stat.exe          (Electron renamed)
      bin/env.conf
      bin/jamovi-engine.exe   (if compiled)
      Resources/client/
      Resources/jamovi/version
      Resources/modules/
      Frameworks/Python/      (embeddable CPython + jamovi server)
      Frameworks/R/           (copied from local R, optional)

  Outputs:
    dist/windows/X-Stat-<ver>-Setup.exe
    dist/windows/X-Stat-<ver>.msi
#>
param(
    [string]$RepoRoot = "",
    [string]$OutRoot = "",
    [string]$ProductName = "X-Stat",
    [string]$ElectronVersion = "33.2.1",
    [switch]$SkipClient,
    [switch]$SkipElectron,
    [switch]$SkipPython,
    [switch]$SkipEngine,
    [switch]$SkipInstallers,
    [switch]$KeepPayload
)

$ErrorActionPreference = "Stop"
if (-not $RepoRoot) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}
Set-Location $RepoRoot

$version = ((Get-Content (Join-Path $RepoRoot "version") -Raw).Trim())
if (-not $version) { $version = "0.1.0" }
# MSI needs up to 4 numeric parts X.Y.Z.W
$msiVersion = ($version -replace '[^0-9.]', '')
if ($msiVersion -notmatch '^\d+\.\d+\.\d+') { $msiVersion = "0.1.0" }

if (-not $OutRoot) { $OutRoot = Join-Path $RepoRoot "dist\windows" }
$outRoot = $OutRoot
$payload = Join-Path $outRoot "payload"
# Use a fresh stage dir each run to avoid Windows Search / AV locks on prior extracts
$stage = Join-Path $outRoot ("stage_" + [guid]::NewGuid().ToString("n").Substring(0, 8))
$cache = Join-Path $outRoot "cache"

Write-Host "========================================"
Write-Host " $ProductName Windows package"
Write-Host " version=$version  msi=$msiVersion"
Write-Host " payload=$payload"
Write-Host "========================================"

function New-Dir($p) {
    if (-not (Test-Path $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null }
}

function Get-Makensis {
    $c = Get-Command makensis -EA SilentlyContinue
    if ($c) { return $c.Source }
    foreach ($p in @(
        "${env:ProgramFiles(x86)}\NSIS\makensis.exe",
        "${env:ProgramFiles}\NSIS\makensis.exe"
    )) { if (Test-Path $p) { return $p } }
    return $null
}

function Remove-PathRetry([string]$Path, [int]$Retries = 8) {
    if (-not (Test-Path $Path)) { return }
    for ($i = 0; $i -lt $Retries; $i++) {
        try {
            $item = Get-Item -LiteralPath $Path -Force
            $tmp = Join-Path $item.DirectoryName ("__del_" + [guid]::NewGuid().ToString("n") + $item.Extension)
            Move-Item -LiteralPath $Path -Destination $tmp -Force -ErrorAction Stop
            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
            if (-not (Test-Path $Path)) { return }
        } catch {
            Start-Sleep -Milliseconds (200 * ($i + 1))
        }
    }
    # last resort: leave locked file, overwrite via temp name later
    Write-Host "  WARN: could not delete locked path: $Path"
}

function Copy-ForceReplace([string]$Src, [string]$Dst) {
    $dir = Split-Path $Dst -Parent
    New-Dir $dir
    if (Test-Path $Dst) {
        Remove-PathRetry $Dst
    }
    if (Test-Path $Dst) {
        $alt = "$Dst.new"
        Copy-Item -LiteralPath $Src -Destination $alt -Force
        Move-Item -LiteralPath $alt -Destination $Dst -Force
    } else {
        Copy-Item -LiteralPath $Src -Destination $Dst -Force
    }
}

function Get-VcvarsBat {
    foreach ($p in @(
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
    )) { if (Test-Path $p) { return $p } }
    return $null
}

function Get-BuildPython {
    # Need a Python 3.12 with headers (embed zip has no Python.h)
    foreach ($c in @(
        "D:\devSoftware\Miniconda3\python.exe",
        "$env:USERPROFILE\miniconda3\python.exe",
        "$env:LOCALAPPDATA\miniconda3\python.exe",
        "C:\ProgramData\miniconda3\python.exe",
        (Get-Command python -EA SilentlyContinue | Select-Object -ExpandProperty Source)
    )) {
        if (-not $c -or -not (Test-Path $c)) { continue }
        $ver = & $c -c "import sys; print('%d.%d'%sys.version_info[:2])" 2>$null
        if ($ver -ne "3.12") { continue }
        $inc = & $c -c "import sysconfig; print(sysconfig.get_path('include'))" 2>$null
        if ($inc -and (Test-Path (Join-Path $inc "Python.h"))) { return $c }
    }
    return $null
}

function Install-JamoviServerSources([string]$RepoRoot, [string]$JamoviPkg) {
    Write-Host "  copying jamovi.server sources (exclude C++ core/) ..."
    New-Dir $JamoviPkg
    # wipe prior tree carefully
    if (Test-Path $JamoviPkg) {
        Get-ChildItem $JamoviPkg -Force | Where-Object {
            $_.Name -ne 'core.cp312-win_amd64.pyd' -and $_.Name -notlike 'core.*.pyd'
        } | Remove-Item -Recurse -Force -EA SilentlyContinue
    }
    New-Dir $JamoviPkg
    Copy-Item (Join-Path $RepoRoot "server\jamovi\__init__.py") $JamoviPkg -Force -EA SilentlyContinue
    Copy-Item (Join-Path $RepoRoot "server\jamovi\server") (Join-Path $JamoviPkg "server") -Recurse -Force
    # do NOT copy jamovi/core/ (C++ sources) — it shadows core.pyd as a namespace package
    # do NOT copy core.pyx / common C++ tree
}

function Install-JamoviProtobuf([string]$RepoRoot, [string]$JamoviPkg, [string]$CacheDir) {
    Write-Host "  generating jamovi_pb2.py ..."
    $protoc = $null
    foreach ($c in @(
        "C:\rtools45\x86_64-w64-mingw32.static.posix\bin\protoc.exe",
        "C:\rtools45\usr\bin\protoc.exe",
        (Get-Command protoc -EA SilentlyContinue | Select-Object -ExpandProperty Source)
    )) { if ($c -and (Test-Path $c)) { $protoc = $c; break } }
    if (-not $protoc) { throw "protoc not found (need Rtools45 protoc)" }
    $protoDir = Join-Path $RepoRoot "server\jamovi\server"
    $outDir = Join-Path $JamoviPkg "server"
    New-Dir $outDir
    & $protoc --proto_path=$protoDir --python_out=$outDir (Join-Path $protoDir "jamovi.proto")
    if ($LASTEXITCODE -ne 0) { throw "protoc failed" }
    if (-not (Test-Path (Join-Path $outDir "jamovi_pb2.py"))) { throw "jamovi_pb2.py missing after protoc" }
}

function Install-JamoviCorePyd([string]$RepoRoot, [string]$PyHome, [string]$OutRoot, [string]$CacheDir) {
    Write-Host "  building jamovi.core (.pyd) with MSVC ..."
    $vcvars = Get-VcvarsBat
    if (-not $vcvars) { throw "vcvars64.bat not found — install VS Build Tools C++" }
    if (-not (Test-Path "C:\local\boost_1_88_0\lib64-msvc-14.3")) {
        throw "Boost 1.88 MSVC libs missing at C:\local\boost_1_88_0\lib64-msvc-14.3"
    }
    $buildPy = Get-BuildPython
    if (-not $buildPy) { throw "Need Python 3.12 with headers (e.g. Miniconda) to compile jamovi.core" }

    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & $buildPy -m pip install -i https://mirrors.aliyun.com/pypi/simple/ --trusted-host mirrors.aliyun.com `
        --quiet cython setuptools wheel 2>$null | Out-Null
    $ErrorActionPreference = $prevEap

    $log = Join-Path $OutRoot "core-build.log"
    $bat = Join-Path $CacheDir "_build_jamovi_core.bat"
    $serverDir = Join-Path $RepoRoot "server"
    @"
@echo off
call "$vcvars"
cd /d "$serverDir"
set SETUP_CORE_ONLY=1
"$buildPy" setup.py build_ext --inplace
echo EXIT=%ERRORLEVEL%
"@ | Set-Content $bat -Encoding ASCII

    cmd /c $bat > $log 2>&1
    $pydSrc = Join-Path $serverDir "jamovi\core.cp312-win_amd64.pyd"
    if (-not (Test-Path $pydSrc)) {
        $pydSrc = Get-ChildItem (Join-Path $serverDir "jamovi") -Filter "core*.pyd" -EA SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
    }
    if (-not $pydSrc -or -not (Test-Path $pydSrc)) {
        throw "jamovi.core build failed — see $log"
    }

    $jamoviPkg = Join-Path $PyHome "Lib\site-packages\jamovi"
    New-Dir $jamoviPkg
    # remove any leftover C++ core/ directory that would shadow the extension
    $coreDir = Join-Path $jamoviPkg "core"
    if (Test-Path $coreDir) { Remove-Item $coreDir -Recurse -Force }
    Remove-Item (Join-Path $jamoviPkg "core.pyx") -Force -EA SilentlyContinue
    Copy-Item $pydSrc (Join-Path $jamoviPkg (Split-Path $pydSrc -Leaf)) -Force
    Write-Host "  core.pyd -> $jamoviPkg"

    # Boost DLLs next to embed python + bin (loader search path)
    $boostLib = "C:\local\boost_1_88_0\lib64-msvc-14.3"
    $binDir = Join-Path (Split-Path (Split-Path $PyHome -Parent) -Parent) "bin"
    foreach ($dll in @(
        "boost_filesystem-vc143-mt-x64-1_88.dll",
        "boost_system-vc143-mt-x64-1_88.dll"
    )) {
        $src = Join-Path $boostLib $dll
        if (Test-Path $src) {
            Copy-Item $src $PyHome -Force
            if (Test-Path $binDir) { Copy-Item $src $binDir -Force }
        }
    }
}

function Install-NanomsgBinding([string]$PyHome, [string]$PayloadBin, [string]$CacheDir, [string]$OutRoot) {
    Write-Host "  installing nanomsg (ctypes) + nanomsg.dll ..."
    if (-not (Test-Path "C:\nanomsg\bin\nanomsg.dll")) {
        throw "C:\nanomsg\bin\nanomsg.dll missing — install nanomsg first"
    }
    $nanoSrcRoot = Join-Path $CacheDir "nanomsg-src"
    $nanoDir = Join-Path $nanoSrcRoot "nanomsg-1.0"
    New-Dir $nanoSrcRoot
    if (-not (Test-Path (Join-Path $nanoDir "setup.py"))) {
        $tar = Join-Path $nanoSrcRoot "nanomsg-1.0.tar.gz"
        if (-not (Test-Path $tar)) {
            $j = Invoke-RestMethod "https://pypi.org/pypi/nanomsg/1.0/json"
            $url = ($j.urls | Where-Object { $_.packagetype -eq "sdist" } | Select-Object -First 1).url
            curl.exe -L --fail -o $tar $url
            if ($LASTEXITCODE -ne 0) { throw "nanomsg sdist download failed" }
        }
        tar -xf $tar -C $nanoSrcRoot
    }
    # Patch: Windows Python 3.12 raises AttributeError (not OSError) for missing nanoconfig
    $setupPy = Join-Path $nanoDir "setup.py"
    $setup = Get-Content $setupPy -Raw
    $setup = $setup -replace 'except OSError:','except Exception:'
    [System.IO.File]::WriteAllText($setupPy, $setup)

    $ctypesInit = Join-Path $nanoDir "_nanomsg_ctypes\__init__.py"
    $ct = Get-Content $ctypesInit -Raw
    $ct = $ct -replace 'except OSError:','except Exception:'
    if ($ct -notmatch 'WinDLL') {
        $ct = $ct -replace "(?s)if sys\.platform in \('win32', 'cygwin'\):\r?\n    _functype = ctypes\.WINFUNCTYPE\r?\n    _lib = ctypes\.windll\.nanomsg\r?\nelse:\r?\n    _functype = ctypes\.CFUNCTYPE\r?\n    _lib = ctypes\.cdll\.LoadLibrary\('libnanomsg\.so'\)", @'
if sys.platform in ('win32', 'cygwin'):
    _functype = ctypes.WINFUNCTYPE
    try:
        _lib = ctypes.windll.nanomsg
    except Exception:
        import os
        _candidates = [
            os.path.join(os.path.dirname(__file__), 'nanomsg.dll'),
            os.path.join(os.path.dirname(sys.executable), 'nanomsg.dll'),
            r'C:\nanomsg\bin\nanomsg.dll',
        ]
        _lib = None
        for _p in _candidates:
            if os.path.isfile(_p):
                _lib = ctypes.WinDLL(_p)
                break
        if _lib is None:
            raise
else:
    _functype = ctypes.CFUNCTYPE
    _lib = ctypes.cdll.LoadLibrary('libnanomsg.so')
'@
    }
    [System.IO.File]::WriteAllText($ctypesInit, $ct)

    $log = Join-Path $OutRoot "nanomsg-install.log"
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    Push-Location $nanoDir
    try {
        & "$PyHome\python.exe" setup.py install --prefix="$PyHome" *> $log
    } finally {
        Pop-Location
        $ErrorActionPreference = $prevEap
    }

    # Vendor DLL beside python, bin, and ctypes package
    Copy-Item "C:\nanomsg\bin\nanomsg.dll" $PyHome -Force
    Copy-Item "C:\nanomsg\bin\nanomsg.dll" $PayloadBin -Force
    $ctypesPkg = Join-Path $PyHome "Lib\site-packages\_nanomsg_ctypes"
    if (Test-Path $ctypesPkg) {
        Copy-Item "C:\nanomsg\bin\nanomsg.dll" $ctypesPkg -Force
        # re-apply nanoconfig Exception patch on installed copy
        $inst = Join-Path $ctypesPkg "__init__.py"
        if (Test-Path $inst) {
            $ic = Get-Content $inst -Raw
            $ic = $ic -replace 'except OSError:','except Exception:'
            [System.IO.File]::WriteAllText($inst, $ic)
        }
    }
    if (-not (Test-Path (Join-Path $PyHome "Lib\site-packages\nanomsg\__init__.py"))) {
        throw "nanomsg install failed — see $log"
    }
    Write-Host "  nanomsg OK"
}

function Disable-NativeFormatioPlugins([string]$JamoviPkg) {
    # jamovi.librdata / readstat native modules are not built yet
    $fmt = Join-Path $JamoviPkg "server\formatio"
    foreach ($name in @("rdata.py", "readstat.py")) {
        $p = Join-Path $fmt $name
        if (Test-Path $p) {
            Move-Item $p "$p.disabled" -Force
            Write-Host "  disabled formatio plugin $name (needs native librdata)"
        }
    }
}

function Get-PathLockers([string]$FilePath) {
    # Restart Manager: list processes holding a file open
    if (-not (Test-Path -LiteralPath $FilePath)) { return @() }
    if (-not ("RmLockQuery" -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;
public static class RmLockQuery {
  [StructLayout(LayoutKind.Sequential)]
  struct RM_UNIQUE_PROCESS { public int dwProcessId; public System.Runtime.InteropServices.ComTypes.FILETIME ProcessStartTime; }
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  struct RM_PROCESS_INFO {
    public RM_UNIQUE_PROCESS Process;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=256)] public string strAppName;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=64)] public string strServiceShortName;
    public uint ApplicationType; public uint AppStatus; public uint TSSessionId;
    [MarshalAs(UnmanagedType.Bool)] public bool bRestartable;
  }
  [DllImport("rstrtmgr.dll", CharSet=CharSet.Unicode)] static extern int RmStartSession(out uint pSessionHandle, int dwSessionFlags, string strSessionKey);
  [DllImport("rstrtmgr.dll")] static extern int RmEndSession(uint pSessionHandle);
  [DllImport("rstrtmgr.dll", CharSet=CharSet.Unicode)] static extern int RmRegisterResources(uint pSessionHandle, uint nFiles, string[] rgsFilenames, uint nApplications, IntPtr rgApplications, uint nServices, string[] rgsServiceNames);
  [DllImport("rstrtmgr.dll")] static extern int RmGetList(uint pSessionHandle, out uint pnProcInfoNeeded, ref uint pnProcInfo, [In, Out] RM_PROCESS_INFO[] rgAffectedApps, ref uint lpdwRebootReasons);
  public static int[] GetPids(string path) {
    uint handle; string key = Guid.NewGuid().ToString();
    var list = new List<int>();
    if (RmStartSession(out handle, 0, key) != 0) return list.ToArray();
    try {
      string[] resources = new string[] { path };
      if (RmRegisterResources(handle, 1, resources, 0, IntPtr.Zero, 0, null) != 0) return list.ToArray();
      uint needed = 0, count = 0, reboot = 0;
      int res = RmGetList(handle, out needed, ref count, null, ref reboot);
      if (res == 234) {
        count = needed;
        RM_PROCESS_INFO[] arr = new RM_PROCESS_INFO[count];
        if (RmGetList(handle, out needed, ref count, arr, ref reboot) == 0) {
          for (int i = 0; i < count; i++) list.Add(arr[i].Process.dwProcessId);
        }
      }
    } finally { RmEndSession(handle); }
    return list.ToArray();
  }
}
"@
    }
    try { return [RmLockQuery]::GetPids($FilePath) } catch { return @() }
}

function Stop-PayloadLockers([string]$PayloadDir) {
    Write-Host "  releasing locks on payload ..."
    # 1) known app processes
    Get-Process -Name "X-Stat","electron" -EA SilentlyContinue | ForEach-Object {
        Write-Host "  stop $($_.ProcessName) pid=$($_.Id)"
        Stop-Process -Id $_.Id -Force -EA SilentlyContinue
    }
    Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='pythonw.exe'" -EA SilentlyContinue | Where-Object {
        $_.CommandLine -and (
            $_.CommandLine -like '*jamovi.server*' -or
            $_.CommandLine -like "*$PayloadDir*"
        )
    } | ForEach-Object {
        Write-Host "  stop python pid=$($_.ProcessId)"
        Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue
    }

    # 2) Restart Manager: anything still holding key files
    $probeFiles = @(
        (Join-Path $PayloadDir "bin\X-Stat.exe"),
        (Join-Path $PayloadDir "bin\resources\default_app.asar"),
        (Join-Path $PayloadDir "bin\env.conf")
    ) | Where-Object { Test-Path -LiteralPath $_ }

    $skip = @{
        'System' = $true; 'csrss' = $true; 'smss' = $true; 'services' = $true
        'lsass' = $true; 'wininit' = $true; 'explorer' = $true
    }
    foreach ($f in $probeFiles) {
        foreach ($lockerPid in (Get-PathLockers $f)) {
            if ($lockerPid -eq $PID) { continue }
            $proc = Get-Process -Id $lockerPid -EA SilentlyContinue
            if (-not $proc) { continue }
            if ($skip.ContainsKey($proc.ProcessName)) { continue }
            Write-Host "  stop locker $($proc.ProcessName) pid=$lockerPid ($f)"
            Stop-Process -Id $lockerPid -Force -EA SilentlyContinue
        }
    }
    Start-Sleep -Seconds 1
}

function Clear-PayloadDir([string]$PayloadDir) {
    if (-not (Test-Path -LiteralPath $PayloadDir)) { return }
    Stop-PayloadLockers $PayloadDir
    Remove-PathRetry $PayloadDir 12
    if (Test-Path -LiteralPath $PayloadDir) {
        # one more unlock + delete cycle
        Stop-PayloadLockers $PayloadDir
        try {
            Remove-Item -LiteralPath $PayloadDir -Recurse -Force -ErrorAction Stop
        } catch {
            $payloadBak = Join-Path (Split-Path $PayloadDir -Parent) ("payload_old_" + [guid]::NewGuid().ToString("n").Substring(0, 8))
            Write-Host "  delete failed, moving aside to $payloadBak"
            Move-Item -LiteralPath $PayloadDir -Destination $payloadBak -Force -ErrorAction Stop
        }
    }
    if (Test-Path -LiteralPath $PayloadDir) {
        throw "payload still locked: $PayloadDir — close X-Stat and any Explorer/Cursor tabs under dist\windows\payload, then retry"
    }
}

# ---------- dirs ----------
# Preserve payload when resuming with SkipElectron/SkipPython (avoid wiping long downloads)
$preservePayload = $KeepPayload -or ($SkipElectron -and $SkipPython)
if ((Test-Path $payload) -and -not $preservePayload) {
    Clear-PayloadDir $payload
}
New-Dir $payload
New-Dir "$payload\bin"
New-Dir "$payload\Resources\client"
New-Dir "$payload\Resources\jamovi"
New-Dir "$payload\Resources\modules"
New-Dir "$payload\Resources\examples"
New-Dir "$payload\Frameworks"
New-Dir $stage
New-Dir $cache

# Reduce Windows Search locking build outputs
try {
    $deskIni = Join-Path $outRoot "desktop.ini"
    if (-not (Test-Path $deskIni)) {
        Set-Content $deskIni "[.ShellClassInfo]`r`nIconResource=%SystemRoot%\system32\SHELL32.dll,4" -Encoding ASCII
    }
} catch {}

Copy-Item (Join-Path $RepoRoot "packaging\windows\env.conf") "$payload\bin\env.conf" -Force
Copy-Item (Join-Path $RepoRoot "version") "$payload\Resources\jamovi\version" -Force
Set-Content "$payload\Resources\modules\.keep" ""

# ---------- 1) client ----------
if (-not $SkipClient) {
    Write-Host "`n[1/6] Build client (vite) ..."
    Push-Location (Join-Path $RepoRoot "client")
    try {
        if (-not (Test-Path "node_modules")) {
            npm install --no-fund --no-audit
            if ($LASTEXITCODE -ne 0) { throw "npm install failed" }
        }
        # coms.proto for client
        $protoSrc = Join-Path $RepoRoot "server\jamovi\server\jamovi.proto"
        New-Dir "assets"
        Copy-Item $protoSrc "assets\coms.proto" -Force
        npm run build
        if ($LASTEXITCODE -ne 0) { throw "vite build failed" }
        $distClient = Join-Path (Get-Location) "dist"
        if (-not (Test-Path $distClient)) { throw "client/dist missing" }
        Copy-Item "$distClient\*" "$payload\Resources\client\" -Recurse -Force
    } finally { Pop-Location }
} else {
    Write-Host "`n[1/6] SkipClient — copy existing client/dist if present"
    $distClient = Join-Path $RepoRoot "client\dist"
    if (Test-Path $distClient) {
        Copy-Item "$distClient\*" "$payload\Resources\client\" -Recurse -Force
    }
}

# ---------- 2) Electron shell -> X-Stat.exe ----------
if (-not $SkipElectron) {
    Write-Host "`n[2/6] Download Electron $ElectronVersion and pack app ..."
    $zipName = "electron-v$ElectronVersion-win32-x64.zip"
    $zipPath = Join-Path $cache $zipName
    $url = "https://npmmirror.com/mirrors/electron/$ElectronVersion/$zipName"
    if (-not (Test-Path $zipPath)) {
        Write-Host "  downloading $url"
        try {
            curl.exe -L --fail --retry 3 -o $zipPath $url
            if ($LASTEXITCODE -ne 0) { throw "curl failed" }
        } catch {
            $url2 = "https://github.com/electron/electron/releases/download/v$ElectronVersion/$zipName"
            Write-Host "  fallback $url2"
            curl.exe -L --fail --retry 3 -o $zipPath $url2
            if ($LASTEXITCODE -ne 0) { throw "electron download failed" }
        }
    }
    $elecDir = Join-Path $stage ("electron_" + [guid]::NewGuid().ToString("n"))
    New-Dir $elecDir
    Write-Host "  extracting to $elecDir"
    Expand-Archive -Path $zipPath -DestinationPath $elecDir -Force

    # pack jamovi electron app as default_app.asar (unique name to avoid locks)
    Push-Location (Join-Path $RepoRoot "electron")
    try {
        if (-not (Test-Path "node_modules\@electron\asar")) {
            npm install --no-fund --no-audit
            if ($LASTEXITCODE -ne 0) { throw "electron npm install failed" }
        }
        $asarOut = Join-Path $stage ("default_app_" + [guid]::NewGuid().ToString("n") + ".asar")
        npx --no-install asar pack app $asarOut
        if ($LASTEXITCODE -ne 0) { throw "asar pack failed" }
        if (-not (Test-Path $asarOut)) { throw "asar output missing" }
    } finally { Pop-Location }

    # Assemble payload/bin WITHOUT mutating extracted Electron tree (avoids AV file locks)
    Copy-Item (Join-Path $elecDir "electron.exe") "$payload\bin\$ProductName.exe" -Force
    Get-ChildItem $elecDir -File | Where-Object { $_.Name -ne "electron.exe" } | ForEach-Object {
        Copy-Item $_.FullName "$payload\bin\$($_.Name)" -Force
    }
    if (Test-Path (Join-Path $elecDir "locales")) {
        Copy-Item (Join-Path $elecDir "locales") "$payload\bin\locales" -Recurse -Force
    }
    New-Dir "$payload\bin\resources"
    Get-ChildItem (Join-Path $elecDir "resources") -Force | Where-Object {
        $_.Name -ne "default_app.asar" -and $_.Name -ne "default_app"
    } | ForEach-Object {
        Copy-Item $_.FullName "$payload\bin\resources\$($_.Name)" -Recurse -Force
    }
    Copy-Item $asarOut "$payload\bin\resources\default_app.asar" -Force
    Write-Host "  wrote $payload\bin\$ProductName.exe"
} else {
    Write-Host "`n[2/6] SkipElectron"
}

# ---------- 3) Embeddable Python + server package ----------
if (-not $SkipPython) {
    Write-Host "`n[3/6] Embeddable Python + jamovi server ..."
    $pyVer = "3.12.10"
    $pyZip = "python-$pyVer-embed-amd64.zip"
    $pyZipPath = Join-Path $cache $pyZip
    $pyUrl = "https://www.python.org/ftp/python/$pyVer/$pyZip"
    if (-not (Test-Path $pyZipPath)) {
        Write-Host "  downloading $pyUrl"
        curl.exe -L --fail --retry 3 -o $pyZipPath $pyUrl
        if ($LASTEXITCODE -ne 0) { throw "python embed download failed" }
    }
    $pyHome = Join-Path $payload "Frameworks\Python"
    if (Test-Path $pyHome) { Remove-Item $pyHome -Recurse -Force }
    New-Dir $pyHome
    Expand-Archive -Path $pyZipPath -DestinationPath $pyHome -Force

    # enable site-packages in ._pth
    $pth = Get-ChildItem $pyHome -Filter "python*._pth" | Select-Object -First 1
    if ($pth) {
        $content = Get-Content $pth.FullName
        $content = $content | ForEach-Object {
            if ($_ -match '^#\s*import site') { 'import site' } else { $_ }
        }
        if ($content -notcontains 'Lib\site-packages') {
            $content = @('Lib\site-packages') + $content
        }
        Set-Content $pth.FullName $content
    }

    # get pip + build backend (needed for any sdists)
    $getPip = Join-Path $cache "get-pip.py"
    if (-not (Test-Path $getPip)) {
        curl.exe -L --fail -o $getPip "https://bootstrap.pypa.io/get-pip.py"
    }
    & "$pyHome\python.exe" $getPip -i https://mirrors.aliyun.com/pypi/simple/ --trusted-host mirrors.aliyun.com
    if ($LASTEXITCODE -ne 0) { throw "get-pip failed" }
    & "$pyHome\python.exe" -m pip install -i https://mirrors.aliyun.com/pypi/simple/ --trusted-host mirrors.aliyun.com `
        --upgrade setuptools wheel pip
    if ($LASTEXITCODE -ne 0) { throw "setuptools/wheel install failed" }

    # Runtime deps: skip nanomsg (needs native lib + compile) and test-only pkgs
    $req = Join-Path $RepoRoot "server\requirements.txt"
    $reqRuntime = Join-Path $cache "requirements-runtime.txt"
    Get-Content $req | Where-Object {
        $_ -notmatch '^\s*#' -and
        $_ -notmatch '^\s*$' -and
        $_ -notmatch '^nanomsg' -and
        $_ -notmatch '^pytest' -and
        $_ -notmatch '^iniconfig' -and
        $_ -notmatch '^pluggy' -and
        $_ -notmatch '^pygments' -and
        $_ -notmatch '^cython'
    } | Set-Content $reqRuntime
    Write-Host "  pip install runtime requirements ..."
    & "$pyHome\python.exe" -m pip install -i https://mirrors.aliyun.com/pypi/simple/ --trusted-host mirrors.aliyun.com -r $reqRuntime
    if ($LASTEXITCODE -ne 0) { throw "pip install requirements failed" }

    $sp = Join-Path $pyHome "Lib\site-packages"
    New-Dir $sp
    $jamoviPkg = Join-Path $sp "jamovi"
    Install-JamoviServerSources -RepoRoot $RepoRoot -JamoviPkg $jamoviPkg
    Install-JamoviProtobuf -RepoRoot $RepoRoot -JamoviPkg $jamoviPkg -CacheDir $cache
    Install-JamoviCorePyd -RepoRoot $RepoRoot -PyHome $pyHome -OutRoot $outRoot -CacheDir $cache
    Install-NanomsgBinding -PyHome $pyHome -PayloadBin (Join-Path $payload "bin") -CacheDir $cache -OutRoot $outRoot
    Disable-NativeFormatioPlugins -JamoviPkg $jamoviPkg

    # smoke: core + nanomsg must import
    & "$pyHome\python.exe" -c "from jamovi.core import ColumnType; import nanomsg; print('native-ok', ColumnType.DATA)"
    if ($LASTEXITCODE -ne 0) { throw "native smoke import failed (jamovi.core / nanomsg)" }
} else {
    Write-Host "`n[3/6] SkipPython"
    $sp = Join-Path $payload "Frameworks\Python\Lib\site-packages"
    $jamoviPkg = Join-Path $sp "jamovi"
    $pyHome = Join-Path $payload "Frameworks\Python"
    if ((Test-Path (Join-Path $pyHome "python.exe")) -and -not (Test-Path (Join-Path $jamoviPkg "server"))) {
        Write-Host "  copying jamovi server sources into site-packages ..."
        Install-JamoviServerSources -RepoRoot $RepoRoot -JamoviPkg $jamoviPkg
        Install-JamoviProtobuf -RepoRoot $RepoRoot -JamoviPkg $jamoviPkg -CacheDir $cache
    }
}

# ---------- 4) Engine (best-effort) ----------
if (-not $SkipEngine) {
    Write-Host "`n[4/6] Build jamovi-engine (best-effort) ..."
    $engineOut = Join-Path $payload "bin\jamovi-engine.exe"
    $log = Join-Path $outRoot "engine-build.log"
    try {
        Push-Location (Join-Path $RepoRoot "engine")
        cmd /c "configure.bat" 2>&1 | Tee-Object $log
        # Prefer Rtools mingw make if available
        $make = $null
        foreach ($c in @(
            "C:\rtools45\usr\bin\make.exe",
            "C:\rtools45\mingw64\bin\mingw32-make.exe"
        )) { if (Test-Path $c) { $make = $c; break } }
        if ($make -and (Test-Path "Makefile")) {
            $env:Path = "C:\rtools45\x86_64-w64-mingw32.static.posix\bin;C:\rtools45\usr\bin;C:\rtools45\mingw64\bin;" + $env:Path
            & $make 2>&1 | Tee-Object $log -Append
            if (Test-Path "jamovi-engine.exe") {
                Copy-Item "jamovi-engine.exe" $engineOut -Force
                Write-Host "  engine OK -> $engineOut"
            } elseif (Test-Path "jamovi-engine") {
                Copy-Item "jamovi-engine" $engineOut -Force
            } else {
                Write-Host "  WARN: engine binary not produced (see $log)"
            }
        } else {
            Write-Host "  WARN: make not found / Makefile missing — skip engine"
        }
    } catch {
        Write-Host "  WARN engine build: $_"
    } finally { Pop-Location }
} else {
    Write-Host "`n[4/6] SkipEngine"
}

# ---------- 5) R Framework (copy local R — analysis modules still needed) ----------
Write-Host "`n[5/6] Copy local R into Frameworks\R (base runtime) ..."
$rSrc = "C:\Program Files\R\R-4.6.1"
$rDst = Join-Path $payload "Frameworks\R"
if (Test-Path $rSrc) {
    New-Dir $rDst
    # copy essential tree (large) — use robocopy for speed
    & robocopy $rSrc $rDst /E /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
    Write-Host "  R copied from $rSrc"
} else {
    Write-Host "  WARN: $rSrc not found — Frameworks\R empty"
}

# ---------- 6) Installers ----------
if (-not $SkipInstallers) {
    Write-Host "`n[6/6] Build Setup.exe (NSIS) and .msi (WiX) ..."
    $setupOut = Join-Path $outRoot "$ProductName-$version-Setup.exe"
    $msiOut = Join-Path $outRoot "$ProductName-$version.msi"

    $makensis = Get-Makensis
    if ($makensis) {
        $nsi = Join-Path $RepoRoot "packaging\windows\xstat.nsi"
        $payloadNsis = $payload -replace '\\', '/'
        & $makensis `
            "/DPRODUCT_NAME=$ProductName" `
            "/DPRODUCT_VERSION=$version" `
            "/DPAYLOAD_DIR=$payload" `
            "/DOUT_FILE=$setupOut" `
            $nsi
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  WARN: makensis failed — skip Setup.exe"
        } else {
            Write-Host "  Setup.exe -> $setupOut"
        }
    } else {
        Write-Host "  WARN: makensis not found — skip Setup.exe (install NSIS)"
    }

    $wix = Get-Command wix -EA SilentlyContinue
    if ($wix) {
        $wxsMain = Join-Path $RepoRoot "packaging\windows\xstat.wxs"
        Write-Host "  wix build (Files harvest) ..."
        # WiX v5+/v6: Files element harvests $(PayloadDir)\**
        & wix build $wxsMain `
            -d "ProductVersion=$msiVersion" `
            -d "PayloadDir=$payload" `
            -o $msiOut `
            -nologo
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  WARN: wix build failed — see output above"
        } elseif (Test-Path $msiOut) {
            Write-Host "  MSI -> $msiOut"
        }
    } else {
        Write-Host "  WARN: wix CLI not found — skip MSI"
    }
} else {
    Write-Host "`n[6/6] SkipInstallers"
}

Write-Host ""
Write-Host "DONE"
Write-Host "  payload : $payload"
Get-ChildItem $outRoot -File -Filter "$ProductName*" -EA SilentlyContinue | ForEach-Object {
    Write-Host ("  {0}  ({1:N1} MB)" -f $_.FullName, ($_.Length/1MB))
}
Write-Host ""
Write-Host "Note: statistical analyses also need jamovi-engine.exe (step 4) and R modules under Resources\modules."
