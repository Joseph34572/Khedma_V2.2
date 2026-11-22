# Phase 1 report: proof of concept

## What was built

| Phase 1 item | Where | State |
|---|---|---|
| Environment check (Windows build, AMD-V/SVM + BIOS steps, RAM, SSD/HDD, WSL, Docker Desktop, Wireshark, PuTTY) | `Check-Environment.cmd`, `windows/Check-Environment.ps1` | written, not run (no Windows here) |
| Dependency install, asking first: WSL, `.wslconfig` with backup, NetLab distro on the SSD, Docker Engine, containerlab, vrnetlab | `Setup.cmd`, `windows/Setup-NetLab.ps1`, `wsl/install-engine.sh` | written, not run |
| IOL / IOL-L2 image build with vrnetlab (auto-detects L2/L3 and version) | `Import-Image.cmd`, `wsl/import-iol.sh` | written, not run (no images yet) |
| Linux PC, Windows-like PC, Linux firewall images | `images/` | written; shell logic tested (see below), images not built |
| Sample lab: 3 routers OSPF + IOL-L2 switch (2 VLANs + trunk) + firewall + 2 PCs | `labs/phase1/` | written, not deployed |
| Telnet console per node for PuTTY (127.0.0.1:5001...) | lab files + `NetLab.cmd` item 5 | written, not run |
| Live Wireshark capture on any link | `wsl/capture.sh` + `NetLab.cmd` item 6 | written, not run |
| Boot time and RAM per node | `lab.sh deploy` / `lab.sh report`, `NetLab.cmd` item 8 | written; **no numbers yet** |

## What was verified, and how

I worked in a Linux cloud sandbox. It has no Windows, no WSL, no Docker daemon,
and I was not allowed to install packages there. So nothing was deployed, no
image was built and no PowerShell ran. What I could check:

- **Every shell script parses** (`bash -n` / `sh -n`).
- **The topology helper** (`wsl/netlab_topo.py`) reads both labs correctly:
  nodes, kinds, images, console/SSH ports, links, the RAM estimate, and the
  `${NETLAB_IOL_IMAGE:=...}` override.
- **winsh**: `tests/test_winsh.sh` runs 83 checks with mocked `ip`, `ping`,
  `traceroute`, `nslookup` and `netstat` that print the same formats as the
  real tools. It covers ipconfig (plain, /all, /release, /renew, errors),
  ping (replies, timeouts, unreachable, name + DNS suffix, bad options),
  tracert, arp, nslookup, netstat, route, netsh. All pass.
- **fw**: `tests/test_fw.sh` runs 40 checks: phase1 config loads, generated
  nftables rules, rule replace/delete/ordering, validation errors, rollback
  when nftables rejects a change, show rules/conn/interfaces, write. All pass.
- **Bugs found by the tests and fixed:** the firewall accepted `/33`
  prefixes and rejected `192.168.20.0/24` (a regex variable was being
  overwritten). winsh printed `Pinging r3` instead of `Pinging r3.lab`.

Facts the design depends on were checked in the current docs and source code,
not taken from memory:

- containerlab `cisco_iol`: image names, `type: L2`, interface aliases
  `Ethernet0/1` = `eth1`, `.partial` startup configs, admin/admin.
- The vrnetlab/iouyap source serves the real IOL console over telnet on
  container port 5000 to several clients at once. A published
  `127.0.0.1:5001:5000` port reaches it.
- WSL settings: `memory`, `swap` and `swapFile` live in `[wsl2]`;
  `autoMemoryReclaim` lives in `[experimental]` (values: disabled, gradual,
  dropCache); an idle distro stops after about 15 s.

## What I need you to run on your PC

1. `Check-Environment.cmd`, then send me `state\environment-report.txt`.
2. `Setup.cmd`. Answer the questions. If any step fails, send me the
   red/yellow text. This is the first time these PowerShell scripts run, so
   a small fix may be needed.
3. `NetLab.cmd`: choose **smoke**, then 1 (deploy), 7 (tests),
   5 (open PC2 in PuTTY, try `ipconfig /all`, `ping -t 203.0.113.10`, Ctrl+C),
   6 (capture PC1-FW1 in Wireshark while pinging) and 8 (report).
4. When you have IOL images: `Import-Image.cmd` (drag the file onto it), then
   do the same steps for **phase1**. Send me the report file from
   `state\reports\`: it holds boot time per node, RAM per node, WSL memory
   and Windows free RAM.

**No boot times or RAM figures are reported yet.** I can't measure them
without your PC. The RAM values in `config/settings.json`
(`ram.estimatesMB`, e.g. 350 MB per IOL node) are placeholders that only
drive the "will it fit" warning. containerlab's docs list 768 MB per IOL node
as a sizing guideline; I'll replace both with your measured numbers.

## Choices I made that you may want to change

1. **Project location**: this repository holds an unrelated Next.js app, so
   NetLab lives in its own `netlab/` folder and touches nothing else. Moving
   it to its own repository later is just moving the folder.
2. **SRV1 was added to the sample lab**: a 5 MB Linux "Internet" web
   server behind the firewall. Without something on the outside, the
   firewall would have nothing to filter or NAT. Remove it if you prefer the
   exact list.
3. **Ubuntu 24.04** for the NetLab distro (setting `wsl.baseImage`). It is
   the most proven base for Docker and containerlab.
4. **`.wslconfig`**: `memory` = total RAM - max(3 GB, 25%), which is 5 GB on
   your PC. `swap=2GB`, the swap file in the NetLab SSD folder, and
   `autoMemoryReclaim=gradual`. `processors` is not set, so WSL may use all 8
   threads but reserves none. Sparse VHD is **not** turned on because WSL
   itself has warned about data corruption with it.
5. **Keep-alive instead of `instanceIdleTimeout=-1`**: WSL stops when no lab
   runs, so all its RAM goes back to Windows.
6. **KSM** (`wsl/ksm.sh`, menu item 10) is off by default. It helps VM nodes
   such as ASAv. IOL routers don't offer their memory for merging, so the
   gain for IOL is small. IOL already shares the binary's code pages
   between routers. In Phase 2 I can try an opt-in for IOL (kernel ≥ 6.4)
   and measure it.
7. **Security**: all console and SSH ports bind to 127.0.0.1. Lab
   credentials are admin/admin (IOL) and root/netlab (Linux nodes). SSH
   from other machines needs a different bind address. That is a Phase 2
   setting.
8. **The phase1 lab uses default STP**, so the trunk to R1 takes about 30 s
   to forward after boot. PC2 may get its DHCP lease about 30 s late. The
   tests retry for 60 s.

## Not in Phase 1 (planned)

These are planned for Phases 2-4: start/stop a single node, save/load labs,
startup-config import/export per node, device templates, the API,
per-start hardware detection, the GUI with xterm.js consoles and live stats,
and the installer.
