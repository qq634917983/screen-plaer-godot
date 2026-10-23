param(
    [string]$Godot = $env:GODOT_BIN,
    [string]$TemplateArchive = $env:GODOT_EXPORT_TEMPLATES,
    [string]$OutputDirectory = 'dist/ScreenPlayer-Windows-x86_64',
    [string]$VCRuntimeDirectory
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Set-Location $projectRoot
if (-not $Godot) { $Godot = 'godot' }
$godotCommand = Get-Command $Godot -ErrorAction SilentlyContinue
if (-not $godotCommand) { throw 'Set GODOT_BIN or pass -Godot with Godot 4.7.2 x86_64.' }

& "$PSScriptRoot/check_windows_runtime.ps1"

$templateRoot = Join-Path $projectRoot '.build/export_templates'
$templatePath = Join-Path $templateRoot 'templates/windows_release_x86_64.exe'
if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
    if (-not $TemplateArchive) {
        $localArchive = 'D:/Download/Godot_v4.7.2-stable_export_templates.tpz'
        if (Test-Path -LiteralPath $localArchive) { $TemplateArchive = $localArchive }
    }
    if (-not $TemplateArchive -or -not (Test-Path -LiteralPath $TemplateArchive -PathType Leaf)) {
        throw 'Pass -TemplateArchive with the Godot 4.7.2 export_templates.tpz file.'
    }
    New-Item -ItemType Directory -Path $templateRoot -Force | Out-Null
    # bsdtar只解出所需模板，避免 PowerShell ZipArchive 映射 1GB+ tpz 时崩溃。
    & tar -xf (Resolve-Path -LiteralPath $TemplateArchive) -C $templateRoot templates/windows_release_x86_64.exe
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
        throw 'Failed to extract the Windows x86_64 release template.'
    }
}

$outputPath = [IO.Path]::GetFullPath((Join-Path $projectRoot $OutputDirectory))
$distRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot 'dist'))
if (-not $outputPath.StartsWith($distRoot + [IO.Path]::DirectorySeparatorChar)) {
    throw "OutputDirectory must be inside $distRoot"
}
if (Test-Path -LiteralPath $outputPath) { Remove-Item -LiteralPath $outputPath -Recurse -Force }
New-Item -ItemType Directory -Path $outputPath -Force | Out-Null

& $godotCommand.Source --headless --editor --path $projectRoot --import --quit
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$exePath = Join-Path $outputPath 'ScreenPlayer.exe'
& $godotCommand.Source --headless --path $projectRoot --export-release 'Windows Desktop' $exePath
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# CEF 的 helper、pak、locales 必须是 exe 旁的真实文件，不能只放进嵌入式 PCK。
$manifest = Get-Content "$PSScriptRoot/windows-runtime.lock.json" -Raw | ConvertFrom-Json
foreach ($file in $manifest.files) {
    $prefix = 'cef_artifacts/windows/'
    if (-not $file.path.StartsWith($prefix)) { continue }
    $relative = $file.path.Substring($prefix.Length)
    if ($relative.StartsWith('locales/') -and $relative -notin @('locales/en-US.pak', 'locales/zh-CN.pak')) {
        continue
    }
    $target = Join-Path $outputPath $relative
    New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectRoot $file.path) -Destination $target -Force
}

# MPV 与 CEF 各自携带不同版本的 ANGLE，但 DLL 原名相同。Godot 导出会把两套
# 原生库放到 exe 目录；这里给 MPV 的导入项改成独立名称，防止 CEF 版本覆盖它。
function Copy-WithImportRename([string]$Source, [string]$Target, [hashtable]$Renames) {
    $bytes = [IO.File]::ReadAllBytes($Source)
    foreach ($oldName in $Renames.Keys) {
        $oldBytes = [Text.Encoding]::ASCII.GetBytes($oldName)
        $newBytes = [Text.Encoding]::ASCII.GetBytes([string]$Renames[$oldName])
        if ($newBytes.Length -gt $oldBytes.Length) { throw "Import rename is too long: $oldName" }
        $matches = 0
        for ($i = 0; $i -le $bytes.Length - $oldBytes.Length; $i++) {
            $same = $true
            for ($j = 0; $j -lt $oldBytes.Length; $j++) {
                if ($bytes[$i + $j] -ne $oldBytes[$j]) { $same = $false; break }
            }
            if (-not $same) { continue }
            for ($j = 0; $j -lt $oldBytes.Length; $j++) { $bytes[$i + $j] = 0 }
            for ($j = 0; $j -lt $newBytes.Length; $j++) { $bytes[$i + $j] = $newBytes[$j] }
            $matches++
            $i += $oldBytes.Length - 1
        }
        if ($matches -ne 1) { throw "Expected one '$oldName' import in $Source, found $matches." }
    }
    [IO.File]::WriteAllBytes($Target, $bytes)
}
Copy-WithImportRename (Join-Path $projectRoot 'bin/libgodot_mpv.windows.template_release.x86_64.dll') `
    (Join-Path $outputPath 'libgodot_mpv.windows.template_release.x86_64.dll') `
    @{ 'libEGL.dll' = 'mpvEGL.dll' }
Copy-WithImportRename (Join-Path $projectRoot 'bin/libEGL.dll') `
    (Join-Path $outputPath 'mpvEGL.dll') @{ 'libGLESv2.dll' = 'mpvGLES2.dll' }
Copy-Item -LiteralPath (Join-Path $projectRoot 'bin/libGLESv2.dll') `
    -Destination (Join-Path $outputPath 'mpvGLES2.dll') -Force

# 使用 Visual Studio 官方 Redist 目录做 app-local 部署，新机器无需另装 VC++ 运行库。
if (-not $VCRuntimeDirectory) {
    # Visual Studio Build Tools 常安装在 Program Files (x86)，两处都要查找。
    $redistRoots = @('C:/Program Files/Microsoft Visual Studio',
        'C:/Program Files (x86)/Microsoft Visual Studio')
    $redistCandidates = @($redistRoots | Where-Object { Test-Path -LiteralPath $_ } | ForEach-Object {
        Get-ChildItem -LiteralPath $_ -Directory -Filter 'Microsoft.VC*.CRT' -Recurse -ErrorAction SilentlyContinue
    } | Where-Object { $_.FullName -match '\\x64\\Microsoft\.VC[^\\]+\.CRT$' } |
        Sort-Object FullName -Descending)
    if ($redistCandidates.Count) { $VCRuntimeDirectory = $redistCandidates[0].FullName }
}
if (-not $VCRuntimeDirectory -or -not (Test-Path -LiteralPath $VCRuntimeDirectory -PathType Container)) {
    throw 'Microsoft VC++ x64 Redist directory not found. Pass -VCRuntimeDirectory from Visual Studio VC/Redist.'
}
Get-ChildItem -LiteralPath $VCRuntimeDirectory -Filter '*.dll' -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $outputPath -Force
}

$required = @('ScreenPlayer.exe', 'libgodot_mpv.windows.template_release.x86_64.dll',
    'libmpv-2.dll', 'mpvEGL.dll', 'mpvGLES2.dll', 'zlib1.dll',
    'libEGL.dll', 'libGLESv2.dll', 'libgdcef.dll', 'libcef.dll',
    'gdCefRenderProcess.exe', 'icudtl.dat', 'resources.pak', 'locales/zh-CN.pak',
    'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')
$missing = @($required | Where-Object { -not (Test-Path -LiteralPath (Join-Path $outputPath $_) -PathType Leaf) })
if ($missing.Count) { throw "Release is missing files:`n$($missing -join "`n")" }

# 在生成 ZIP 前从发行目录实际加载两套扩展，捕获缺少间接依赖、架构错误和
# ANGLE 同名覆盖等“文件存在但 Error 126”的问题。
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ScreenPlayerReleaseNativeCheck {
    [DllImport("kernel32", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern IntPtr LoadLibraryEx(string path, IntPtr file, uint flags);
    [DllImport("kernel32", SetLastError = true)]
    public static extern bool FreeLibrary(IntPtr module);
}
'@
foreach ($nativeName in @('libgodot_mpv.windows.template_release.x86_64.dll', 'libgdcef.dll')) {
    $nativePath = Join-Path $outputPath $nativeName
    # LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS
    $handle = [ScreenPlayerReleaseNativeCheck]::LoadLibraryEx($nativePath, [IntPtr]::Zero, 0x1100)
    if ($handle -eq [IntPtr]::Zero) {
        $win32Error = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "Release native load failed: $nativeName (Win32 error $win32Error)"
    }
    [ScreenPlayerReleaseNativeCheck]::FreeLibrary($handle) | Out-Null
    Write-Host "PASS release native load: $nativeName"
}

$zipPath = "$outputPath.zip"
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
& tar -a -cf $zipPath -C (Split-Path $outputPath -Parent) (Split-Path $outputPath -Leaf)
if ($LASTEXITCODE -ne 0) { throw 'Failed to create the release ZIP archive.' }
Get-FileHash -LiteralPath $zipPath -Algorithm SHA256
Write-Host "Release directory: $outputPath"
Write-Host "Release archive:   $zipPath"
