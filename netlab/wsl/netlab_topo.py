#!/usr/bin/env python3
"""Reads a containerlab topology file for the NetLab shell scripts.

    netlab_topo.py name     <topo.clab.yml>   lab name
    netlab_topo.py images   <topo.clab.yml>   images used (one per line)
    netlab_topo.py nodes    <topo.clab.yml>   name kind type image telnet-port ssh-port
    netlab_topo.py links    <topo.clab.yml>   nodeA:ifA nodeB:ifB
    netlab_topo.py estimate <topo.clab.yml> <settings.json> [<defaults.json>]
                                              estimated RAM in MB (used only for warnings)

Environment variables like ${NETLAB_IOL_IMAGE:=vrnetlab/cisco_iol:17.12.01}
are expanded the same way containerlab does it.
"""
import json
import os
import re
import sys

import yaml

# ${VAR}, ${VAR:=default}, ${VAR:-default}, ${VAR=default}, ${VAR-default}
_ENV = re.compile(r"\$\{(\w+)(?:(:?[-=])([^}]*))?\}")


def expand_env(text):
    def repl(m):
        name, op, default = m.group(1), m.group(2), m.group(3) or ""
        value = os.environ.get(name)
        if op is None:
            return value or ""
        if op.startswith(":"):          # ":-" / ":=" also replace an empty value
            return value if value else default
        return value if value is not None else default

    return _ENV.sub(repl, text)


def load(path):
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(expand_env(f.read())) or {}


def merged_nodes(topo):
    """Yields (name, settings) with kind-level and default settings merged in,
    the way containerlab does it (node > kind > defaults)."""
    t = topo.get("topology", {})
    defaults = t.get("defaults", {}) or {}
    kinds = t.get("kinds", {}) or {}
    for name, node in (t.get("nodes", {}) or {}).items():
        node = node or {}
        kind = node.get("kind", defaults.get("kind", "linux"))
        merged = dict(defaults)
        merged.update(kinds.get(kind, {}) or {})
        merged.update(node)
        merged["kind"] = kind
        yield name, merged


def published_ports(node):
    """Returns (telnet_port, ssh_port) published on the host, or '-'."""
    telnet = ssh = "-"
    for spec in node.get("ports", []) or []:
        parts = str(spec).split("/")[0].split(":")
        if len(parts) < 2:
            continue
        host_port, container_port = parts[-2], parts[-1]
        if container_port == "5000":
            telnet = host_port
        elif container_port == "22":
            ssh = host_port
    return telnet, ssh


def estimate_key(node):
    kind = node["kind"]
    if kind == "cisco_iol" and str(node.get("type", "")).upper() == "L2":
        return "cisco_iol_L2"
    return kind


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    cmd, path = argv[1], argv[2]
    topo = load(path)

    if cmd == "name":
        print(topo.get("name", ""))
    elif cmd == "images":
        for image in sorted({n.get("image", "") for _, n in merged_nodes(topo)} - {""}):
            print(image)
    elif cmd == "nodes":
        for name, n in merged_nodes(topo):
            telnet, ssh = published_ports(n)
            print("\t".join([name, n["kind"], str(n.get("type", "-")),
                             n.get("image", "-"), telnet, ssh]))
    elif cmd == "links":
        for link in topo.get("topology", {}).get("links", []) or []:
            eps = link.get("endpoints", [])
            if len(eps) == 2:
                print(f"{eps[0]}\t{eps[1]}")
    elif cmd == "estimate":
        estimates = {}
        for settings_file in reversed(argv[3:]):      # first file wins
            try:
                with open(settings_file, encoding="utf-8-sig") as f:
                    estimates.update(json.load(f).get("ram", {}).get("estimatesMB", {}))
            except (OSError, ValueError):
                pass
        default = int(estimates.get("default", 300))
        total = 0
        for _, n in merged_nodes(topo):
            total += int(estimates.get(estimate_key(n), default))
        print(total)
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
