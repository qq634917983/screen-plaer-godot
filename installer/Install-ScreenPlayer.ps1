param(
    [Parameter(Mandatory = $true)]
    [string]$InstallerPath,
    [string[]]$InstallerArguments = @()
)
$ErrorActionPreference = 'Stop'

# Inno's loader creates its temp directory before any [Code] can run. Give only
# the child process a tested temp directory; leave Windows settings unchanged.
function ConvertTo-WindowsArgument([string]$Value) {
    if ($Value -notmatch '[\s"]' -and $Value.Length) { return $Value }
    return '"' + [regex]::Replace(
        [regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1') + '"'
}

$sessionDirectory = $null
$logPath = $null
$result = 1
try {
    $setupPath = (Resolve-Path -LiteralPath $InstallerPath).Path
    if (-not (Test-Path -LiteralPath $setupPath -PathType Leaf)) {
        throw 'Installer file was not found.'
    }
    $candidates = @((Join-Path (Split-Path $setupPath -Parent) '.screenplayer-install-temp'))
    $localData = [Environment]::GetFolderPath('LocalApplicationData')
    if ($localData) { $candidates += Join-Path $localData 'ScreenPlayer/InstallTemp' }
    $failures = @()
    foreach ($candidate in $candidates) {
        $attempt = Join-Path $candidate ([Guid]::NewGuid().ToString('N'))
        try {
            [IO.Directory]::CreateDirectory($attempt) | Out-Null
            $probePath = Join-Path $attempt 'write-test'
            [IO.File]::WriteAllText($probePath, 'ScreenPlayer installer temp probe')
            [IO.File]::Delete($probePath)
            $sessionDirectory = [IO.Path]::GetFullPath($attempt)
            break
        } catch {
            $failures += $candidate + ': ' + $_.Exception.Message
        }
    }
    if (-not $sessionDirectory) {
        throw ('No writable installer temp directory. Move the installer and launcher to a writable folder.' +
            [Environment]::NewLine + ($failures -join [Environment]::NewLine))
    }
    $logPath = Join-Path (Split-Path $sessionDirectory -Parent) (
        'install-' + [IO.Path]::GetFileName($sessionDirectory) + '.log')
    $arguments = @($InstallerArguments)
    # Keep the generated log location predictable, even when callers pass /LOG.
    $arguments += '/LOG=' + $logPath
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $setupPath
    $startInfo.WorkingDirectory = Split-Path $setupPath -Parent
    $startInfo.UseShellExecute = $false
    $startInfo.Arguments = (($arguments | ForEach-Object { ConvertTo-WindowsArgument $_ }) -join ' ')
    $startInfo.EnvironmentVariables['TEMP'] = $sessionDirectory
    $startInfo.EnvironmentVariables['TMP'] = $sessionDirectory
    Write-Host "Installer temp: $sessionDirectory"
    Write-Host "Installer log:  $logPath"
    $process = [Diagnostics.Process]::Start($startInfo)
    $process.WaitForExit()
    $result = $process.ExitCode
    $process.Dispose()
    if ($result -ne 0) {
        Write-Host "Installation did not finish (exit $result). Log: $logPath"
    }
} catch {
    Write-Host ('Installation could not start: ' + $_.Exception.Message)
} finally {
    if ($sessionDirectory) {
        # Delete only our empty session directory. Never recursively delete an
        # installation directory or files left behind by a running child.
        try { [IO.Directory]::Delete($sessionDirectory, $false) } catch { }
    }
}
exit $result
