$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$projectRoot = Split-Path $PSScriptRoot -Parent
$testRoot = Join-Path $projectRoot ".build/installer launcher's smoke"
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$probeExe = Join-Path $testRoot 'Probe.exe'
$compiler = Join-Path ([Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) 'csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) {
    $compiler = 'C:/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe'
}
& $compiler /nologo /target:exe "/out:$probeExe" (Join-Path $PSScriptRoot 'installer_launcher_probe.cs')
if ($LASTEXITCODE -ne 0) { throw 'Probe compilation failed' }
$blockedTemp = Join-Path $testRoot 'blocked-temp-file'
Set-Content -LiteralPath $blockedTemp -Value 'This file cannot be used as a temp directory.'
$launcher = Join-Path $projectRoot 'installer/Install-ScreenPlayer.ps1'
$parentTemp = $env:TEMP
$parentTmp = $env:TMP
foreach ($expectedExit in @(0, 7)) {
    $outputPath = Join-Path $testRoot "probe-$expectedExit.txt"
    # Exercise Windows argument quoting, spaces, apostrophes and trailing slashes.
    $arguments = @('plain', 'with spaces', 'with "quotes"', 'space trailing\')
    $quotePs = { param($value) "'" + $value.Replace("'", "''") + "'" }
    $command = '& ' + (& $quotePs $launcher) + ' -InstallerPath ' + (& $quotePs $probeExe) +
        ' -InstallerArguments @(' + (($arguments | ForEach-Object { & $quotePs $_ }) -join ',') + '); exit $LASTEXITCODE'
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = 'powershell.exe'
    $info.UseShellExecute = $false
    $info.Arguments = '-NoProfile -OutputFormat Text -ExecutionPolicy Bypass -EncodedCommand ' +
        [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $info.EnvironmentVariables['TEMP'] = $blockedTemp
    $info.EnvironmentVariables['TMP'] = $blockedTemp
    $info.EnvironmentVariables['SP_PROBE_OUTPUT'] = $outputPath
    $info.EnvironmentVariables['SP_PROBE_EXIT'] = [string]$expectedExit
    $child = [Diagnostics.Process]::Start($info)
    if (-not $child.WaitForExit(30000)) { throw 'Launcher test timed out' }
    if ($child.ExitCode -ne $expectedExit) { throw "Exit code was not preserved: $($child.ExitCode)" }
    $lines = [IO.File]::ReadAllLines($outputPath)
    if ($lines[0] -eq $blockedTemp -or $lines[0] -ne $lines[1]) { throw 'Child temp was not replaced' }
    if (-not $lines[0].StartsWith((Join-Path $testRoot '.screenplayer-install-temp'))) {
        throw 'Child temp is outside the selected installation folder'
    }
    for ($index = 0; $index -lt $arguments.Count; $index++) {
        if ($lines[$index + 2] -cne $arguments[$index]) { throw "Argument $index did not round-trip" }
    }
    if (-not $lines[$lines.Length - 1].StartsWith('/LOG=')) { throw 'Installer log argument missing' }
    if (Test-Path -LiteralPath $lines[0]) { throw 'Empty temp session was not cleaned up' }
    Write-Host "PASS invalid TEMP/TMP, writable child temp, quoted arguments, cleanup and exit $expectedExit"
    $child.Dispose()
}
if ($env:TEMP -ne $parentTemp -or $env:TMP -ne $parentTmp) { throw 'Parent environment changed' }
Write-Host 'PASS parent TEMP/TMP unchanged'

# Run the same CMD entry the user double-clicks, including its -File invocation.
$cmdPath = Join-Path $testRoot 'Install-ScreenPlayer.cmd'
$cmdText = [IO.File]::ReadAllText((Join-Path $projectRoot 'installer/Install-ScreenPlayer.cmd')).Replace('@APP_VERSION@', '0.0.0')
[IO.File]::WriteAllText($cmdPath, $cmdText, [Text.Encoding]::ASCII)
Copy-Item -LiteralPath $launcher -Destination (Join-Path $testRoot 'Install-ScreenPlayer.ps1') -Force
Copy-Item -LiteralPath $probeExe -Destination (Join-Path $testRoot 'ScreenPlayer-Setup-0.0.0.exe') -Force
$cmdOutput = Join-Path $testRoot 'cmd-probe.txt'
$cmdInfo = New-Object Diagnostics.ProcessStartInfo
$cmdInfo.FileName = 'cmd.exe'
$cmdInfo.UseShellExecute = $false
$cmdInfo.Arguments = '/d /c ""' + $cmdPath + '""'
$cmdInfo.EnvironmentVariables['TEMP'] = $blockedTemp
$cmdInfo.EnvironmentVariables['TMP'] = $blockedTemp
$cmdInfo.EnvironmentVariables['SP_PROBE_OUTPUT'] = $cmdOutput
$cmdInfo.EnvironmentVariables['SP_PROBE_EXIT'] = '0'
$cmdChild = [Diagnostics.Process]::Start($cmdInfo)
if (-not $cmdChild.WaitForExit(30000) -or $cmdChild.ExitCode -ne 0) { throw 'CMD entry failed' }
if (-not (Test-Path -LiteralPath $cmdOutput)) { throw 'CMD did not run installer' }
Write-Host 'PASS CMD entry starts installer with invalid inherited TEMP/TMP'
$cmdChild.Dispose()

# Exercise the actual Inno loader too, without installing files or registry keys.
$innoCompiler = Join-Path $projectRoot '.build/InnoSetup/ISCC.exe'
if (Test-Path -LiteralPath $innoCompiler) {
    $innoInfo = New-Object Diagnostics.ProcessStartInfo
    $innoInfo.FileName = $innoCompiler
    $innoInfo.UseShellExecute = $false
    $innoInfo.Arguments = '"/O' + $testRoot + '" "' + (Join-Path $PSScriptRoot 'installer_temp_probe.iss') + '"'
    $innoInfo.EnvironmentVariables['TEMP'] = $testRoot
    $innoInfo.EnvironmentVariables['TMP'] = $testRoot
    $compile = [Diagnostics.Process]::Start($innoInfo)
    if (-not $compile.WaitForExit(30000) -or $compile.ExitCode -ne 0) { throw 'Inno probe compilation failed' }
    $marker = Join-Path $testRoot 'inno-marker.txt'
    $innoSetup = Join-Path $testRoot 'TempProbeSetup.exe'
    $innoArgs = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', ('/ProbeMarker=' + $marker))
    $command = '& ' + (& $quotePs $launcher) + ' -InstallerPath ' + (& $quotePs $innoSetup) +
        ' -InstallerArguments @(' + (($innoArgs | ForEach-Object { & $quotePs $_ }) -join ',') + '); exit $LASTEXITCODE'
    $info.Arguments = '-NoProfile -OutputFormat Text -ExecutionPolicy Bypass -EncodedCommand ' +
        [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $child = [Diagnostics.Process]::Start($info)
    if (-not $child.WaitForExit(30000) -or $child.ExitCode -ne 0) { throw 'Real Inno temp probe failed' }
    $actualTemp = [IO.File]::ReadAllText($marker)
    if (-not $actualTemp.StartsWith((Join-Path $testRoot '.screenplayer-install-temp'))) {
        throw 'Inno loader did not use the replacement temp directory'
    }
    Write-Host 'PASS real Inno loader completes with invalid inherited TEMP/TMP'
    $child.Dispose()
    $compile.Dispose()
}
