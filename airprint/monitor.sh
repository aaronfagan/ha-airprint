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

	while IFS=$'\t' read -r QUEUE DEVICE LABEL; do
		[ -n "${QUEUE}" ] || continue
		CONFIGURED="${CONFIGURED} ${DEVICE}"

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

		PRINTERS=$(printf '%s' "${PRINTERS}" | jq -c \
			--arg id "${QUEUE}" --arg name "${LABEL}" --arg host "${HOST}" \
			--argjson online "${ONLINE}" --argjson problem "${PROBLEM}" --argjson jobs "${JOBS}" \
			'. + [{id:$id, name:$name, host:$host, online:$online, problem:$problem, jobs:$jobs}]')

		if [ "${PROBLEM}" = "true" ] && [ "${JOBS}" -gt 0 ]; then
			if ! grep -qx "stuck_${QUEUE}" "${NOTIFIED}"; then
				echo "stuck_${QUEUE}" >> "${NOTIFIED}"
				notify "Printer not accepting jobs" \
					"**${LABEL}** is on the network but refusing print jobs, and ${JOBS} job(s) are waiting. It is usually out of paper, jammed, or showing an error." \
					"stuck_${QUEUE}"
			fi
		elif [ "${PROBLEM}" = "false" ]; then
			sed -i "/^stuck_${QUEUE}$/d" "${NOTIFIED}"
		fi
	done < "${QUEUES}"

	FOUND=$(/discover.sh)
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
