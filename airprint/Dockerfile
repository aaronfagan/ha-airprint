FROM debian:bookworm-slim

ARG CANON_URL="https://gdlp01.c-wss.com/gds/0/0100009240/41/linux-UFRII-drv-v630-m17n-10.tar.gz"
ARG CANON_DEB="linux-UFRII-drv-v630-m17n/x64/Debian/cnrdrvcups-ufr2-uk_6.30-1.10_amd64.deb"

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      avahi-daemon \
      ca-certificates \
      cups \
      cups-bsd \
      cups-client \
      cups-filters \
      curl \
      dbus \
      jq \
 && curl -fsSL -o /tmp/canon.tar.gz "${CANON_URL}" \
 && tar xzf /tmp/canon.tar.gz -C /tmp \
 && apt-get install -y --no-install-recommends "/tmp/${CANON_DEB}" \
 && test -f /usr/share/cups/model/CNRCUPSMF4800ZK.ppd \
 && test -x /usr/lib/cups/filter/rastertoufr2 \
 && apt-get purge -y curl \
 && apt-get autoremove -y \
 && rm -rf /tmp/canon.tar.gz /tmp/linux-UFRII-drv-v630-m17n /var/lib/apt/lists/*

COPY cupsd.conf /etc/cups/cupsd.conf
COPY avahi-daemon.conf /etc/avahi/avahi-daemon.conf
COPY printer.png /usr/share/airprint/printer.png
COPY run.sh /run.sh
RUN chmod +x /run.sh

CMD ["/run.sh"]
