# Import-Image.ps1 - builds a containerlab image from your own Cisco IOL / IOL-L2 file.
# Drag the image file onto Import-Image.cmd, or run it from the NetLab menu.
# The file is read from where it is; a backup copy goes to <dataDir>\images.
param(
    [string]$Path = '',
    [switch]$NoPause
)

. "$PSScriptRoot\NetLab.Common.ps1"
$s = Get-NetLabSettings
$script:DistroName = $s.wsl.distroName

function Done([int]$Code) {
    if (-not $NoPause) { Read-Host 'Press Enter to close' | Out-Null }
    exit $Code
}

if (-not (Test-Distro $script:DistroName)) { Write-Bad 'NetLab is not installed yet. Run Setup.cmd first.'; Done 1 }
if (-not $Path) { $Path = (Read-Host 'Path of the IOL image file (drag it into this window, then Enter)').Trim().Trim('"') }
if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Write-Bad "File not found: $Path"; Done 1 }

Write-Step "Importing $Path"
Sync-NetLab
$args2 = @('/opt/netlab/wsl/import-iol.sh', (ConvertTo-WslPath $Path))
if ($s.paths.dataDir) {
    $backup = Join-Path $s.paths.dataDir 'images'
    New-Item -ItemType Directory -Force -Path $backup | Out-Null
    $args2 += @('--backup-dir', (ConvertTo-WslPath $backup))
}
Invoke-Wsl $args2
if ($LASTEXITCODE -ne 0) { Write-Bad 'Import failed (see the messages above).'; Done 1 }
Write-Ok 'Image ready. Deploy the "phase1" lab from NetLab.cmd.'
Done 0
