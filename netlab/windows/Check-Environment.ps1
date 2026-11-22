# Check-Environment.ps1 - read-only check of this PC for NetLab.
# Changes nothing. Prints a report and saves it to state\environment-report.txt
# (send that file when you report back after Phase 1).

. "$PSScriptRoot\NetLab.Common.ps1"

function Invoke-EnvironmentCheck {
    $s = Get-NetLabSettings
    $script:DistroName = $s.wsl.distroName
    $report = New-Object System.Collections.Generic.List[string]
    $problems = 0
    function Add-Line([string]$Status, [string]$Text) {
        $report.Add(('{0,-6} {1}' -f $Status, $Text))
        switch ($Status) {
            'OK'   { Write-Ok $Text }
            'WARN' { Write-Warn $Text }
            'FAIL' { Write-Bad $Text }
            default { Write-Info $Text }
        }
    }

    Write-Step 'Windows'
    $hw = Get-HardwareInfo
    if ($hw.OsBuild -ge 19041) { Add-Line 'OK' "$($hw.OsCaption) (build $($hw.OsBuild))" }
    else { Add-Line 'FAIL' "$($hw.OsCaption) (build $($hw.OsBuild)): WSL 2 needs Windows 10 build 19041 or newer"; $problems++ }
    if ($hw.OsBuild -lt 22000) { Add-Line 'INFO' 'Windows 10: fine for NetLab (Windows 11 adds WSL mirrored networking, optional)' }

    Write-Step 'CPU and virtualization'
    Add-Line 'INFO' "$($hw.CpuName): $($hw.Cores) cores / $($hw.Threads) threads"
    $virt = Get-VirtualizationState $hw
    switch ($virt) {
        'Enabled'  { Add-Line 'OK' 'Hardware virtualization (AMD-V / SVM) is enabled' }
        'Disabled' { Add-Line 'FAIL' 'Hardware virtualization (AMD-V / SVM) is DISABLED in the BIOS'; $problems++; Write-Host $BiosHelp -ForegroundColor Yellow }
        default    { Add-Line 'WARN' 'Could not read the virtualization state; Setup will tell you if WSL 2 cannot start' }
    }

    Write-Step 'Memory'
    $wslMem = Get-RecommendedWslMemoryGB $hw $s
    Add-Line 'INFO' "RAM: $($hw.TotalRamGB) GB total, $([math]::Round($hw.FreeRamMB / 1024, 1)) GB free right now"
    Add-Line 'INFO' "Recommended WSL limit: $wslMem GB (memory is used only when needed and given back when idle)"
    if ($hw.TotalRamGB -lt 7.5) { Add-Line 'WARN' 'Less than 8 GB RAM: keep labs small (about 6-8 IOL nodes)' }

    Write-Step 'Disks'
    $drives = Get-DriveInfo
    foreach ($d in $drives) { Add-Line 'INFO' ("{0}:  {1,-7} {2,5} GB free of {3,5} GB  {4}" -f $d.Letter, $d.Media, $d.FreeGB, $d.SizeGB, $d.Name) }
    if (-not ($drives | Where-Object { $_.Media -eq 'SSD' })) { Add-Line 'WARN' 'No SSD detected (or not reported by Windows); NetLab works on an HDD but boots slower' }

    Write-Step 'WSL'
    $wslVer = Get-WslVersion
    if ($null -eq $wslVer) {
        Add-Line 'WARN' 'WSL is not installed (or it is the old built-in version). Setup can install/update it.'
    } elseif ($wslVer -lt [version]'2.0.0') {
        Add-Line 'WARN' "WSL $wslVer is old; Setup will update it (NetLab needs 2.0 or newer)"
    } else {
        Add-Line 'OK' "WSL $wslVer"
    }
    $distros = Get-WslDistros
    if ($distros.Count -gt 0) { Add-Line 'INFO' ("Installed distros: " + ($distros -join ', ')) }
    if ($distros -contains $s.wsl.distroName) { Add-Line 'OK' "NetLab distro '$($s.wsl.distroName)' is installed" }
    else { Add-Line 'INFO' "NetLab distro '$($s.wsl.distroName)' is not installed yet (Setup creates it)" }

    $wslconfig = Join-Path $env:USERPROFILE '.wslconfig'
    if (Test-Path $wslconfig) {
        $keys = @(Get-Content $wslconfig | Where-Object { $_ -match '^\s*(memory|swap|processors|autoMemoryReclaim|networkingMode)\s*=' })
        Add-Line 'INFO' (".wslconfig exists: " + ($keys -join '; '))
    } else {
        Add-Line 'INFO' '.wslconfig does not exist (WSL would use up to 50% of RAM; Setup proposes a limit)'
    }

    Write-Step 'Other software'
    if (Find-DockerDesktop) {
        Add-Line 'WARN' 'Docker Desktop is installed. NetLab does not need it (it uses Docker Engine inside its own distro).'
        Add-Line 'INFO' '       Quit Docker Desktop while labbing to save 1-2 GB RAM, and do not enable its WSL integration for the NetLab distro.'
    } else {
        Add-Line 'OK' 'Docker Desktop is not installed (good: NetLab uses the lighter Docker Engine)'
    }
    $ws = Find-Wireshark
    if ($ws) { Add-Line 'OK' "Wireshark: $ws" } else { Add-Line 'WARN' 'Wireshark not found (needed for link capture): https://www.wireshark.org/download.html' }
    $putty = Find-Putty
    if ($putty) { Add-Line 'OK' "PuTTY: $putty" } else { Add-Line 'WARN' 'PuTTY not found (optional; consoles also open in a WSL telnet window): https://www.putty.org' }

    Write-Host ''
    if ($problems -eq 0) { Write-Host 'No blocking problems found.' -ForegroundColor Green }
    else { Write-Host "$problems blocking problem(s) found, see FAIL lines above." -ForegroundColor Red }

    New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
    $file = Join-Path $StateDir 'environment-report.txt'
    @("NetLab environment report - $(Get-Date -Format 'yyyy-MM-dd HH:mm')") + $report | Set-Content -Path $file -Encoding ASCII
    Write-Host "Report saved to $file"
    return [pscustomobject]@{ Problems = $problems; Hardware = $hw; Virtualization = $virt; WslVersion = $wslVer; Drives = $drives }
}

# Run the check when this file is started directly (not when Setup loads it).
if ($MyInvocation.InvocationName -ne '.') {
    Invoke-EnvironmentCheck | Out-Null
}
