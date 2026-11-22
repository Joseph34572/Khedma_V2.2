# Setup-NetLab.ps1 - one-time setup of NetLab on this PC.
#
# Every step that changes something on your system asks first. Safe to run
# again: finished steps are detected and skipped.
#   1. check this PC (read-only)
#   2. install / update WSL (only if needed; needs administrator rights)
#   3. choose folders (WSL distro + Docker images on the SSD, data on the HDD)
#   4. propose a .wslconfig (memory limit, swap, memory reclaim) - backup first
#   5. create the "NetLab" WSL distro (Ubuntu 24.04) in the chosen SSD folder
#   6. install Docker Engine + containerlab + vrnetlab inside that distro
#   7. build the small NetLab node images (Linux PC, Windows PC, firewall)

. "$PSScriptRoot\NetLab.Common.ps1"
. "$PSScriptRoot\Check-Environment.ps1"

function Stop-Setup([string]$Message) {
    Write-Host ''
    Write-Host $Message -ForegroundColor Yellow
    Read-Host 'Press Enter to close'
    exit 1
}

Write-Host 'NetLab setup' -ForegroundColor Cyan
Write-Host 'Each step that changes your system asks first. Nothing is downloaded from Cisco.'

$s = Get-NetLabSettings
$script:DistroName = $s.wsl.distroName

# -------------------------------------------------------------- 1. check
$check = Invoke-EnvironmentCheck
if ($check.Virtualization -eq 'Disabled') {
    Stop-Setup 'Enable virtualization in the BIOS first (instructions above), then run Setup again.'
}
if ($check.Hardware.OsBuild -lt 19041) {
    Stop-Setup 'This Windows version is too old for WSL 2. Update Windows, then run Setup again.'
}

# ---------------------------------------------------------- 2. WSL itself
Write-Step 'Step 2: WSL'
$wslVer = $check.WslVersion
if (($null -eq $wslVer) -or ($wslVer -lt [version]'2.0.0')) {
    if ($null -eq $wslVer) {
        Write-Info 'WSL is missing or is the old built-in version.'
        Write-Info 'This runs (as administrator):  wsl --install --no-distribution'
        Write-Info 'It turns on the Windows features "Virtual Machine Platform" and WSL. A restart may be needed.'
        if (-not (Confirm-Step 'Install WSL now?' $true)) { Stop-Setup 'WSL is required. Setup stopped.' }
        $p = Start-Process -FilePath wsl.exe -ArgumentList '--install', '--no-distribution' -Verb RunAs -Wait -PassThru
        if ($p.ExitCode -ne 0) {
            Write-Warn "wsl --install returned $($p.ExitCode); trying 'wsl --update'"
            $p = Start-Process -FilePath wsl.exe -ArgumentList '--update' -Verb RunAs -Wait -PassThru
        }
    } else {
        Write-Info "WSL $wslVer is older than 2.0. This runs (as administrator):  wsl --update"
        if (-not (Confirm-Step 'Update WSL now?' $true)) { Stop-Setup 'NetLab needs WSL 2.0 or newer. Setup stopped.' }
        $p = Start-Process -FilePath wsl.exe -ArgumentList '--update' -Verb RunAs -Wait -PassThru
    }
    $wslVer = Get-WslVersion
    if (($null -eq $wslVer) -or ($wslVer -lt [version]'2.0.0')) {
        Stop-Setup 'WSL was installed/updated. Restart Windows, then run Setup again.'
    }
}
Write-Ok "WSL $wslVer"

# ------------------------------------------------------------- 3. folders
Write-Step 'Step 3: folders'
$distroExists = Test-Distro $s.wsl.distroName
$drives = @($check.Drives)
$sysLetter = $env:SystemDrive.TrimEnd(':')
$ssd = @($drives | Where-Object { $_.Media -eq 'SSD' } | Sort-Object -Property FreeGB -Descending)
$ssdPick = @($ssd | Where-Object { $_.Letter -eq $sysLetter }) + $ssd + @($drives | Where-Object { $_.Letter -eq $sysLetter })
$ssdLetter = $sysLetter
if ($ssdPick.Count -gt 0) { $ssdLetter = $ssdPick[0].Letter }
$hdd = @($drives | Where-Object { $_.Media -eq 'HDD' } | Sort-Object -Property FreeGB -Descending)

$defaultDistroDir = "$($ssdLetter):\NetLab\wsl"
if ($s.paths.distroDir) { $defaultDistroDir = $s.paths.distroDir }
$defaultDataDir = "$($ssdLetter):\NetLab\data"
if ($hdd.Count -gt 0) { $defaultDataDir = "$($hdd[0].Letter):\NetLab" }
if ($s.paths.dataDir) { $defaultDataDir = $s.paths.dataDir }

if ($distroExists -and $s.paths.distroDir) {
    Write-Ok "NetLab distro already installed in $($s.paths.distroDir)"
    $distroDir = $s.paths.distroDir
} else {
    Write-Info 'The WSL distro holds Docker and all node images: put it on the SSD.'
    $distroDir = Read-Default 'Folder for the NetLab WSL distro' $defaultDistroDir
}
Write-Info 'Saved labs and backups of your imported images can go on the HDD.'
$dataDir = Read-Default 'Folder for NetLab data (labs, image backups)' $defaultDataDir

$letter = $distroDir.Substring(0, 1)
$d = $drives | Where-Object { $_.Letter -eq $letter } | Select-Object -First 1
if ($d -and ($d.FreeGB -lt 20)) { Write-Warn "Only $($d.FreeGB) GB free on $($letter): - NetLab needs about 10-20 GB there (Ubuntu, Docker, images)." }

$s.paths.distroDir = $distroDir
$s.paths.dataDir = $dataDir
Save-NetLabSettings $s
Write-Ok "Saved in $SettingsPath"

# ---------------------------------------------------------- 4. .wslconfig
Write-Step 'Step 4: WSL memory settings (.wslconfig)'
$memGB = Get-RecommendedWslMemoryGB $check.Hardware $s
$swapPath = (Join-Path $distroDir 'swap.vhdx').Replace('\', '\\')     # .wslconfig wants \\ in paths
$values = [ordered]@{
    'wsl2'         = [ordered]@{ memory = "$($memGB)GB"; swap = "$($s.wsl.swapGB)GB"; swapFile = $swapPath }
    'experimental' = [ordered]@{ autoMemoryReclaim = "$($s.wsl.autoMemoryReclaim)" }
}
$wslconfig = Join-Path $env:USERPROFILE '.wslconfig'
$old = @()
if (Test-Path $wslconfig) { $old = @(Get-Content $wslconfig) }
$new = Set-IniValues $old $values

Write-Info "Your WSL version is $wslVer. For it, the settings live in:"
Write-Info "  [wsl2]          memory, swap, swapFile"
Write-Info "  [experimental]  autoMemoryReclaim (gradual = give unused memory back to Windows)"
Write-Info "These are limits, not reservations: WSL takes RAM only when the lab needs it."
Write-Info "They apply to every WSL distro on this PC."
Write-Host ''
Write-Host '  Current .wslconfig:' -ForegroundColor Gray
if ($old.Count -eq 0) { Write-Host '    (file does not exist)' } else { $old | ForEach-Object { Write-Host "    $_" } }
Write-Host '  Proposed .wslconfig:' -ForegroundColor Gray
$new | ForEach-Object { Write-Host "    $_" }
Write-Host ''
if ((($old -join "`n").Trim()) -eq (($new -join "`n").Trim())) {
    Write-Ok '.wslconfig already has these settings'
} elseif (Confirm-Step "Write this to $wslconfig ? (the old file is backed up first)" $true) {
    if (Test-Path $wslconfig) {
        $bak = "$wslconfig.netlab-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item $wslconfig $bak
        Write-Ok "Backup: $bak"
    }
    New-Item -ItemType Directory -Force -Path $distroDir | Out-Null
    [System.IO.File]::WriteAllLines($wslconfig, $new, (New-Object System.Text.UTF8Encoding($false)))
    Write-Ok '.wslconfig written'
    $running = @(& wsl.exe --list --running --quiet 2>$null | ForEach-Object { "$_".Trim([char]0, ' ') } | Where-Object { $_ })
    if ($running.Count -gt 0) {
        Write-Info ('WSL is running (' + ($running -join ', ') + '). The new limits apply after "wsl --shutdown".')
        if (Confirm-Step 'Shut down WSL now? (stops all running distros)' $false) { & wsl.exe --shutdown; Write-Ok 'WSL stopped' }
        else { Write-Info 'OK, they will apply the next time WSL starts.' }
    }
} else {
    Write-Info '.wslconfig left unchanged.'
}

# -------------------------------------------------------- 5. NetLab distro
Write-Step "Step 5: the '$($s.wsl.distroName)' WSL distro"
if ($distroExists) {
    Write-Ok "'$($s.wsl.distroName)' already exists"
} else {
    Write-Info "This downloads the official $($s.wsl.baseImage) WSL image listed by Microsoft (about 350 MB),"
    Write-Info "checks its SHA-256 and imports it as '$($s.wsl.distroName)' into $distroDir."
    Write-Info 'Your other WSL distros are not touched.'
    if (-not (Confirm-Step 'Create the NetLab distro now?' $true)) { Stop-Setup 'Setup stopped before creating the distro.' }

    $dl = Join-Path $distroDir 'download'
    New-Item -ItemType Directory -Force -Path $dl | Out-Null
    $listFile = Join-Path $dl 'DistributionInfo.json'
    & curl.exe -sSL --fail -o $listFile 'https://raw.githubusercontent.com/microsoft/WSL/master/distributions/DistributionInfo.json'
    if ($LASTEXITCODE -ne 0) { Stop-Setup 'Could not download the WSL distribution list (internet connection?).' }
    $list = Get-Content $listFile -Raw | ConvertFrom-Json
    $entry = $null
    foreach ($family in $list.ModernDistributions.PSObject.Properties) {
        foreach ($e in $family.Value) { if ($e.Name -eq $s.wsl.baseImage) { $entry = $e } }
    }
    if ($null -eq $entry) { Stop-Setup "$($s.wsl.baseImage) is not in Microsoft's list. Change wsl.baseImage in $SettingsPath." }

    $url = $entry.Amd64Url.Url
    $sha = ("$($entry.Amd64Url.Sha256)" -replace '^0x', '').ToUpper()
    $file = Join-Path $dl ([System.IO.Path]::GetFileName($url))
    Write-Info "Downloading $url"
    & curl.exe -L --fail -o $file $url
    if ($LASTEXITCODE -ne 0) { Stop-Setup 'Download failed.' }
    $hash = (Get-FileHash -Path $file -Algorithm SHA256).Hash.ToUpper()
    if ($hash -ne $sha) { Remove-Item $file; Stop-Setup "Checksum mismatch for the Ubuntu image (expected $sha, got $hash). Nothing was installed." }
    Write-Ok 'Checksum verified'

    & wsl.exe --import $s.wsl.distroName $distroDir $file --version 2
    if ($LASTEXITCODE -ne 0) {
        Stop-Setup ('wsl --import failed (see the message above). If WSL was installed just now, restart ' +
                    'Windows first. If the message mentions virtualization, enable SVM/AMD-V in the BIOS.')
    }
    Remove-Item $file, $listFile -ErrorAction SilentlyContinue
    Write-Ok "Imported '$($s.wsl.distroName)' into $distroDir"

    # wsl.conf inside the distro:
    #   systemd=true            Docker runs as a normal service
    #   default=root            NetLab scripts run as root in this lab-only distro
    #   appendWindowsPath=false keeps Linux commands fast and unambiguous
    Invoke-Wsl @('sh', '-c', "printf '[boot]\nsystemd=true\n\n[user]\ndefault=root\n\n[interop]\nappendWindowsPath=false\n' > /etc/wsl.conf")
    & wsl.exe --terminate $s.wsl.distroName | Out-Null
    Write-Ok 'Configured /etc/wsl.conf (systemd on)'
}

# ------------------------------------------------------- 6. engine inside
Write-Step 'Step 6: Docker Engine + containerlab inside the NetLab distro'
Sync-NetLab
$have = Get-WslOutput @('sh', '-c', 'command -v docker >/dev/null && command -v containerlab >/dev/null && test -d /opt/vrnetlab && echo yes')
if (($have -join '') -match 'yes') {
    Write-Ok 'Already installed'
    if (Confirm-Step 'Re-run the installer anyway (updates vrnetlab)?' $false) {
        Invoke-Wsl @('/opt/netlab/wsl/install-engine.sh', '--yes')
    }
} else {
    Write-Info 'Installs into the NetLab distro only (not into Windows):'
    Write-Info '  Docker Engine (download.docker.com), containerlab (netdevops apt repo),'
    Write-Info '  vrnetlab (github.com/srl-labs/vrnetlab, formerly hellt/vrnetlab), tcpdump, jq, git, make.'
    if (-not (Confirm-Step 'Install now?' $true)) { Stop-Setup 'Setup stopped before installing the engine.' }
    Invoke-Wsl @('/opt/netlab/wsl/install-engine.sh', '--yes')
    if ($LASTEXITCODE -ne 0) { Stop-Setup 'The engine installation failed (see the messages above).' }
}

# ------------------------------------------------------------ 7. images
Write-Step 'Step 7: NetLab node images (Linux PC, Windows PC, Linux firewall)'
if (Confirm-Step 'Build them now? (about 1-2 minutes, ~30 MB in total)' $true) {
    Invoke-Wsl @('/opt/netlab/wsl/build-images.sh')
    if ($LASTEXITCODE -ne 0) { Stop-Setup 'Building the images failed (see the messages above).' }
}

Write-Step 'Done'
Write-Host '  Next steps:'
Write-Host '   - Start NetLab.cmd (menu) and deploy the "smoke" lab: it needs no Cisco image.'
Write-Host '   - Import your IOL / IOL-L2 images: drag the file onto Import-Image.cmd,'
Write-Host '     then deploy the "phase1" lab.'
Write-Host ''
Read-Host 'Press Enter to close'
