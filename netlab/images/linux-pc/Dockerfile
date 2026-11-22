# NetLab "Linux PC": a tiny Alpine end device for labs.
# Tools: ping, traceroute, DHCP client (udhcpc), curl, ssh, nslookup, telnet,
#        a small web server (busybox httpd, enable with WEB=1).
ARG BASE=netlab/base:1.0
FROM ${BASE}

RUN apk add --no-cache curl

COPY netlab-init /usr/local/sbin/netlab-init
RUN chmod 755 /usr/local/sbin/netlab-init && mkdir -p /srv/www

CMD ["/usr/local/sbin/netlab-init"]
