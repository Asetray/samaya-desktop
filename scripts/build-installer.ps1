[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$QtRoot,
    [Parameter(Mandatory = $true)][string]$MakeNsis,
    [string]$NsisRoot,
    [string]$BuildTools
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$qt = (Resolve-Path $QtRoot).Path
$nsis = (Resolve-Path $MakeNsis).Path
if ($NsisRoot) { $env:NSISDIR = (Resolve-Path $NsisRoot).Path }

function Invoke-Checked([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Command failed: $Program (exit $LASTEXITCODE)" }
}

if (!$BuildTools) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    $BuildTools = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
}
if (!$BuildTools) { throw 'Visual Studio Build Tools with the x64 C++ tools are required.' }
$vcvars = Join-Path $BuildTools 'VC/Auxiliary/Build/vcvars64.bat'
$setup = [Diagnostics.ProcessStartInfo]::new($env:ComSpec, ('/d /s /c ""' + $vcvars + '" >nul && set"'))
$setup.UseShellExecute = $false
$setup.RedirectStandardOutput = $true
$setup.CreateNoWindow = $true
$dev = [Diagnostics.Process]::Start($setup)
$environment = $dev.StandardOutput.ReadToEnd()
$dev.WaitForExit()
if ($dev.ExitCode -ne 0) { throw 'Could not load the Visual C++ build environment.' }
foreach ($line in ($environment -split "`r?`n")) {
    if ($line -match '^([^=]+)=(.*)$') {
        [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'Process')
    }
}
$env:Path = (Join-Path $qt 'bin') + ';' + $env:Path
$vsCmake = Join-Path $BuildTools 'Common7/IDE/CommonExtensions/Microsoft/CMake'
$cmake = Join-Path $vsCmake 'CMake/bin/cmake.exe'
if (!(Test-Path -LiteralPath $cmake)) { $cmake = (Get-Command cmake.exe).Source }

$build = Join-Path $root 'build/nmake'
Invoke-Checked $cmake @('-S', $root, '-B', $build, '-G', 'NMake Makefiles', '-DCMAKE_BUILD_TYPE=Release',
    '-DCMAKE_TRY_COMPILE_CONFIGURATION=Release', "-DCMAKE_PREFIX_PATH=$qt")
Invoke-Checked $cmake @('--build', $build)

$stage = Join-Path $build ('stage-' + [Guid]::NewGuid().ToString('N'))
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force -Path $stage, $dist | Out-Null
Invoke-Checked $cmake @('--install', $build, '--prefix', $stage)
Invoke-Checked (Join-Path $qt 'bin/windeployqt.exe') @(
    '--qmldir', (Join-Path $root 'qml'), '--release', '--no-translations', '--no-compiler-runtime', '--no-opengl-sw', '--no-system-dxc-compiler',
    '--skip-plugin-types', 'generic,networkinformation,styles',
    '--include-plugins', 'qsvgicon,qsvg',
    (Join-Path $stage 'samaya-desktop.exe')
)

$crt = Get-ChildItem -LiteralPath (Join-Path $env:VCToolsRedistDir 'x64') -Directory -Filter 'Microsoft.VC*.CRT' | Select-Object -First 1
if (!$crt) { throw 'The app-local x64 Visual C++ redistributable files are missing.' }
Copy-Item -Path (Join-Path $crt.FullName '*.dll') -Destination $stage
$critical = @('Qt6Core.dll', 'Qt6Gui.dll', 'Qt6Widgets.dll', 'Qt6Svg.dll', 'Qt6Quick.dll', 'Qt6Qml.dll',
    'platforms/qwindows.dll', 'vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll')
foreach ($file in $critical) {
    if (!(Test-Path -LiteralPath (Join-Path $stage $file) -PathType Leaf)) { throw "Deployment file missing: $file" }
}
Copy-Item -LiteralPath (Join-Path $root 'licenses') -Destination $stage -Recurse
$sbom = Join-Path $qt 'sbom'
if (Test-Path -LiteralPath $sbom) { Copy-Item -LiteralPath $sbom -Destination $stage -Recurse }

# List only deployed files so the uninstaller can also work in a custom directory.
$uninstall = [Collections.Generic.List[string]]::new()
Get-ChildItem -LiteralPath $stage -Recurse -File | ForEach-Object {
    $relative = $_.FullName.Substring($stage.Length + 1)
    $uninstall.Add(('Delete "$INSTDIR\{0}"' -f $relative))
}
Get-ChildItem -LiteralPath $stage -Recurse -Directory | Sort-Object { $_.FullName.Length } -Descending | ForEach-Object {
    $relative = $_.FullName.Substring($stage.Length + 1)
    $uninstall.Add(('RMDir "$INSTDIR\{0}"' -f $relative))
}
$files = Join-Path $build 'uninstall-files.nsh'
[IO.File]::WriteAllLines($files, $uninstall, [Text.UTF8Encoding]::new($true))
$installer = Join-Path $dist 'samaya-desktop-0.3.6-win-x64-setup.exe'
$tmpInstaller = Join-Path $build ('samaya-' + [Guid]::NewGuid().ToString('N') + '-setup.exe')
Invoke-Checked $nsis @('/WX', "/DSTAGE=$stage", "/DOUTPUT=$tmpInstaller", "/DUNINSTALL_FILES=$files", (Join-Path $root 'packaging/samaya-desktop.nsi'))

$archive = Join-Path $dist 'samaya-desktop-0.3.6-win-x64-portable.zip'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$tmpZip = Join-Path $build ('portable-' + [Guid]::NewGuid().ToString('N') + '.zip')
[IO.Compression.ZipFile]::CreateFromDirectory($stage, $tmpZip)
Move-Item -LiteralPath $tmpInstaller -Destination $installer -Force
Move-Item -LiteralPath $tmpZip -Destination $archive -Force
$hashes = Get-FileHash -LiteralPath $installer, $archive -Algorithm SHA256
$rows = foreach ($item in $hashes) { $item.Hash.ToLowerInvariant() + '  ' + [IO.Path]::GetFileName($item.Path) }
[IO.File]::WriteAllLines((Join-Path $dist 'samaya-desktop-0.3.6-SHA256SUMS.txt'), $rows, [Text.Encoding]::ASCII)
$hashes
