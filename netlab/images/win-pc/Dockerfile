# NetLab "Windows PC": the Linux PC plus "winsh", a small CMD-like shell.
# winsh understands ipconfig, ping, tracert, arp, nslookup, netstat, route,
# netsh (basic), cls ... and prints Windows-style output.
# It is the console program and root's login shell (SSH lands in it too).
ARG BASE=netlab/linux-pc:1.0
FROM ${BASE}

COPY winsh /usr/local/bin/winsh
RUN chmod 755 /usr/local/bin/winsh \
    && echo /usr/local/bin/winsh >> /etc/shells \
    && sed -i 's#^\(root:.*:\)[^:]*$#\1/usr/local/bin/winsh#' /etc/passwd

# NETLAB_APIPA=1: use a 169.254.x.y address when DHCP fails, like Windows.
ENV NETLAB_CONSOLE_SHELL=/usr/local/bin/winsh \
    NETLAB_APIPA=1
