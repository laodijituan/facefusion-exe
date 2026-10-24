<#
.SYNOPSIS
    Builds a portable FaceFusion Windows EXE (onedir, no installer needed).

.DESCRIPTION
    Steps: checkout source -> venv -> pip install runtime deps -> fetch ffmpeg
    -> PyInstaller -> copy helpers next to the exe -> zip + sha256.

.EXAMPLE
    .\build_windows.ps1 -Variant cuda12
    .\build_windows.ps1 -Variant cpu -Ref 7247081
    .\build_windows.ps1 -Variant cuda12 -NoCudaRuntime -NoZip
#>
[CmdletBinding()]
param(
    [ValidateSet('cpu', 'cuda12', 'cuda13', 'directml')]
    [string]$Variant = 'cuda12',

    # FaceFusion git ref (branch, tag or commit). Pin a commit for reproducible builds.
    [string]$Ref = '7247081',

    # Bundle cuDNN9 + cuBLAS12 + cudart12 DLLs so the user needs no CUDA install.
    [switch]$NoCudaRuntime,

    [switch]$NoZip,

    [string]$WorkDir = (Join-Path $PSScriptRoot '.work')
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Set-StrictMode -Version Latest

$FFRepo      = 'https://github.com/facefusion/facefusion.git'
$FfmpegUrl   = 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip'
$PythonVer   = '3.12'
$AppName     = 'FaceFusion'
$DistDir     = Join-Path $WorkDir 'dist'
$SrcDir      = Join-Path $WorkDir 'src\facefusion'
$VenvDir     = Join-Path $WorkDir '.venv'

function Write-Step($Text) { Write-Host "`n=== $Text ===" -ForegroundColor Cyan }

# ---------------------------------------------------------------------------
Write-Step 'Checking prerequisites'
$py = (Get-Command python -ErrorAction SilentlyContinue)
if (-not $py) { throw 'python not found on PATH (need Python 3.12 x64)' }
$pyVersion = (& python -c "import sys;print('%d.%d'%sys.version_info[:2])").Trim()
Write-Host "python $pyVersion"
if ($pyVersion -ne $PythonVer) {
    throw "Python $PythonVer required (found $pyVersion). Install it from python.org, or use the GitHub Actions workflow."
}

New-Item -ItemType Directory -Force -Path $WorkDir, $DistDir | Out-Null

# ---------------------------------------------------------------------------
Write-Step "Fetching FaceFusion @ $Ref"
if (Test-Path (Join-Path $SrcDir '.git')) {
    git -C $SrcDir fetch --all --tags --quiet
    git -C $SrcDir checkout --quiet $Ref
    git -C $SrcDir pull --quiet 2>$null
} else {
    git clone --quiet $FFRepo $SrcDir
    git -C $SrcDir checkout --quiet $Ref
}
$commit = (& git -C $SrcDir rev-parse --short HEAD).Trim()
Write-Host "source commit: $commit"

# ---------------------------------------------------------------------------
Write-Step 'Preparing virtual environment'
if (-not (Test-Path (Join-Path $VenvDir 'Scripts\python.exe'))) {
    python -m venv $VenvDir
}
$venvPy  = Join-Path $VenvDir 'Scripts\python.exe'
$venvPip = Join-Path $VenvDir 'Scripts\pip.exe'
& $venvPy -m pip install --upgrade --quiet pip
& $venvPip install --quiet -r (Join-Path $SrcDir 'requirements.txt')
& $venvPip install --quiet -r (Join-Path $PSScriptRoot 'requirements-build.txt')

switch ($Variant) {
    'cpu'      { & $venvPip install --quiet --force-reinstall 'onnxruntime==1.30.0' }
    'cuda12'   { & $venvPip install --quiet --force-reinstall 'onnxruntime-gpu==1.24.4' }
    'cuda13'   { & $venvPip install --quiet --force-reinstall 'onnxruntime-gpu==1.30.0' }
    'directml' { & $venvPip install --quiet --force-reinstall 'onnxruntime-directml==1.24.4' }
}

$cudaDir = ''
if ($Variant -eq 'cuda12' -and -not $NoCudaRuntime) {
    Write-Step 'Installing bundled CUDA runtime (cuDNN 9 / cuBLAS 12 / cudart 12)'
    # only the CUDA 12 runtime is shipped as pip wheels (win_amd64 builds exist);
    # for cuda13 install the CUDA toolkit manually and build with -NoCudaRuntime
    & $venvPip install --quiet 'nvidia-cudnn-cu12==9.*' 'nvidia-cublas-cu12==12.*' 'nvidia-cuda-runtime-cu12==12.*'
    $cudaDir = (& $venvPy -c "import sysconfig,os;print(os.path.join(sysconfig.get_paths()['purelib'],'nvidia'))").Trim()
    if (-not (Test-Path $cudaDir)) { throw "CUDA runtime wheels did not provide $cudaDir" }
    Write-Host "CUDA runtime dir: $cudaDir"
}

# ---------------------------------------------------------------------------
Write-Step 'Fetching ffmpeg / ffprobe'
$ffmpegZip = Join-Path $WorkDir 'ffmpeg.zip'
if (-not (Test-Path $ffmpegZip)) {
    Invoke-WebRequest -Uri $FfmpegUrl -OutFile $ffmpegZip
}
$ffmpegOut = Join-Path $WorkDir 'ffmpeg'
if (-not (Test-Path $ffmpegOut)) {
    Expand-Archive -Path $ffmpegZip -DestinationPath $ffmpegOut -Force
}

# ---------------------------------------------------------------------------
Write-Step "Building $AppName ($Variant)"
$env:FF_SRC     = $SrcDir
$env:FF_VARIANT = $Variant
$env:FF_CUDA_DIR = $cudaDir
$spec = Join-Path $PSScriptRoot 'facefusion.spec'
& (Join-Path $VenvDir 'Scripts\pyinstaller.exe') --noconfirm --distpath $DistDir --workpath (Join-Path $WorkDir 'build') --specpath $WorkDir $spec
if ($LASTEXITCODE -ne 0) { throw 'PyInstaller failed' }

$appDir = Join-Path $DistDir $AppName
if (-not (Test-Path $appDir)) { throw "build output missing: $appDir" }

# ---------------------------------------------------------------------------
Write-Step 'Adding bundle helpers (ffmpeg, curl, readme)'
$ffmpegBin = Get-ChildItem -Path $ffmpegOut -Recurse -Filter 'ffmpeg.exe' | Select-Object -First 1
Copy-Item $ffmpegBin.FullName (Join-Path $appDir 'ffmpeg.exe') -Force
$ffprobeBin = Get-ChildItem -Path $ffmpegOut -Recurse -Filter 'ffprobe.exe' | Select-Object -First 1
Copy-Item $ffprobeBin.FullName (Join-Path $appDir 'ffprobe.exe') -Force

# FaceFusion downloads its models with the system curl; ship one so old Win10 builds work too
$curl = Join-Path $env:SystemRoot 'System32\curl.exe'
if (Test-Path $curl) { Copy-Item $curl (Join-Path $appDir 'curl.exe') -Force }

Copy-Item (Join-Path $PSScriptRoot 'bundle-readme.txt') (Join-Path $appDir '使用说明.txt') -Force

$stamp = "FaceFusion $AppName portable`r`nvariant : $Variant`r`nsource  : $commit`r`nbuilt   : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`n"
Set-Content -Path (Join-Path $appDir 'BUILD-INFO.txt') -Value $stamp -Encoding UTF8

$sizeMb = [math]::Round((Get-ChildItem $appDir -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB, 0)
Write-Host "bundle size: $sizeMb MB  ->  $appDir"

# ---------------------------------------------------------------------------
if (-not $NoZip) {
    Write-Step 'Creating archive'
    $zipName = "$AppName-$Variant-win64-$commit.zip"
    $zipPath = Join-Path $DistDir $zipName
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    # bsdtar handles >2 GB bundles far better than Compress-Archive
    $tar = Join-Path $env:SystemRoot 'System32\tar.exe'
    if (Test-Path $tar) {
        & $tar -a -c -f $zipPath -C $appDir .
        if ($LASTEXITCODE -ne 0) { throw 'tar archiving failed' }
    } else {
        Compress-Archive -Path (Join-Path $appDir '*') -DestinationPath $zipPath -CompressionLevel Optimal
    }
    $hash = (Get-FileHash $zipPath -Algorithm SHA256).Hash
    "$hash  $zipName" | Set-Content (Join-Path $DistDir 'SHA256SUMS.txt') -Encoding ASCII
    Write-Host "archive: $zipPath"
    Write-Host "sha256 : $hash"
}

Write-Step 'Done'
Write-Host "Output: $DistDir"
