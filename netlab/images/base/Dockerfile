# NetLab base image for the small Linux-based nodes (PCs and the Linux firewall).
#
# Alpine keeps it tiny (about 15 MB on disk, a few MB of RAM per running node).
# Nothing in here reserves memory; a node only uses what its processes need.
#
# What every node built on this image gets:
#   - a console on TCP port 5000 (busybox telnetd), published to 127.0.0.1:50xx
#   - SSH on port 22 (user root, password "netlab"), published to 127.0.0.1:22xx
#   - helper scripts in /usr/local/lib/netlab (wait for links, DHCP, ...)
FROM alpine:3.24

RUN apk add --no-cache \
        bash \
        busybox-extras \
        iproute2 \
        iputils-ping \
        openssh \
        tini \
    # Host keys are generated once at build time so nodes boot faster.
    # (All nodes share them; fine for a lab, never do this in production.)
    && ssh-keygen -A \
    && echo 'root:netlab' | chpasswd \
    # No "bracketed paste" control codes in consoles (cleaner PuTTY output).
    && echo 'set enable-bracketed-paste off' >> /etc/inputrc \
    && sed -i 's#^root:\(.*\):/bin/sh$#root:\1:/bin/bash#' /etc/passwd \
    && mkdir -p /run/netlab /etc/netlab

COPY sshd_config /etc/ssh/sshd_config
COPY common.sh netlab-console udhcpc.script /usr/local/lib/netlab/
COPY netlab-dhcp /usr/local/bin/netlab-dhcp
COPY banner /etc/netlab/banner
RUN chmod 755 /usr/local/lib/netlab/netlab-console /usr/local/lib/netlab/udhcpc.script \
              /usr/local/bin/netlab-dhcp

# tini is PID 1: it forwards stop signals and cleans up finished processes.
ENTRYPOINT ["/sbin/tini", "-g", "--"]
CMD ["/bin/bash"]
