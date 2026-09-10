param(
    [string]$Godot = $env:GODOT_BIN,
    [string]$TemplateArchive = $env:GODOT_EXPORT_TEMPLATES,
    [string]$OutputDirectory = 'dist/ScreenPlayer-Windows-x86_64'
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

$required = @('ScreenPlayer.exe', 'libgodot_mpv.windows.template_release.x86_64.dll',
    'libmpv-2.dll', 'libEGL.dll', 'libGLESv2.dll', 'zlib1.dll', 'libgdcef.dll',
    'libcef.dll', 'gdCefRenderProcess.exe', 'icudtl.dat', 'resources.pak', 'locales/zh-CN.pak')
$missing = @($required | Where-Object { -not (Test-Path -LiteralPath (Join-Path $outputPath $_) -PathType Leaf) })
if ($missing.Count) { throw "Release is missing files:`n$($missing -join "`n")" }

$zipPath = "$outputPath.zip"
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
& tar -a -cf $zipPath -C (Split-Path $outputPath -Parent) (Split-Path $outputPath -Leaf)
if ($LASTEXITCODE -ne 0) { throw 'Failed to create the release ZIP archive.' }
Get-FileHash -LiteralPath $zipPath -Algorithm SHA256
Write-Host "Release directory: $outputPath"
Write-Host "Release archive:   $zipPath"
