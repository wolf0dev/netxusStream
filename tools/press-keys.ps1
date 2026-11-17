# Envia teclas a la ventana de NexusStream (la activa primero).
# Uso: powershell -File press-keys.ps1 -Keys "{LEFT}"
param([Parameter(Mandatory = $true)][string]$Keys)
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class W {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@
$proc = Get-Process -Name nexusstream -ErrorAction Stop | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $proc) { throw 'NexusStream no esta en ejecucion' }
[W]::SetForegroundWindow($proc.MainWindowHandle) | Out-Null
Start-Sleep -Milliseconds 400
$shell = New-Object -ComObject WScript.Shell
$shell.SendKeys($Keys)
Write-Output "OK $Keys"
