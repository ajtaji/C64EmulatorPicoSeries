# Write the C64's flash store (tools/c64_store.py's output) to the Pico W at $1F0000, holding the
# board's lease (C:\PMFBuild\board-leases\lease.ps1) only for the write.
#   tools\store_write.ps1 -Store build\c64-store.bin [-Port COM7]
param([Parameter(Mandatory)][string]$Store, [string]$Port = 'COM7', [string]$Offset = '$1F0000')
$ErrorActionPreference = 'Stop'
$pmf = 'C:\Users\ajtaj\Desktop\Github\PureBasicCode\OpenGl Work\ArduinoBasic\PureMetalForge.exe'
$file = [IO.Path]::GetFullPath($Store)
if ((Get-Item $file).Length -gt 0xF000) { throw 'the store is bigger than the C64 region (60 KB)' }
. C:\PMFBuild\board-leases\lease.ps1
$l = Get-BoardLease -Port $Port -Owner 'c64' -Minutes 3
try {
    "lease $($l.Tag)"
    $a = '--storage-write "' + $file + '" --offset ' + $Offset + ' --port ' + $Port
    $p = Start-Process -FilePath $pmf -ArgumentList $a -WorkingDirectory (Split-Path $pmf -Parent) -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput "$file.write.log" -RedirectStandardError "$file.write.err"
} finally {
    Release-BoardLease $l
    'released'
}
Get-Content "$file.write.log" | Where-Object { $_ -notmatch '^\[DEBUG\]|TELEMETRY' }
exit $p.ExitCode
