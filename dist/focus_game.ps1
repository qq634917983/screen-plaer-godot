$sig = '[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool SetForegroundWindow(System.IntPtr h);[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr h, int n);'
$t = Add-Type -MemberDefinition $sig -Name U32F -Namespace W
$p = Get-Process | Where-Object { $_.MainWindowTitle -like '*ScreenPlayer*' } | Select-Object -First 1
if ($p) {
    [W.U32F]::ShowWindow($p.MainWindowHandle, 9) | Out-Null
    [W.U32F]::SetForegroundWindow($p.MainWindowHandle) | Out-Null
    Write-Output ('focused: ' + $p.MainWindowTitle)
} else {
    Write-Output 'notfound'
}
