#!/usr/bin/env bash
set -uo pipefail

QUEUES=/tmp/airprint-queues
NOTIFIED=/tmp/airprint-notified
STATUS=/srv/status.json
CORE=http://supervisor/core/api
INTERVAL=60

touch "${NOTIFIED}"

notify() {
	curl -sS -o /dev/null -m 10 \
		-H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
		-H "Content-Type: application/json" \
		-X POST -d "$(jq -nc --arg t "$1" --arg m "$2" --arg i "airprint_$3" \
			'{title:$t, message:$m, notification_id:$i}')" \
		"${CORE}/services/persistent_notification/create" || true
}

port_open() {
	timeout 4 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null
}

snmp() {
	snmpget -v1 -c public -t 2 -r 0 -Oqv "$1" "$2" 2>/dev/null | tr -d '"'
}

error_reasons() {
	local hex
	hex=$(snmpget -v1 -c public -t 2 -r 0 -Oqvx "$1" 1.3.6.1.2.1.25.3.5.1.2.1 2>/dev/null | tr -cd '0-9A-Fa-f')
	[ -n "${hex}" ] || return 0

	local bits=$((16#${hex:0:2}))
	local reasons=()

	((bits & 0x80)) && reasons+=("Paper low")
	((bits & 0x40)) && reasons+=("Out of paper")
	((bits & 0x20)) && reasons+=("Toner low")
	((bits & 0x10)) && reasons+=("Out of toner")
	((bits & 0x08)) && reasons+=("Door open")
	((bits & 0x04)) && reasons+=("Paper jam")
	((bits & 0x02)) && reasons+=("Offline")
	((bits & 0x01)) && reasons+=("Needs attention")

	printf '%s\n' "${reasons[@]}"
}

resolve() {
	case "$1" in
	dnssd://*)
		local service=${1#dnssd://}
		service=${service%%._*}
		timeout 6 avahi-browse -rtp _pdl-datastream._tcp 2>/dev/null |
			awk -F';' -v name="${service}" '$1 == "=" && $3 == "IPv4" && $4 == name { print $8 "\t" $9; exit }'
		;;
	socket://*)
		local hostport=${1#socket://}
		hostport=${hostport%%/*}
		local port=${hostport##*:}
		[ "${port}" = "${hostport}" ] && port=9100
		printf '%s\t%s\n' "${hostport%%:*}" "${port}"
		;;
	esac
}

while true; do
	PRINTERS="[]"
	CONFIGURED=""
	FOUND=$(/discover.sh)

	while IFS=$'\t' read -r QUEUE DEVICE LABEL DRIVER; do
		[ -n "${QUEUE}" ] || continue
		CONFIGURED="${CONFIGURED} ${DEVICE}"
		DRIVER=${DRIVER:-}

		IFS=$'\t' read -r HOST PORT < <(resolve "${DEVICE}")

		if [ -z "${HOST:-}" ]; then
			ONLINE=false
			PROBLEM=false
			HOST=""
		elif port_open "${HOST}" "${PORT}"; then
			ONLINE=true
			PROBLEM=false
		else
			ONLINE=true
			PROBLEM=true
		fi

		JOBS=$(lpstat -o "${QUEUE}" 2>/dev/null | grep -c . || true)
		MODEL=$(printf '%s' "${FOUND}" | jq -r --arg d "${DEVICE}" '.[] | select(.device == $d) | .name' | head -1)

		TONER=null
		SUPPLY=""
		PAGES=null
		REASONS="[]"

		if [ -n "${HOST}" ]; then
			SUPPLY=$(snmp "${HOST}" 1.3.6.1.2.1.43.11.1.1.6.1.1)
			LEVEL=$(snmp "${HOST}" 1.3.6.1.2.1.43.11.1.1.9.1.1)
			CAPACITY=$(snmp "${HOST}" 1.3.6.1.2.1.43.11.1.1.8.1.1)
			COUNT=$(snmp "${HOST}" 1.3.6.1.2.1.43.10.2.1.4.1.1)

			if [ -n "${LEVEL}" ] && [ -n "${CAPACITY}" ] && [ "${CAPACITY}" -gt 0 ] 2>/dev/null; then
				TONER=$((LEVEL * 100 / CAPACITY))
			fi
			[ -n "${COUNT}" ] && [ "${COUNT}" -ge 0 ] 2>/dev/null && PAGES=${COUNT}

			REASONS=$(error_reasons "${HOST}" | jq -Rc '[., inputs] | map(select(length > 0))' 2>/dev/null || echo '[]')
			[ -n "${REASONS}" ] || REASONS="[]"
		fi

		PRINTERS=$(printf '%s' "${PRINTERS}" | jq -c \
			--arg id "${QUEUE}" --arg device "${DEVICE}" --arg name "${LABEL}" --arg host "${HOST}" \
			--arg model "${MODEL}" --arg supply "${SUPPLY}" --arg driver "${DRIVER}" \
			--argjson online "${ONLINE}" --argjson problem "${PROBLEM}" --argjson jobs "${JOBS}" \
			--argjson toner "${TONER}" --argjson pages "${PAGES}" --argjson reasons "${REASONS}" \
			'. + [{id:$id, device:$device, name:$name, model:$model, driver:$driver, host:$host, online:$online, problem:$problem, jobs:$jobs, toner:$toner, supply:$supply, pages:$pages, reasons:$reasons}]')

		if [ -z "${DRIVER}" ]; then
			if ! grep -qx "nodriver_${QUEUE}" "${NOTIFIED}"; then
				echo "nodriver_${QUEUE}" >> "${NOTIFIED}"
				notify "Printer needs a driver" \
					"**${LABEL}** has no driver, so it cannot print. Add one in the AirPrint add-on's **Drivers** option — see the [README](https://github.com/aaronfagan/ha-airprint#drivers)." \
					"nodriver_${QUEUE}"
			fi
		else
			sed -i "/^nodriver_${QUEUE}$/d" "${NOTIFIED}"
		fi

		if [ "${PROBLEM}" = "true" ] && [ "${JOBS}" -gt 0 ]; then
			if ! grep -qx "stuck_${QUEUE}" "${NOTIFIED}"; then
				echo "stuck_${QUEUE}" >> "${NOTIFIED}"
				WHY=$(printf '%s' "${REASONS}" | jq -r 'join(", ")')
				[ -n "${WHY}" ] || WHY="It is usually out of paper, jammed, or showing an error"
				notify "Printer not accepting jobs" \
					"**${LABEL}** is refusing print jobs and ${JOBS} job(s) are waiting. ${WHY}." \
					"stuck_${QUEUE}"
			fi
		elif [ "${PROBLEM}" = "false" ]; then
			sed -i "/^stuck_${QUEUE}$/d" "${NOTIFIED}"
		fi
	done < "${QUEUES}"

	DISCOVERED="[]"

	while read -r ROW; do
		[ -n "${ROW}" ] || continue
		DEVICE=$(printf '%s' "${ROW}" | jq -r '.device')
		NAME=$(printf '%s' "${ROW}" | jq -r '.name')

		case " ${CONFIGURED} " in
		*" ${DEVICE} "*) continue ;;
		esac

		DISCOVERED=$(printf '%s' "${DISCOVERED}" | jq -c --argjson found "${ROW}" '. + [$found]')

		ID=$(printf '%s' "${DEVICE}" | tr -cs 'A-Za-z0-9' '_')
		grep -qx "new_${ID}" "${NOTIFIED}" && continue
		echo "new_${ID}" >> "${NOTIFIED}"
		notify "New printer found" \
			"**${NAME}** is on your network but is not set up. Add it under Settings → Devices & Services → AirPrint." \
			"new_${ID}"
	done < <(printf '%s' "${FOUND}" | jq -c '.[]')

	SLUG=$(curl -sS -m 10 -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" http://supervisor/addons/self/info 2>/dev/null | jq -r '.data.slug // ""')

	jq -nc --argjson printers "${PRINTERS}" --argjson discovered "${DISCOVERED}" --arg slug "${SLUG}" \
		'{printers:$printers, discovered:$discovered, slug:$slug}' > "${STATUS}.tmp"
	mv "${STATUS}.tmp" "${STATUS}"

	sleep "${INTERVAL}"
done
