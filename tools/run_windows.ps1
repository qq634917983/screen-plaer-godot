param(
    [string]$Godot = $env:GODOT_BIN,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$GameArguments
)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$architecture = [Environment]::GetEnvironmentVariable('PROCESSOR_ARCHITECTURE', 'Machine')
if ($architecture -ne 'AMD64') {
    throw 'This launcher requires x86_64 Windows.'
}
if (-not $Godot) { $Godot = 'godot' }
$command = Get-Command $Godot -ErrorAction SilentlyContinue
if (-not $command) {
    throw 'Set GODOT_BIN or pass -Godot with the path to Godot 4.7.2 x86_64.'
}
$required = @(
    'bin/godot_mpv.gdextension',
    'bin/libgodot_mpv.windows.template_release.x86_64.dll',
    'bin/libmpv-2.dll', 'bin/libEGL.dll', 'bin/libGLESv2.dll', 'bin/zlib1.dll',
    'cef_artifacts/gdcef.gdextension',
    'cef_artifacts/windows/libgdcef.dll',
    'cef_artifacts/windows/libcef.dll',
    'cef_artifacts/windows/gdCefRenderProcess.exe',
    'cef_artifacts/windows/icudtl.dat'
)
$missing = @($required | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
if ($missing.Count) {
    throw ("Missing native runtime files:`n" + ($missing -join "`n") +
        "`nRestore the complete Windows runtime from the working Windows project; see doc/PLATFORMS.md.")
}
& $command.Source --headless --editor --path $PWD.Path --import --quit
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $command.Source --path $PWD.Path @GameArguments
exit $LASTEXITCODE
