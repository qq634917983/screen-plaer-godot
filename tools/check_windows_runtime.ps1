$ErrorActionPreference = 'Stop'
if (-not [Environment]::Is64BitProcess) { throw 'Run this check in x64 PowerShell.' }
$projectRoot = Split-Path $PSScriptRoot -Parent
$manifest = Get-Content "$PSScriptRoot/windows-runtime.lock.json" -Raw | ConvertFrom-Json
$issues = @()
foreach ($file in $manifest.files) {
    $path = Join-Path $projectRoot $file.path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $issues += "Missing: $($file.path)"; continue }
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $file.sha256) { $issues += "SHA-256 mismatch: $($file.path)" }
}
if ($issues.Count) {
    throw (($issues -join "`n") + "`nRun tools/install_windows_runtime.ps1 -SourceRoot <runtime directory>. See doc/PLATFORMS.md.")
}
if (-not ('ScreenPlayer.NativeLoader' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
namespace ScreenPlayer {
    public static class NativeLoader {
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        public static extern IntPtr LoadLibraryEx(string path, IntPtr file, uint flags);
        [DllImport("kernel32.dll")]
        public static extern bool FreeLibrary(IntPtr module);
    }
}
'@
}
foreach ($relative in @('bin/libgodot_mpv.windows.template_release.x86_64.dll', 'cef_artifacts/windows/libgdcef.dll')) {
    # Search only the DLL directory and system directories, never a global PATH workaround.
    $handle = [ScreenPlayer.NativeLoader]::LoadLibraryEx((Join-Path $projectRoot $relative), [IntPtr]::Zero, 0x1100)
    if ($handle -eq [IntPtr]::Zero) {
        $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "Cannot load $relative (Windows error $code). Check x64 architecture and Microsoft VC++ x64 runtime."
    }
    [ScreenPlayer.NativeLoader]::FreeLibrary($handle) | Out-Null
    Write-Host "PASS native load: $relative"
}
Write-Host "PASS Windows runtime $($manifest.version): all file hashes match."
