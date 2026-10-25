# Under one board lease: optionally write the C64 flash store, upload a firmware, then run a serial
# script against it (tools/serial_script.py). THE LEASE COMES FIRST: nothing - not even the compile -
# runs until it is held, and it is released in a finally (2026-10-25: a compile before the lease had
# COM7 open while another worker held it).
#   tools\board_session.ps1 -Source src\c64.picow -Script tests\board\boot.txt -Log docs\board-boot.log [-Store build\c64-store.bin] [-Minutes 6] [-Port COM7]
param(
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$Script,
    [Parameter(Mandatory)][string]$Log,
    [string]$Store = '',
    # flashed after the script, under the same lease: a silent program after a sound test
    [string]$After = '',
    [string]$Port = 'COM7',
    [int]$Minutes = 6
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$pmf = 'C:\Users\ajtaj\Desktop\Github\PureBasicCode\OpenGl Work\ArduinoBasic\PureMetalForge.exe'
function Resolve-Any([string]$p) { if ([IO.Path]::IsPathRooted($p)) { return [IO.Path]::GetFullPath($p) } return [IO.Path]::GetFullPath((Join-Path $root $p)) }
$src = Resolve-Any $Source; $scr = Resolve-Any $Script; $logf = Resolve-Any $Log
$out = Join-Path $root ('build\' + [IO.Path]::GetFileNameWithoutExtension($src) + '-session.uf2')
[IO.Directory]::CreateDirectory((Join-Path $root 'build')) | Out-Null
. C:\PMFBuild\board-leases\lease.ps1
$l = Get-BoardLease -Port $Port -Owner 'c64' -Minutes ($Minutes + 2)
$rc = 1
try {
    "lease $($l.Tag)"
    $p = Start-Process -FilePath $pmf -ArgumentList ('--compile "' + $src + '" -S -o "' + $out + '"') -WorkingDirectory (Split-Path $pmf -Parent) -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput "$out.build.log" -RedirectStandardError "$out.stderr.log"
    if ($p.ExitCode -ne 0) { throw "compile failed: $out.build.log" }
    if ($Store) {
        $st = Resolve-Any $Store
        $chip = 'rp2040'; if ($src -match '\.pico2') { $chip = 'rp2350' }
        $p = Start-Process -FilePath $pmf -ArgumentList ('--storage-write "' + $st + '" --offset $1F0000 -t ' + $chip + ' --port ' + $Port) -WorkingDirectory (Split-Path $pmf -Parent) -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput "$st.write.log" -RedirectStandardError "$st.write.err"
        "store write rc=$($p.ExitCode)"
        Get-Content "$st.write.log" | Where-Object { $_ -notmatch '^\[DEBUG\]|TELEMETRY' } | Select-Object -Last 6
        if ($p.ExitCode -ne 0) { throw 'store write failed' }
    }
    $p = Start-Process -FilePath $pmf -ArgumentList ('--compile "' + $src + '" -S -o "' + $out + '" --port ' + $Port) -WorkingDirectory (Split-Path $pmf -Parent) -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput "$out.board.log" -RedirectStandardError "$out.stderr.log"
    "upload rc=$($p.ExitCode)"
    if ($p.ExitCode -ne 0) { Get-Content "$out.board.log" | Select-Object -Last 8; throw 'upload failed' }
    & py -3 (Join-Path $PSScriptRoot 'serial_script.py') --port $Port --script $scr --log $logf
    $rc = $LASTEXITCODE
    if ($After) {
        $af = Resolve-Any $After
        $ao = Join-Path $root 'build/after-silent.uf2'
        $p = Start-Process -FilePath $pmf -ArgumentList ('--compile "' + $af + '" -S -o "' + $ao + '" --port ' + $Port) -WorkingDirectory (Split-Path $pmf -Parent) -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput "$ao.board.log" -RedirectStandardError "$ao.stderr.log"
        "silent program back rc=$($p.ExitCode)"
    }
} finally {
    Release-BoardLease $l
    'released'
}
exit $rc
