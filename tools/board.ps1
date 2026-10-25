# Build a PureMetal source, then upload it to a shared board and capture its serial output, holding
# the board through C:\PMFBuild\board-leases\lease.ps1 (the one way to take a board on this PC).
# THE LEASE COMES FIRST: nothing - not even the compile - runs until it is held, and it is released in
# a finally (2026-10-25: a compile before the lease had COM7 open while another worker held it).
#
#   tools\board.ps1 -Source src\tests\lorenz1.picow -Output build\lorenz1.uf2 -Seconds 300 [-Port COM7] [-Minutes 8]
#   -NoUpload only compiles (and checks the image stays below $40000); it takes no lease.
param(
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$Output,
    [int]$Seconds = 30,
    [string]$Port = 'COM7',
    [int]$Minutes = 0,
    [switch]$NoUpload
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$pmf = 'C:\Users\ajtaj\Desktop\Github\PureBasicCode\OpenGl Work\ArduinoBasic\PureMetalForge.exe'
function Resolve-Any([string]$p) { if ([IO.Path]::IsPathRooted($p)) { return [IO.Path]::GetFullPath($p) } return [IO.Path]::GetFullPath((Join-Path $root $p)) }
$src = Resolve-Any $Source
$out = Resolve-Any $Output
[IO.Directory]::CreateDirectory((Split-Path $out -Parent)) | Out-Null

function Build {
    $args1 = '--compile "' + $src + '" -S -o "' + $out + '"'
    $p = Start-Process -FilePath $pmf -ArgumentList $args1 -WorkingDirectory (Split-Path $pmf -Parent) -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput "$out.build.log" -RedirectStandardError "$out.stderr.log"
    if ($p.ExitCode -ne 0) {
        Get-Content "$out.build.log" | Select-String -Pattern 'error|PM\d{4}' | Select-Object -First 12 | ForEach-Object { $_.Line }
        throw "compile failed ($($p.ExitCode)): $out.build.log"
    }
    Get-Content "$out.build.log" | Select-String -Pattern 'ROM_TOTAL|bytes of code run from SRAM' | ForEach-Object { $_.Line }
    # The image must end below $40000 (the Ms. Pac-Man pack, then the NES store at $50000).
    $uf2 = [IO.File]::ReadAllBytes($out); $end = 0
    for ($o = 0; $o -lt $uf2.Length; $o += 512) {
        $e = [BitConverter]::ToUInt32($uf2, $o + 12) + [BitConverter]::ToUInt32($uf2, $o + 16)
        if ($e -gt $end) { $end = $e }
    }
    if ($end -gt 0x10040000) { throw ('image reaches 0x{0:X8}, past 0x10040000: not uploaded' -f $end) }
    'image ends at 0x{0:X8}' -f $end
}

if ($NoUpload) { Build; return }
if ($Minutes -le 0) { $Minutes = [Math]::Ceiling(($Seconds + 150) / 60) }
. C:\PMFBuild\board-leases\lease.ps1
$l = Get-BoardLease -Port $Port -Owner 'c64' -Minutes $Minutes
$rc = 1
try {
    "lease $($l.Tag)"
    Build
    $args2 = '--compile "' + $src + '" -S -o "' + $out + '" --port ' + $Port + ' --seconds ' + $Seconds
    $p = Start-Process -FilePath $pmf -ArgumentList $args2 -WorkingDirectory (Split-Path $pmf -Parent) -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput "$out.board.log" -RedirectStandardError "$out.stderr.log"
    $rc = $p.ExitCode
} finally {
    Release-BoardLease $l
    if ([IO.File]::Exists($l.Path)) {
        $t = $null; try { $t = [IO.File]::ReadAllText($l.Path) } catch {}
        if ($t -eq $l.Tag) { Write-Warning 'OUR LEASE IS STILL THERE' }
    }
    'released'
}
Get-Content "$out.board.log" | Where-Object { $_ -notmatch '^\[DEBUG\]|^> |TELEMETRY|_RP2040\||_RP2350\||^pmfc:' }
exit $rc
