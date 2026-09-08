param([int]$x, [int]$y)
$sig = '[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);'
$t = Add-Type -MemberDefinition $sig -Name U32C -Namespace W
[W.U32C]::SetCursorPos($x, $y) | Out-Null
Write-Output "moved to $x,$y"
