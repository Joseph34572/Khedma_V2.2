# NetLab.Common.ps1 - shared functions for the NetLab Windows scripts.
# Loaded by the other scripts with:  . "$PSScriptRoot\NetLab.Common.ps1"
# Written for Windows PowerShell 5.1 (built into Windows 10/11).

$NetLabRoot          = Split-Path -Parent $PSScriptRoot
$SettingsDefaultPath = Join-Path $NetLabRoot 'config\settings.default.json'
$SettingsPath        = Join-Path $NetLabRoot 'config\settings.json'
$StateDir            = Join-Path $NetLabRoot 'state'

# wsl.exe prints UTF-16 by default; this makes it print UTF-8 so we can read it.
$env:WSL_UTF8 = '1'

# ------------------------------------------------------------------ output

function Write-Step([string]$Msg) { Write-Host ''; Write-Host "==> $Msg" -ForegroundColor Cyan }
function Write-Ok([string]$Msg)   { Write-Host "  [OK]   $Msg" -ForegroundColor Green }
function Write-Warn([string]$Msg) { Write-Host "  [WARN] $Msg" -ForegroundColor Yellow }
function Write-Bad([string]$Msg)  { Write-Host "  [FAIL] $Msg" -ForegroundColor Red }
function Write-Info([string]$Msg) { Write-Host "         $Msg" }

# Asks a yes/no question. Enter = the default answer.
function Confirm-Step([string]$Question, [bool]$DefaultYes = $false) {
    $suffix = '[y/N]'
    if ($DefaultYes) { $suffix = '[Y/n]' }
    while ($true) {
        $a = Read-Host "$Question $suffix"
        if ([string]::IsNullOrWhiteSpace($a)) { return $DefaultYes }
        if ($a -match '^(y|yes)$') { return $true }
        if ($a -match '^(n|no)$')  { return $false }
    }
}

# Asks for a value. Enter = the default value.
function Read-Default([string]$Question, [string]$Default) {
    $a = Read-Host "$Question [$Default]"
    if ([string]::IsNullOrWhiteSpace($a)) { return $Default }
    return $a.Trim().Trim('"')
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ---------------------------------------------------------------- settings

# Adds keys that exist in the defaults but not (yet) in the user's settings.
function Merge-Defaults($Target, $Defaults) {
    foreach ($p in $Defaults.PSObject.Properties) {
        $t = $Target.PSObject.Properties[$p.Name]
        if ($null -eq $t) {
            $Target | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value
        } elseif (($p.Value -is [System.Management.Automation.PSCustomObject]) -and ($t.Value -is [System.Management.Automation.PSCustomObject])) {
            Merge-Defaults $t.Value $p.Value
        }
    }
}

function Get-NetLabSettings {
    if (-not (Test-Path $SettingsPath)) { Copy-Item $SettingsDefaultPath $SettingsPath }
    $s = Get-Content $SettingsPath -Raw | ConvertFrom-Json
    $d = Get-Content $SettingsDefaultPath -Raw | ConvertFrom-Json
    Merge-Defaults $s $d
    return $s
}

function Save-NetLabSettings($Settings) {
    $json = $Settings | ConvertTo-Json -Depth 10
    # UTF-8 without BOM, so the Linux tools (jq, python) read it without trouble.
    [System.IO.File]::WriteAllText($SettingsPath, $json, (New-Object System.Text.UTF8Encoding($false)))
}

# --------------------------------------------------------------------- WSL

# Returns the WSL version as [version], or $null when WSL is missing or is the
# old built-in ("inbox") version that has no --version option.
function Get-WslVersion {
    try { $out = & wsl.exe --version 2>$null } catch { return $null }
    if ($LASTEXITCODE -ne 0 -or -not $out) { return $null }
    foreach ($line in $out) {
        if ("$line" -match '(\d+\.\d+\.\d+)') { return [version]$Matches[1] }
    }
    return $null
}

function Get-WslDistros {
    try { $out = & wsl.exe --list --quiet 2>$null } catch { return @() }
    if ($LASTEXITCODE -ne 0) { return @() }
    return @($out | ForEach-Object { "$_".Trim([char]0, ' ', "`t") } | Where-Object { $_ })
}

function Test-Distro([string]$Name) {
    return ((Get-WslDistros) -contains $Name)
}

# Runs a program as root inside the NetLab distro (no Linux shell in between,
# so arguments with spaces arrive unchanged). Check $LASTEXITCODE afterwards.
#   Invoke-Wsl @('/opt/netlab/wsl/lab.sh', 'deploy', 'phase1')
function Invoke-Wsl([string[]]$Arguments, [string]$Cd = '') {
    $a = @('-d', $script:DistroName, '-u', 'root')
    if ($Cd) { $a += @('--cd', $Cd) }
    $a += '--exec'
    $a += $Arguments
    & wsl.exe @a
}

# Same, but returns the output lines instead of printing them.
function Get-WslOutput([string[]]$Arguments) {
    $a = @('-d', $script:DistroName, '-u', 'root', '--exec') + $Arguments
    $out = & wsl.exe @a 2>&1
    return @($out | ForEach-Object { "$_" })
}

# C:\Users\me\file.bin -> /mnt/c/Users/me/file.bin
function ConvertTo-WslPath([string]$Path) {
    $full = [System.IO.Path]::GetFullPath($Path)
    if ($full -match '^([A-Za-z]):\\(.*)$') {
        return '/mnt/' + $Matches[1].ToLower() + '/' + ($Matches[2] -replace '\\', '/')
    }
    throw "Cannot use '$Path' from WSL (only local drive paths like C:\... are supported)."
}

# Copies the NetLab code from this folder into the distro (/opt/netlab).
function Sync-NetLab {
    Invoke-Wsl @('bash', '-c', "tr -d '\r' < wsl/sync.sh | bash -s") -Cd $NetLabRoot
    if ($LASTEXITCODE -ne 0) { throw 'Could not copy the NetLab files into WSL (wsl/sync.sh failed).' }
}

# ---------------------------------------------------------------- hardware

function Get-HardwareInfo {
    $cs   = Get-CimInstance Win32_ComputerSystem
    $os   = Get-CimInstance Win32_OperatingSystem
    $cpus = @(Get-CimInstance Win32_Processor)
    return [pscustomobject]@{
        CpuName           = "$($cpus[0].Name)".Trim()
        Cores             = ($cpus | Measure-Object -Property NumberOfCores -Sum).Sum
        Threads           = ($cpus | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
        TotalRamGB        = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
        FreeRamMB         = [math]::Round($os.FreePhysicalMemory / 1KB, 0)   # FreePhysicalMemory is in KB
        HypervisorPresent = [bool]$cs.HypervisorPresent
        VirtFirmware      = $cpus[0].VirtualizationFirmwareEnabled
        OsCaption         = "$($os.Caption)".Trim()
        OsBuild           = [int]$os.BuildNumber
    }
}

# 'Enabled', 'Disabled' or 'Unknown'.
# When Hyper-V/WSL2 already runs, Windows reports VirtualizationFirmwareEnabled
# as False even though it is on, so a running hypervisor counts as "enabled".
function Get-VirtualizationState($Hw) {
    if ($Hw.HypervisorPresent) { return 'Enabled' }
    if ($Hw.VirtFirmware -eq $true) { return 'Enabled' }
    if ($Hw.VirtFirmware -eq $false) { return 'Disabled' }
    return 'Unknown'
}

# Drive letters with media type (SSD/HDD), free and total size.
function Get-DriveInfo {
    $result = @()
    try {
        $physical = @{}
        foreach ($pd in (Get-PhysicalDisk -ErrorAction Stop)) { $physical["$($pd.DeviceId)"] = $pd }
        foreach ($part in (Get-Partition -ErrorAction Stop | Where-Object { $_.DriveLetter })) {
            $pd = $physical["$($part.DiskNumber)"]
            $media = 'Unknown'
            $name = ''
            if ($pd) {
                $name = $pd.FriendlyName
                if (("$($pd.BusType)" -eq 'NVMe') -or ("$($pd.MediaType)" -eq 'SSD')) { $media = 'SSD' }
                elseif ("$($pd.MediaType)" -eq 'HDD') { $media = 'HDD' }
            }
            $vol = Get-Volume -DriveLetter $part.DriveLetter -ErrorAction SilentlyContinue
            $free = 0; $size = 0
            if ($vol) { $free = [math]::Round($vol.SizeRemaining / 1GB, 0); $size = [math]::Round($vol.Size / 1GB, 0) }
            $result += [pscustomobject]@{ Letter = "$($part.DriveLetter)"; Media = $media; FreeGB = $free; SizeGB = $size; Name = $name }
        }
    } catch {
        foreach ($d in (Get-PSDrive -PSProvider FileSystem)) {
            if ($null -ne $d.Free) {
                $result += [pscustomobject]@{ Letter = $d.Name; Media = 'Unknown'; FreeGB = [math]::Round($d.Free / 1GB, 0); SizeGB = [math]::Round(($d.Used + $d.Free) / 1GB, 0); Name = '' }
            }
        }
    }
    return $result
}

# WSL memory limit: total RAM minus what Windows keeps (see settings.json).
function Get-RecommendedWslMemoryGB($Hw, $Settings) {
    $total = [math]::Round($Hw.TotalRamGB)
    $reserve = [math]::Max([double]$Settings.wsl.memoryReserveMinGB, [math]::Ceiling($total * [double]$Settings.wsl.memoryReservePercent / 100))
    return [int][math]::Max(2, $total - $reserve)
}

function Find-Wireshark {
    $candidates = @()
    $reg = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\Wireshark.exe' -ErrorAction SilentlyContinue
    if ($reg) { $candidates += $reg.'(default)' }
    $candidates += "$env:ProgramFiles\Wireshark\Wireshark.exe"
    $candidates += "${env:ProgramFiles(x86)}\Wireshark\Wireshark.exe"
    foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { return $c } }
    return $null
}

function Find-Putty {
    $cmd = Get-Command putty.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($c in @("$env:ProgramFiles\PuTTY\putty.exe", "${env:ProgramFiles(x86)}\PuTTY\putty.exe")) {
        if (Test-Path $c) { return $c }
    }
    return $null
}

function Find-DockerDesktop {
    $p = "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
    if (Test-Path $p) { return $p }
    return $null
}

# ------------------------------------------------------------------- .ini

# Sets keys in an INI file (like .wslconfig) and keeps everything else:
# other keys, other sections and comments stay as they were.
#   $Values = [ordered]@{ 'wsl2' = [ordered]@{ memory = '5GB' } }
function Set-IniValues([string[]]$Lines, [System.Collections.IDictionary]$Values) {
    $out = New-Object System.Collections.Generic.List[string]
    $written = @{}
    $section = ''
    $flush = {
        param($sec)
        if ($sec -and $Values.Contains($sec)) {
            foreach ($k in $Values[$sec].Keys) {
                if (-not $written.Contains("$sec|$k")) { $out.Add("$k=$($Values[$sec][$k])"); $written["$sec|$k"] = $true }
            }
        }
    }
    foreach ($line in $Lines) {
        if ($line -match '^\s*\[([^\]]+)\]\s*$') {
            & $flush $section
            $section = $Matches[1].Trim().ToLower()
            $out.Add($line)
            continue
        }
        if ($section -and $Values.Contains($section) -and ($line -match '^\s*([^#;=\s][^=]*?)\s*=')) {
            $key = $Matches[1]
            $known = @($Values[$section].Keys | Where-Object { $_ -ieq $key })
            if ($known.Count -gt 0) {
                $k = $known[0]
                if (-not $written.Contains("$section|$k")) { $out.Add("$k=$($Values[$section][$k])"); $written["$section|$k"] = $true }
                continue
            }
        }
        $out.Add($line)
    }
    & $flush $section
    foreach ($sec in $Values.Keys) {
        $missing = @($Values[$sec].Keys | Where-Object { -not $written.Contains("$sec|$_") })
        if ($missing.Count -gt 0) {
            if ($out.Count -gt 0 -and $out[$out.Count - 1] -ne '') { $out.Add('') }
            $out.Add("[$sec]")
            foreach ($k in $missing) { $out.Add("$k=$($Values[$sec][$k])") }
        }
    }
    return ,$out.ToArray()
}

# Text shown when AMD-V / Intel VT-x is off.
$BiosHelp = @'
  How to turn on CPU virtualization (AMD-V, called "SVM Mode" on AMD boards):
    1. Restart the PC and press Del (or F2) while it starts to open the BIOS/UEFI setup.
    2. Find the CPU settings (switch to "Advanced Mode" with F7 if you see a simple screen):
         ASUS:     Advanced > CPU Configuration > SVM Mode
         MSI:      OC > Advanced CPU Configuration > SVM Mode
         Gigabyte: Tweaker > Advanced CPU Settings > SVM Mode
         ASRock:   Advanced > CPU Configuration > SVM Mode
       (Intel boards: "Intel Virtualization Technology" / "VT-x".)
    3. Set it to Enabled, save with F10 and restart. Then run Setup again.
'@
