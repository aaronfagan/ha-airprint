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

COUNT=$(jq '.printers | length' "${OPTIONS}")
if [ "${COUNT}" -eq 0 ]; then
	echo "[airprint] no printers configured"
	exit 1
fi

DISCOVERED=$(lpinfo -v 2>/dev/null | awk '/^network socket:\/\/[0-9]/ {print $2}')
DISCOVERED_COUNT=$(printf '%s' "${DISCOVERED}" | grep -c . || true)

if [ -n "${DISCOVERED}" ]; then
	echo "[airprint] found on the network:"
	printf '%s\n' "${DISCOVERED}" | sed 's/^/[airprint]   /'
fi

: > "${QUEUES}"
mkdir -p "${STATUS_DIR}"
echo '{"printers":[],"discovered":[]}' > "${STATUS_DIR}/status.json"

CONFIGURED=0
for i in $(seq 0 $((COUNT - 1))); do
	NAME=$(jq -r ".printers[${i}].name" "${OPTIONS}")
	ADDRESS=$(jq -r ".printers[${i}].address // \"\"" "${OPTIONS}")
	LOCATION=$(jq -r ".printers[${i}].location // \"\"" "${OPTIONS}")
	EMOJI=$(jq -r ".printers[${i}].emoji // \"none\"" "${OPTIONS}")

	QUEUE=$(printf '%s' "${NAME}" | tr -cs 'A-Za-z0-9_-' '_' | sed -e 's/^_*//' -e 's/_*$//')
	if [ -z "${QUEUE}" ]; then
		echo "[airprint] skipping printer ${i}: name must contain letters or numbers"
		continue
	fi

	if [ "${EMOJI}" = "none" ] || [ -z "${EMOJI}" ]; then
		LABEL="${NAME}"
	else
		LABEL="${EMOJI} ${NAME}"
	fi

	if [ -z "${ADDRESS}" ]; then
		if [ "${DISCOVERED_COUNT}" -eq 1 ]; then
			URI="${DISCOVERED}"
		elif [ "${DISCOVERED_COUNT}" -eq 0 ]; then
			echo "[airprint] skipping ${NAME}: no printer found on the network, set an address"
			continue
		else
			echo "[airprint] skipping ${NAME}: ${DISCOVERED_COUNT} printers found, set an address to choose one"
			continue
		fi
	elif printf '%s' "${ADDRESS}" | grep -q '://'; then
		URI="${ADDRESS}"
	else
		URI="socket://${ADDRESS}"
	fi

	lpadmin -p "${QUEUE}" \
		-v "${URI}" \
		-P "${PPD}" \
		-D "${LABEL}" \
		-L "${LOCATION}" \
		-o printer-is-shared=true \
		-o printer-error-policy=retry-job \
		-E

	mkdir -p /var/cache/cups/images
	cp "${ICON}" "/var/cache/cups/images/${QUEUE}.png"

	HOST=${URI#*://}
	HOST=${HOST%%/*}
	PORT=${HOST##*:}
	if [ "${PORT}" = "${HOST}" ]; then
		PORT=9100
	fi
	HOST=${HOST%%:*}
	printf '%s\t%s\t%s\t%s\n' "${QUEUE}" "${HOST}" "${PORT}" "${LABEL}" >> "${QUEUES}"

	echo "[airprint] ${LABEL} -> ${URI}"
	CONFIGURED=$((CONFIGURED + 1))
done

if [ "${CONFIGURED}" -eq 0 ]; then
	echo "[airprint] no printers could be configured"
	exit 1
fi

cupsctl --share-printers

/monitor.sh &
python3 -m http.server 8099 --directory /srv --bind 0.0.0.0 >/dev/null 2>&1 &
avahi-publish -s "AirPrint add-on" _airprint-status._tcp 8099 >/dev/null 2>&1 &

wait "${CUPSD_PID}"
