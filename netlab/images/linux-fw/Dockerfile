# NetLab "Linux firewall": Alpine + nftables with a small Cisco-like CLI (fw).
# Zones, numbered permit/deny rules, stateful inspection and NAT (masquerade).
ARG BASE=netlab/base:1.0
FROM ${BASE}

RUN apk add --no-cache nftables conntrack-tools

COPY fw /usr/local/bin/fw
COPY fw-init /usr/local/sbin/fw-init
COPY fw.conf.default /etc/netlab/fw.conf
RUN chmod 755 /usr/local/bin/fw /usr/local/sbin/fw-init

# The console (telnet port 5000) opens the firewall CLI.
ENV NETLAB_CONSOLE_SHELL=/usr/local/bin/fw

CMD ["/usr/local/sbin/fw-init"]
