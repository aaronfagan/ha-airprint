#!/usr/bin/env bash
set -euo pipefail

OPTIONS=/data/options.json
PRINTER_NAME=$(jq -r '.printer_name' "${OPTIONS}")
PRINTER_URI=$(jq -r '.printer_uri' "${OPTIONS}")
PRINTER_LOCATION=$(jq -r '.printer_location' "${OPTIONS}")
PRINTER_ICON=$(jq -r '.printer_icon // ""' "${OPTIONS}")
PPD=/usr/share/cups/model/CNRCUPSMF4800ZK.ppd

if [ -z "${PRINTER_ICON}" ] || [ ! -f "${PRINTER_ICON}" ]; then
	PRINTER_ICON=/usr/share/cups-airprint/printer.png
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
	echo "[cups-airprint] cupsd failed to start"
	exit 1
fi

lpadmin -p "${PRINTER_NAME}" \
	-v "${PRINTER_URI}" \
	-P "${PPD}" \
	-D "Canon MF4890DW" \
	-L "${PRINTER_LOCATION}" \
	-o printer-is-shared=true \
	-o printer-error-policy=retry-job \
	-E
lpadmin -d "${PRINTER_NAME}"
cupsctl --share-printers

mkdir -p /var/cache/cups/images
cp "${PRINTER_ICON}" "/var/cache/cups/images/${PRINTER_NAME}.png"

echo "[cups-airprint] queue ${PRINTER_NAME} -> ${PRINTER_URI}"
lpstat -t || true

wait "${CUPSD_PID}"
