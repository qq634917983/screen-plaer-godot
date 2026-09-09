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
$mpvDlls = @('libgodot_mpv.windows.template_release.x86_64.dll',
    'libmpv-2.dll', 'libEGL.dll', 'libGLESv2.dll', 'zlib1.dll')
$missingMpv = @($mpvDlls | Where-Object { -not (Test-Path -LiteralPath "bin/$_" -PathType Leaf) })
if ($missingMpv.Count -and (Test-Path -LiteralPath 'bin/win-bin.zip' -PathType Leaf)) {
    & (Join-Path $PSScriptRoot 'restore_windows_mpv.ps1')
}
& "$PSScriptRoot/check_windows_runtime.ps1"
& $command.Source --headless --editor --path $PWD.Path --import --quit
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $command.Source --path $PWD.Path @GameArguments
exit $LASTEXITCODE
