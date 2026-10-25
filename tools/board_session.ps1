# Build outside the lease; then, holding the board only for the board steps: write the C64 flash store
# (optional), upload the ready image, run a serial script against it (tools/serial_script.py, whose
# expects carry their own timeouts), optionally put a silent image back - and release in a finally.
# (BOARDS.md, Ron 2026-10-25: compile and analyse OUTSIDE the lease; -Minutes = the board steps' real length.)
#   tools\board_session.ps1 -Source src\c64.picow -Script tests\board\boot.txt -Log docs\board-boot.log [-Store build\c64-store.bin] [-Minutes 5] [-Port COM7]
param(
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$Script,
    [Parameter(Mandatory)][string]$Log,
    [string]$Store = '',
    # put back after the script, under the same lease: a silent program after a sound test
    [string]$After = '',
    [string]$Port = 'COM7',
    [int]$Minutes = 5
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$pmf = 'C:\Users\ajtaj\Desktop\Github\PureBasicCode\OpenGl Work\ArduinoBasic\PureMetalForge.exe'
function Resolve-Any([string]$p) { if ([IO.Path]::IsPathRooted($p)) { return [IO.Path]::GetFullPath($p) } return [IO.Path]::GetFullPath((Join-Path $root $p)) }
function Pmf([string]$argline, [string]$logfile) {
    $p = Start-Process -FilePath $pmf -ArgumentList $argline -WorkingDirectory (Split-Path $pmf -Parent) -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $logfile -RedirectStandardError "$logfile.err"
    return $p.ExitCode
}
$src = Resolve-Any $Source; $scr = Resolve-Any $Script; $logf = Resolve-Any $Log
[IO.Directory]::CreateDirectory((Join-Path $root 'build')) | Out-Null
$chip = 'rp2040'; if ($src -match '\.pico2') { $chip = 'rp2350' }

# 1. outside the lease: the images
$out = Join-Path $root ('build\' + [IO.Path]::GetFileNameWithoutExtension($src) + '-session.uf2')
if ((Pmf ('--compile "' + $src + '" -S -o "' + $out + '"') "$out.build.log") -ne 0) { throw "compile failed: $out.build.log" }
$ao = ''
if ($After) {
    $ao = Join-Path $root 'build\after-silent.uf2'
    if ((Pmf ('--compile "' + (Resolve-Any $After) + '" -S -o "' + $ao + '"') "$ao.build.log") -ne 0) { throw "compile failed: $ao.build.log" }
}

# 2. the board steps, under the lease
. C:\PMFBuild\board-leases\lease.ps1
$l = Get-BoardLease -Port $Port -Owner 'c64' -Minutes $Minutes
$rc = 1
try {
    "lease $($l.Tag)"
    if ($Store) {
        $st = Resolve-Any $Store
        $w = Pmf ('--storage-write "' + $st + '" --offset $1F0000 -t ' + $chip + ' --port ' + $Port) "$st.write.log"
        "store write rc=$w"
        if ($w -ne 0) { Get-Content "$st.write.log" | Where-Object { $_ -notmatch '^\[DEBUG\]|TELEMETRY' } | Select-Object -Last 6; throw 'store write failed' }
    }
    $u = Pmf ('--radio-firmware "' + $out + '" -t ' + $chip + ' --port ' + $Port) "$out.board.log"
    "upload rc=$u"
    if ($u -ne 0) { Get-Content "$out.board.log" | Where-Object { $_ -notmatch '^\[DEBUG\]|TELEMETRY' } | Select-Object -Last 8; throw 'upload failed' }
    & py -3 (Join-Path $PSScriptRoot 'serial_script.py') --port $Port --script $scr --log $logf
    $rc = $LASTEXITCODE
    if ($ao) {
        "silent program back rc=$(Pmf ('--radio-firmware "' + $ao + '" -t ' + $chip + ' --port ' + $Port) "$ao.board.log")"
    }
} finally {
    Release-BoardLease $l
    'released'
}
exit $rc
