param([int]$x1, [int]$y1, [int]$x2, [int]$y2, [switch]$hold, [switch]$uponly)
$sig = @'
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, System.UIntPtr extra);
'@
$t = Add-Type -MemberDefinition $sig -Name U32D -Namespace W
if ($uponly) {
    [W.U32D]::mouse_event(4, 0, 0, 0, [System.UIntPtr]::Zero)   # LEFTUP
    Write-Output "up"
    exit
}
[W.U32D]::SetCursorPos($x1, $y1) | Out-Null
Start-Sleep -Milliseconds 150
[W.U32D]::mouse_event(2, 0, 0, 0, [System.UIntPtr]::Zero)   # LEFTDOWN
Start-Sleep -Milliseconds 100
$steps = 20
for ($i = 1; $i -le $steps; $i++) {
    $cx = $x1 + ($x2 - $x1) * $i / $steps
    $cy = $y1 + ($y2 - $y1) * $i / $steps
    [W.U32D]::SetCursorPos([int]$cx, [int]$cy) | Out-Null
    Start-Sleep -Milliseconds 25
}
if ($hold) {
    Write-Output "holding at $x2,$y2"
    exit
}
Start-Sleep -Milliseconds 100
[W.U32D]::mouse_event(4, 0, 0, 0, [System.UIntPtr]::Zero)   # LEFTUP
Write-Output "dragged $x1,$y1 -> $x2,$y2"
