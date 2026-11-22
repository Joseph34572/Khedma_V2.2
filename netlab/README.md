# NetLab

A local network lab for CCNA/CCNP study on Windows: real Cisco IOS (IOL) routers
and switches, a Linux firewall, Linux and Windows-like PCs, a telnet console
per node for PuTTY, and live Wireshark capture on any link. The engine is
Docker Engine + containerlab inside a dedicated WSL 2 distro, without Docker
Desktop.

> **Status: Phase 1 (proof of concept, no GUI).** Scripts, node images and two
> sample labs. Phase 2 (backend API), Phase 3 (GUI) and Phase 4 (installer)
> come later. See [docs/PHASE1-REPORT.md](docs/PHASE1-REPORT.md).

## Quick start (Windows)

Double-click these files in the `netlab` folder, in this order:

| Step | File | What it does |
|---|---|---|
| 1 | `Check-Environment.cmd` | Read-only check: Windows build, AMD-V/SVM, RAM, SSD/HDD, WSL, Wireshark, PuTTY. Saves `state\environment-report.txt`. |
| 2 | `Setup.cmd` | One-time setup. **Asks before every change.** It installs/updates WSL if needed, chooses folders (SSD/HDD), proposes a `.wslconfig` (backed up first), creates the `NetLab` distro (Ubuntu 24.04), installs Docker Engine + containerlab + vrnetlab, and builds the node images. |
| 3 | `NetLab.cmd` | Menu: deploy/destroy a lab, open consoles in PuTTY, capture a link in Wireshark, connectivity tests, boot-time and RAM report. Start with the **smoke** lab: it needs no Cisco image. |
| 4 | `Import-Image.cmd` | Drag your IOL or IOL-L2 file onto it. It is built with vrnetlab and the **phase1** lab can then run. |

You also need [Wireshark](https://www.wireshark.org/download.html) for captures
and [PuTTY](https://www.putty.org) for consoles. Without PuTTY, consoles open in
a WSL telnet window.

### Cisco images

NetLab never downloads or bundles Cisco images. IOL and IOL-L2 come with
Cisco Modeling Labs (CML, including the free CML-Free tier) in the
"reference platform" ISO:

- CML 2.9 and older: `x86_64_crb_linux-adventerprisek9-ms` (IOL) and
  `x86_64_crb_linux_l2-adventerprisek9-ms` (IOL-L2).
- CML 2.10 and newer: `iol-xe-17-18-02.tar.gz` / `ioll2-xe-17-18-02.tar.gz`.

`Import-Image.cmd` detects the L2/L3 type and the IOS version, and builds
`vrnetlab/cisco_iol:<version>` or `vrnetlab/cisco_iol:L2-<version>`. Labs then
use the image you built.

## The sample labs

**phase1**: 3 routers running OSPF, an IOL-L2 switch with 2 VLANs and a trunk,
a firewall and 2 PCs, plus a tiny "Internet" web server behind the firewall.
The diagram and addressing are at the top of
[labs/phase1/phase1.clab.yml](labs/phase1/phase1.clab.yml).

**smoke**: firewall, Linux PC, Windows PC and web server, with no Cisco nodes.
Use it to test the whole tool chain first.

### Consoles

Each node publishes its console (container port 5000) and SSH (port 22) on
`127.0.0.1` only, so nothing is reachable from your LAN.

| Node (phase1) | PuTTY: Telnet, 127.0.0.1, port | SSH (port) | Login |
|---|---|---|---|
| R1 / R2 / R3 | 5001 / 5002 / 5003 | 2201 / 2202 / 2203 | `admin` / `admin` |
| SW1 | 5004 | 2204 | `admin` / `admin` |
| FW1 (firewall CLI) | 5005 | 2205 | `root` / `netlab` |
| PC1 (Linux) | 5006 | 2206 | `root` / `netlab` |
| PC2 (Windows-like) | 5007 | 2207 | `root` / `netlab` |
| SRV1 | 5008 | 2208 | `root` / `netlab` |

The IOL console is the real IOS console (served by vrnetlab's iouyap on port
5000), so you see boot messages and can recover a node with a broken
configuration. Press Enter to get the prompt.

### Windows PC commands

PC2 runs `winsh`, a CMD-like shell: `ipconfig [/all | /release | /renew |
/flushdns]`, `ping [-t] [-n] [-l] [-w] [-i]`, `tracert`, `arp -a/-d/-s`,
`nslookup`, `netstat [-a] [-r]`, `route print/add/delete`,
`netsh interface ip set address/dns ... static|dhcp`, `netsh interface ip show config`,
`hostname`, `cls`, `telnet`, `ssh`, `curl`, `help`. The output follows the
Windows layout, including APIPA (169.254.x.y) when DHCP fails, and Ctrl+C
stops `ping -t`.

### Firewall CLI

FW1's console opens `fw`, a small Cisco-like CLI on top of nftables. It has
zones, numbered permit/deny rules, stateful inspection and NAT:

```
FW1# show rules
FW1# rule 15 deny tcp from inside to outside port 23
FW1# no rule 15
FW1# show conn
FW1# write
```

Type `?` for the full syntax. `shell` opens bash, where `nft list ruleset`
shows the generated rules.

## How it fits together

```
Windows                                   WSL 2 distro "NetLab" (Ubuntu, on the SSD)
-------                                   -------------------------------------------
NetLab.cmd / Setup.cmd (PowerShell) --->  /opt/netlab/wsl/*.sh   (copied from this folder)
                                          Docker Engine + containerlab
PuTTY  -- telnet 127.0.0.1:50xx ------->  docker-proxy -> node:5000 (console)
Wireshark <- pcap over a cmd.exe pipe --  ip netns exec <node> tcpdump -w - (on the veth)
```

- **Docker Engine inside WSL, not Docker Desktop**, which saves 1-2 GB of RAM.
- **Nothing reserves RAM.** No container has a memory reservation. The
  `.wslconfig` values are upper limits, and `autoMemoryReclaim` returns unused
  memory to Windows. The RAM figures in `config/settings.json` are only used
  to warn before a deploy.
- **WSL stays up only while a lab runs.** The menu starts a hidden keep-alive
  after a deploy and stops it after a destroy. WSL then shuts down and gives
  all its memory back.
- **All limits come from `config/settings.json`** (created from
  `settings.default.json` on first run) or from detected hardware: WSL memory,
  parallel boot (`deploy.maxWorkers`, 0 = one per CPU thread), RAM estimates,
  test retries.
- **Runtime state stays inside WSL.** A deploy copies the lab template to
  `/var/lib/netlab/labs/<lab>` and runs it there, so a running lab never
  depends on files on a Windows drive.

### Project layout

```
netlab/
  Setup.cmd  NetLab.cmd  Import-Image.cmd  Check-Environment.cmd
  config/settings.default.json   every tunable value (copied to settings.json)
  windows/                       PowerShell 5.1 scripts behind the .cmd files
  wsl/                           scripts run inside the NetLab distro
    install-engine.sh            Docker Engine + containerlab + vrnetlab
    build-images.sh              NetLab node images
    import-iol.sh                Cisco IOL/IOL-L2 -> vrnetlab image
    lab.sh                       list/plan/deploy/destroy/status/consoles/test/report
    capture.sh  stats.sh  ksm.sh  sync.sh  keepalive.sh  netlab_topo.py
  images/                        Dockerfiles of the small nodes
    base/      Alpine + console (telnetd :5000) + SSH + DHCP helpers
    linux-pc/  win-pc/ (winsh)   linux-fw/ (fw CLI, nftables)
  labs/phase1/  labs/smoke/      containerlab topologies, configs, tests.conf
  tests/                         offline tests for winsh and fw (bash, mocked tools)
  docs/PHASE1-REPORT.md
```

### Tests

`bash tests/test_winsh.sh` and `bash tests/test_fw.sh` check the Windows shell
and the firewall CLI without Docker. They use mocked network tools and run
on any Linux, including inside the NetLab distro. Inside a running lab,
`lab.sh test <lab>` (menu item 7) runs the real end-to-end tests from the
lab's `tests.conf`.

## Decisions for later phases (recorded now)

- **Desktop packaging: Tauri, not Electron.** Tauri uses Windows' built-in
  WebView2 and needs about 30-80 MB of RAM. Electron ships a whole Chromium
  and needs 150 MB or more. RAM is the main constraint here.
- **The backend (Phase 2, FastAPI) will run inside the NetLab distro**, next
  to Docker. The GUI talks to it over HTTP on localhost. The same API can
  later run on another machine.
- **Device types will be plugins**: a template JSON (ports, interface naming,
  kind/type, RAM estimate, console method) plus an optional image builder.
  Phase 1 already avoids per-model code: the scripts read the topology, not
  a hard-coded node list.
- **Multi-host labs** stay possible: containerlab supports VXLAN links between
  hosts, and nothing in the scripts assumes a single host except the
  127.0.0.1 port publishing.
- **Phase 1 limitation**: console ports are written in each lab file, so two
  labs that use the same ports cannot run at the same time. Phase 2 will
  allocate ports from `settings.json`.
