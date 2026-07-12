#!/usr/bin/env bash
set -euo pipefail

OPTIONS=/data/options.json
QUEUES=/tmp/airprint-queues
STATUS_DIR=/srv
ICON=/usr/share/airprint/printer.png
PPD=/usr/share/cups/model/CNRCUPSMF4800ZK.ppd

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

for i in $(seq 0 $((COUNT - 1))); do
	NAME=$(jq -r ".printers[${i}].name" "${OPTIONS}")
	DEVICE=$(jq -r ".printers[${i}].device // .printers[${i}].address // \"\"" "${OPTIONS}")
	LOCATION=$(jq -r ".printers[${i}].location // \"\"" "${OPTIONS}")
	EMOJI=$(jq -r ".printers[${i}].emoji // \"\"" "${OPTIONS}")

	QUEUE=$(printf '%s' "${NAME}" | tr -cs 'A-Za-z0-9_-' '_' | sed -e 's/^_*//' -e 's/_*$//')
	if [ -z "${QUEUE}" ]; then
		echo "[airprint] skipping printer ${i}: the name needs letters or numbers"
		continue
	fi

	if [ -z "${DEVICE}" ]; then
		DEVICE=$(/discover.sh | jq -r '.[0].device // ""')
	elif ! printf '%s' "${DEVICE}" | grep -q '://'; then
		DEVICE="socket://${DEVICE}"
	fi

	if [ -z "${DEVICE}" ]; then
		echo "[airprint] skipping ${NAME}: no printer found on the network"
		continue
	fi

	if [ -z "${EMOJI}" ]; then
		LABEL="${NAME}"
	else
		LABEL="${EMOJI} ${NAME}"
	fi

	lpadmin -p "${QUEUE}" \
		-v "${DEVICE}" \
		-P "${PPD}" \
		-D "${LABEL}" \
		-L "${LOCATION}" \
		-o printer-is-shared=true \
		-o printer-error-policy=retry-job \
		-E

	mkdir -p /var/cache/cups/images
	cp "${ICON}" "/var/cache/cups/images/${QUEUE}.png"

	printf '%s\t%s\t%s\n' "${QUEUE}" "${DEVICE}" "${LABEL}" >> "${QUEUES}"
	echo "[airprint] ${LABEL} -> ${DEVICE}"
done

cupsctl --share-printers

/monitor.sh &
python3 -m http.server 8099 --directory /srv --bind 0.0.0.0 >/dev/null 2>&1 &
avahi-publish -s "AirPrint add-on" _airprint-status._tcp 8099 >/dev/null 2>&1 &

wait "${CUPSD_PID}"
