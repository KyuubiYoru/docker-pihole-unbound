FROM pihole/pihole:2025.11.1
RUN apk update && apk add unbound bind-tools

COPY lighttpd-external.conf /etc/lighttpd/external.conf 
COPY unbound-pihole.conf /etc/unbound/unbound.conf.d/pi-hole.conf
COPY 99-edns.conf /etc/dnsmasq.d/99-edns.conf
RUN mkdir -p /etc/services.d/unbound

COPY custom-entrypoint.sh /custom-entrypoint.sh
COPY warm-cache.sh /usr/local/bin/warm-cache
RUN chmod +x /custom-entrypoint.sh /usr/local/bin/warm-cache

ENTRYPOINT ["/custom-entrypoint.sh"]

