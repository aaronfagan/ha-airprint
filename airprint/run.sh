#!/usr/bin/env bash
set -euo pipefail

OPTIONS=/data/options.json
PRINTER_NAME=$(jq -r '.printer_name' "${OPTIONS}")
PRINTER_QUEUE=$(printf '%s' "${PRINTER_NAME}" | tr -c 'A-Za-z0-9_-' '_')
PRINTER_URI=$(jq -r '.printer_uri' "${OPTIONS}")
PRINTER_LOCATION=$(jq -r '.printer_location' "${OPTIONS}")
PRINTER_ICON=$(jq -r '.printer_icon // ""' "${OPTIONS}")
PPD=/usr/share/cups/model/CNRCUPSMF4800ZK.ppd

if [ -z "${PRINTER_ICON}" ] || [ ! -f "${PRINTER_ICON}" ]; then
	PRINTER_ICON=/usr/share/airprint/printer.png
fi

mkdir -p /run/dbus
rm -f /run/dbus/pid
dbus-daemon --system --fork

avahi-daemon --daemonize --no-chroot

cupsd -f &
CUPSD_PID=$!

for _ in $(seq 1 60); do
	if lpstat -r 2>/dev/null | grep -q "is running"; then
		break
	fi
	sleep 1
done

if ! lpstat -r 2>/dev/null | grep -q "is running"; then
	echo "[airprint] cupsd failed to start"
	exit 1
fi

lpadmin -p "${PRINTER_QUEUE}" \
	-v "${PRINTER_URI}" \
	-P "${PPD}" \
	-D "${PRINTER_NAME}" \
	-L "${PRINTER_LOCATION}" \
	-o printer-is-shared=true \
	-o printer-error-policy=retry-job \
	-E
lpadmin -d "${PRINTER_QUEUE}"
cupsctl --share-printers

mkdir -p /var/cache/cups/images
cp "${PRINTER_ICON}" "/var/cache/cups/images/${PRINTER_QUEUE}.png"

echo "[airprint] queue ${PRINTER_QUEUE} (${PRINTER_NAME}) -> ${PRINTER_URI}"
echo "[airprint] icon ${PRINTER_ICON}"

wait "${CUPSD_PID}"
