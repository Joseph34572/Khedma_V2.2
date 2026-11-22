# NetLab-Menu.ps1 - the Phase 1 control menu (no GUI yet).
# Deploy / destroy labs, open consoles in PuTTY, capture links in Wireshark,
# run connectivity tests and the boot time / RAM report.

. "$PSScriptRoot\NetLab.Common.ps1"

$s = Get-NetLabSettings
$script:DistroName = $s.wsl.distroName

function Pause-Menu { Read-Host 'Press Enter to continue' | Out-Null }

# --------------------------------------------------------- keep-alive
# WSL stops an idle distro after ~15 s, which would kill a running lab.
# A hidden "sleep" process keeps it alive while a lab is deployed.
function Test-KeepAlive {
    $null = Get-WslOutput @('pgrep', '-f', 'netlab-keepalive')
    return ($LASTEXITCODE -eq 0)
}
function Start-KeepAlive {
    if (Test-KeepAlive) { return }
    Start-Process -FilePath wsl.exe -WindowStyle Hidden -ArgumentList @('-d', $script:DistroName, '-u', 'root', '--exec', '/opt/netlab/wsl/keepalive.sh')
}
function Stop-KeepAlive {
    $null = Get-WslOutput @('pkill', '-f', 'netlab-keepalive')
}
function Test-AnyLabRunning {
    $out = Get-WslOutput @('docker', 'ps', '-q', '--filter', 'label=containerlab')
    return (($out -join '').Trim().Length -gt 0)
}

# ---------------------------------------------------------------- labs
function Select-Lab {
    $lines = Get-WslOutput @('/opt/netlab/wsl/lab.sh', 'list')
    $labs = @()
    Write-Host ''
    Write-Host 'Labs:'
    foreach ($l in $lines) {
        if ($l -match '^(\S+)\s+(\S+)\s*(.*)$') {
            $labs += $Matches[1]
            Write-Host ('  {0}) {1,-10} {2,-8} {3}' -f $labs.Count, $Matches[1], $Matches[2], $Matches[3])
        }
    }
    if ($labs.Count -eq 0) { Write-Bad 'No labs found in labs\'; return $null }
    $n = Read-Default 'Choose a lab' '1'
    $i = 0
    if ([int]::TryParse($n, [ref]$i) -and $i -ge 1 -and $i -le $labs.Count) { return $labs[$i - 1] }
    return $null
}

function Get-Nodes([string]$Lab) {
    $nodes = @()
    foreach ($l in (Get-WslOutput @('/opt/netlab/wsl/lab.sh', 'nodes', $Lab))) {
        $f = $l -split "`t"
        if ($f.Count -ge 6) { $nodes += [pscustomobject]@{ Name = $f[0]; Kind = $f[1]; Type = $f[2]; Telnet = $f[4]; Ssh = $f[5] } }
    }
    return $nodes
}

function Select-FromList([string]$Title, $Items, [scriptblock]$Label) {
    Write-Host ''
    Write-Host $Title
    for ($i = 0; $i -lt $Items.Count; $i++) { Write-Host ('  {0,2}) {1}' -f ($i + 1), (& $Label $Items[$i])) }
    $n = Read-Host 'Number (Enter = back)'
    $k = 0
    if ([int]::TryParse($n, [ref]$k) -and $k -ge 1 -and $k -le $Items.Count) { return $Items[$k - 1] }
    return $null
}

# ------------------------------------------------------------- actions
function Invoke-Deploy([string]$Lab) {
    $plan = Get-WslOutput @('/opt/netlab/wsl/lab.sh', 'plan', $Lab)
    $kv = @{}
    foreach ($l in $plan) { if ($l -match '^([A-Z_]+)=(.*)$') { $kv[$Matches[1]] = $Matches[2] } else { Write-Host $l } }
    if ($kv['MISSING_IMAGES']) {
        Write-Bad "Missing images: $($kv['MISSING_IMAGES'])"
        Write-Info 'Import your IOL image (menu 9) or build the NetLab images (Setup).'
        return
    }
    $need = [int]$kv['NEED_MB']; $wslAvail = [int]$kv['WSL_AVAILABLE_MB']; $margin = [int]$kv['MARGIN_MB']
    $winFree = (Get-HardwareInfo).FreeRamMB
    Write-Host ''
    Write-Info "Lab '$Lab': $($kv['NODES']) nodes, needs about $need MB (estimate, nothing is reserved)."
    Write-Info "WSL can still use $wslAvail MB; Windows has $winFree MB free."
    $fits = ($need -le ($wslAvail - $margin)) -and ($need -le ($winFree - $margin))
    if ([int]$kv['VM_NODES'] -gt 0) {
        Write-Warn "$($kv['VM_NODES']) node(s) are full virtual machines (e.g. ASAv). Each needs several GB of RAM and boots for minutes."
        $fits = $false
    }
    if (-not $fits) {
        Write-Warn 'This lab may not fit in the free memory. Windows or WSL could start swapping.'
        if (-not (Confirm-Step 'Deploy anyway?' $false)) { return }
    }
    Invoke-Wsl @('/opt/netlab/wsl/lab.sh', 'deploy', $Lab)
    if ($LASTEXITCODE -eq 0) { Start-KeepAlive }
}

function Invoke-Destroy([string]$Lab) {
    Invoke-Wsl @('/opt/netlab/wsl/lab.sh', 'destroy', $Lab)
    if (-not (Test-AnyLabRunning)) { Stop-KeepAlive; Write-Info 'No lab is running: WSL will stop by itself and give its RAM back.' }
}

function Open-Console([string]$Lab) {
    $nodes = @(Get-Nodes $Lab | Where-Object { $_.Telnet -ne '-' })
    if ($nodes.Count -eq 0) { Write-Bad 'This lab has no console ports.'; return }
    $node = Select-FromList 'Open the console of:' $nodes { param($n) '{0,-8} {1,-10} telnet 127.0.0.1:{2}' -f $n.Name, $n.Kind, $n.Telnet }
    if ($null -eq $node) { return }
    $putty = Find-Putty
    if ($putty) {
        # PuTTY in telnet mode on the node's console port.
        Start-Process -FilePath $putty -ArgumentList @('-telnet', '127.0.0.1', '-P', $node.Telnet)
        Write-Ok "PuTTY opened for $($node.Name) (telnet 127.0.0.1:$($node.Telnet))"
    } else {
        Write-Warn 'PuTTY not found: opening a telnet window inside WSL instead (Ctrl+] then "quit" to close).'
        Start-Process -FilePath wsl.exe -ArgumentList @('-d', $script:DistroName, '-u', 'root', '--exec', 'telnet', '127.0.0.1', $node.Telnet)
    }
    if ($node.Kind -eq 'cisco_iol') { Write-Info 'IOL: press Enter in the window to get the prompt.' }
}

function Start-Capture([string]$Lab) {
    $ws = Find-Wireshark
    if (-not $ws) { Write-Bad 'Wireshark is not installed (https://www.wireshark.org/download.html).'; return }
    $links = @()
    foreach ($l in (Get-WslOutput @('/opt/netlab/wsl/capture.sh', 'links', $Lab))) {
        $f = $l -split "`t"
        if ($f.Count -eq 2) { $links += [pscustomobject]@{ A = $f[0]; B = $f[1] } }
    }
    if ($links.Count -eq 0) { Write-Bad 'No links found.'; return }
    $link = Select-FromList 'Capture which link?' $links { param($k) '{0,-20} <->  {1}' -f $k.A, $k.B }
    if ($null -eq $link) { return }
    # Capture on the A side of the link (both sides see the same packets).
    $node, $ifname = $link.A -split ':', 2
    $inner = "wsl.exe -d $($script:DistroName) -u root --exec /opt/netlab/wsl/capture.sh $Lab $node $ifname | `"$ws`" -k -i -"
    # cmd.exe pipes are binary-safe (a PowerShell 5.1 pipe would corrupt the pcap stream).
    Start-Process -FilePath cmd.exe -ArgumentList "/c `"$inner`"" -WindowStyle Minimized
    Write-Ok "Wireshark is starting on $($link.A) <-> $($link.B). Close Wireshark to stop the capture."
}

function Show-Report([string]$Lab) {
    New-Item -ItemType Directory -Force -Path (Join-Path $StateDir 'reports') | Out-Null
    $file = Join-Path $StateDir ("reports\$Lab-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt')
    $lines = Get-WslOutput @('/opt/netlab/wsl/lab.sh', 'report', $Lab)
    $hw = Get-HardwareInfo
    $vm = Get-Process -Name 'vmmemWSL', 'vmmem' -ErrorAction SilentlyContinue | Measure-Object -Property WorkingSet64 -Sum
    $lines += ''
    $lines += '==> Windows view'
    $lines += ('  Windows: {0} GB RAM total, {1} MB free, CPU: {2} ({3} threads)' -f $hw.TotalRamGB, $hw.FreeRamMB, $hw.CpuName, $hw.Threads)
    if ($vm.Count -gt 0) { $lines += ('  WSL VM process (vmmem): {0:N0} MB working set' -f ($vm.Sum / 1MB)) }
    $lines | ForEach-Object { Write-Host $_ }
    $lines | Set-Content -Path $file -Encoding UTF8
    Write-Ok "Saved to $file"
}

function Import-IolImage {
    Write-Info 'Tip: you can also drag an image file onto Import-Image.cmd.'
    $path = Read-Host 'Path of the IOL / IOL-L2 image (drag the file into this window, then Enter)'
    $path = $path.Trim().Trim('"')
    if (-not $path) { return }
    & "$PSScriptRoot\Import-Image.ps1" -Path $path -NoPause
}

function Show-Ksm {
    Invoke-Wsl @('/opt/netlab/wsl/ksm.sh', 'status')
    Write-Info 'KSM merges identical memory pages. It helps VM nodes (ASAv); IOL gains little.'
    $a = Read-Host 'on / off / Enter = leave as is'
    if ($a -eq 'on' -or $a -eq 'off') { Invoke-Wsl @('/opt/netlab/wsl/ksm.sh', $a) }
}

# ---------------------------------------------------------------- main
if (-not (Test-Distro $script:DistroName)) {
    Write-Bad "NetLab is not installed yet (no WSL distro '$($script:DistroName)'). Run Setup.cmd first."
    Pause-Menu
    exit 1
}

Write-Host 'Starting NetLab (copying the project files into WSL)...' -ForegroundColor Cyan
try { Sync-NetLab } catch { Write-Bad $_; Pause-Menu; exit 1 }
if ((Test-AnyLabRunning) -and -not (Test-KeepAlive)) { Start-KeepAlive }

$lab = Select-Lab
if (-not $lab) { exit 0 }

while ($true) {
    Write-Host ''
    Write-Host "NetLab - lab: $lab" -ForegroundColor Cyan
    Write-Host '  1) Deploy lab              2) Destroy lab           3) Status'
    Write-Host '  4) Show consoles           5) Open console (PuTTY)  6) Capture a link (Wireshark)'
    Write-Host '  7) Connectivity tests      8) Boot time and RAM report'
    Write-Host '  9) Import IOL image       10) KSM                  11) Choose another lab'
    Write-Host '  0) Exit'
    $c = Read-Host 'Choice'
    switch ($c) {
        '1'  { Invoke-Deploy $lab; Pause-Menu }
        '2'  { Invoke-Destroy $lab; Pause-Menu }
        '3'  { Invoke-Wsl @('/opt/netlab/wsl/lab.sh', 'status', $lab); Pause-Menu }
        '4'  { Invoke-Wsl @('/opt/netlab/wsl/lab.sh', 'consoles', $lab); Pause-Menu }
        '5'  { Open-Console $lab }
        '6'  { Start-Capture $lab }
        '7'  { Invoke-Wsl @('/opt/netlab/wsl/lab.sh', 'test', $lab); Pause-Menu }
        '8'  { Show-Report $lab; Pause-Menu }
        '9'  { Import-IolImage; Pause-Menu }
        '10' { Show-Ksm; Pause-Menu }
        '11' { $new = Select-Lab; if ($new) { $lab = $new } }
        '0'  {
            if (Test-AnyLabRunning) {
                Write-Info 'A lab is still running in the background (it keeps using RAM).'
                Write-Info 'Use "Destroy lab" when you are done to give the memory back.'
            }
            exit 0
        }
    }
}
