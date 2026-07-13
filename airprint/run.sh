#!/usr/bin/env bash
set -euo pipefail

OPTIONS=/data/options.json
QUEUES=/tmp/airprint-queues
STATUS_DIR=/srv
ICON=/usr/share/airprint/printer.png

driver_for() {
	local device_id=$1 model=$2 driver=""

	if [ -n "${device_id}" ]; then
		driver=$(lpinfo --device-id "${device_id}" -m 2>/dev/null | awk 'NR == 1 { print $1 }')
	fi

	if [ -z "${driver}" ] && [ -n "${model}" ]; then
		driver=$(lpinfo --make-and-model "${model}" -m 2>/dev/null | awk 'NR == 1 { print $1 }')
	fi

	printf '%s' "${driver}"
}

/drivers.sh

pkill -x cupsd 2>/dev/null && sleep 2
rm -f /run/cups/cupsd.pid

install -m 0644 /usr/share/airprint/cupsd.conf /etc/cups/cupsd.conf

if grep -q '^SystemGroup' /etc/cups/cups-files.conf 2>/dev/null; then
	sed -i 's/^SystemGroup.*/SystemGroup root lpadmin/' /etc/cups/cups-files.conf
else
	echo 'SystemGroup root lpadmin' >> /etc/cups/cups-files.conf
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

mkdir -p "${STATUS_DIR}"
echo '{"printers":[],"discovered":[],"slug":""}' > "${STATUS_DIR}/status.json"
: > "${QUEUES}"

COUNT=$(jq '.printers | length' "${OPTIONS}")
if [ "${COUNT}" -eq 0 ]; then
	echo "[airprint] no printers configured yet — add one in Home Assistant"
fi

FOUND=$(/discover.sh)

for i in $(seq 0 $((COUNT - 1))); do
	NAME=$(jq -r ".printers[${i}].name" "${OPTIONS}")
	DEVICE=$(jq -r ".printers[${i}].device // .printers[${i}].address // \"\"" "${OPTIONS}")
	LOCATION=$(jq -r ".printers[${i}].location // \"\"" "${OPTIONS}")
	PRINTER_ICON=$(jq -r ".printers[${i}].icon // \"\"" "${OPTIONS}")

	QUEUE=$(printf '%s' "${NAME}" | tr -cs 'A-Za-z0-9_-' '_' | sed -e 's/^_*//' -e 's/_*$//')
	if [ -z "${QUEUE}" ]; then
		echo "[airprint] skipping printer ${i}: the name needs letters or numbers"
		continue
	fi

	if [ -z "${DEVICE}" ]; then
		DEVICE=$(printf '%s' "${FOUND}" | jq -r '.[0].device // ""')
	elif ! printf '%s' "${DEVICE}" | grep -q '://'; then
		DEVICE="socket://${DEVICE}"
	fi

	if [ -z "${DEVICE}" ]; then
		echo "[airprint] skipping ${NAME}: no printer found on the network"
		continue
	fi

	DEVICE_ID=$(printf '%s' "${FOUND}" | jq -r --arg d "${DEVICE}" '.[] | select(.device == $d) | .device_id // ""' | head -1)
	MODEL=$(printf '%s' "${FOUND}" | jq -r --arg d "${DEVICE}" '.[] | select(.device == $d) | .name // ""' | head -1)

	DRIVER=$(driver_for "${DEVICE_ID}" "${MODEL}")

	if [ -z "${PRINTER_ICON}" ]; then
		LABEL="${NAME}"
	else
		LABEL="${PRINTER_ICON} ${NAME}"
	fi


	if [ -z "${DRIVER}" ]; then
		echo "[airprint] ${NAME}: no driver — add one in the add-on's Drivers option"
		printf '%s\t%s\t%s\t%s\n' "${QUEUE}" "${DEVICE}" "${LABEL}" "" >> "${QUEUES}"
		continue
	fi

	echo "[airprint] ${NAME}: driver ${DRIVER}"

	if ! lpadmin -p "${QUEUE}" \
		-v "${DEVICE}" \
		-m "${DRIVER}" \
		-D "${LABEL}" \
		-L "${LOCATION}" \
		-o printer-is-shared=true \
		-o printer-error-policy=retry-job \
		-E; then
		echo "[airprint] skipping ${NAME}: could not create the print queue"
		continue
	fi

	mkdir -p /var/cache/cups/images
	cp "${ICON}" "/var/cache/cups/images/${QUEUE}.png"

	printf '%s\t%s\t%s\t%s\n' "${QUEUE}" "${DEVICE}" "${LABEL}" "${DRIVER}" >> "${QUEUES}"
	echo "[airprint] ${LABEL} -> ${DEVICE}"
done

cupsctl --share-printers

/monitor.sh &
python3 -m http.server 8099 --directory /srv --bind 0.0.0.0 >/dev/null 2>&1 &
avahi-publish -s "AirPrint add-on" _airprint-status._tcp 8099 >/dev/null 2>&1 &

wait "${CUPSD_PID}"
