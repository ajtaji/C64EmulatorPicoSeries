# Build a PureMetal source OUTSIDE the lease, then hold the board only to upload the ready image and
# capture its serial output until a line carrying -Until appears (or -Seconds pass: the hard timeout),
# and release in a finally (BOARDS.md, Ron 2026-10-25).
#
#   tools\board.ps1 -Source src\tests\lorenz1.picow -Output build\lorenz1.uf2 -Until LORENZ_RESULT -Seconds 480 [-Port COM7]
#   -NoUpload only compiles (and checks the image stays below $40000).
param(
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$Output,
    [int]$Seconds = 30,
    [string]$Until = 'NEVER-SEEN',
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
$chip = 'rp2040'; if ($src -match '\.pico2') { $chip = 'rp2350' }

$p = Start-Process -FilePath $pmf -ArgumentList ('--compile "' + $src + '" -S -o "' + $out + '"') -WorkingDirectory (Split-Path $pmf -Parent) -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput "$out.build.log" -RedirectStandardError "$out.stderr.log"
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
if ($NoUpload) { return }

# the capture: one expect with the hard timeout
$scr = "$out.capture.txt"
[IO.File]::WriteAllText($scr, "expect $Until $Seconds`n")
if ($Minutes -le 0) { $Minutes = [Math]::Ceiling(($Seconds + 60) / 60) }
. C:\PMFBuild\board-leases\lease.ps1
$l = Get-BoardLease -Port $Port -Owner 'c64' -Minutes $Minutes
$rc = 1
try {
    "lease $($l.Tag)"
    $p = Start-Process -FilePath $pmf -ArgumentList ('--radio-firmware "' + $out + '" -t ' + $chip + ' --port ' + $Port) -WorkingDirectory (Split-Path $pmf -Parent) -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput "$out.upload.log" -RedirectStandardError "$out.stderr.log"
    "upload rc=$($p.ExitCode)"
    if ($p.ExitCode -ne 0) { Get-Content "$out.upload.log" | Select-Object -Last 8; throw 'upload failed' }
    & py -3 (Join-Path $PSScriptRoot 'serial_script.py') --port $Port --script $scr --log "$out.board.log"
    $rc = $LASTEXITCODE
} finally {
    Release-BoardLease $l
    'released'
}
Get-Content "$out.board.log" | Where-Object { $_ -match 'LORENZ|RESULT|FAIL|STOP' } | Select-Object -Last 12
exit $rc
