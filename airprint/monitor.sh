#!/usr/bin/env bash
set -uo pipefail

QUEUES=/tmp/airprint-queues
NOTIFIED=/tmp/airprint-notified
STATUS=/srv/status.json
CORE=http://supervisor/core/api
INTERVAL=60

touch "${NOTIFIED}"
mkdir -p /srv

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

while true; do
	CONFIGURED_HOSTS=""
	PRINTERS="[]"

	while IFS=$'\t' read -r QUEUE HOST PORT LABEL; do
		[ -n "${QUEUE}" ] || continue
		CONFIGURED_HOSTS="${CONFIGURED_HOSTS} ${HOST}"

		if port_open "${HOST}" "${PORT}"; then
			ACCEPTING=true
			ONLINE=true
		else
			ACCEPTING=false
			if port_open "${HOST}" 80 || ping -c1 -W2 "${HOST}" >/dev/null 2>&1; then
				ONLINE=true
			else
				ONLINE=false
			fi
		fi

		if [ "${ONLINE}" = "true" ] && [ "${ACCEPTING}" = "false" ]; then
			PROBLEM=true
		else
			PROBLEM=false
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
					"**${LABEL}** is powered on but refusing print jobs, and ${JOBS} job(s) are waiting. It is usually out of paper, jammed, or showing an error." \
					"stuck_${QUEUE}"
			fi
		elif [ "${PROBLEM}" = "false" ]; then
			sed -i "/^stuck_${QUEUE}$/d" "${NOTIFIED}"
		fi
	done < "${QUEUES}"

	DISCOVERED="[]"
	for URI in $(lpinfo -v 2>/dev/null | awk '/^network socket:\/\/[0-9]/ {print $2}'); do
		IP=${URI#socket://}
		IP=${IP%%:*}
		case " ${CONFIGURED_HOSTS} " in
		*" ${IP} "*) continue ;;
		esac
		DISCOVERED=$(printf '%s' "${DISCOVERED}" | jq -c --arg ip "${IP}" '. + [$ip]')
		grep -qx "new_${IP}" "${NOTIFIED}" && continue
		echo "new_${IP}" >> "${NOTIFIED}"
		notify "New printer found" \
			"A printer at **${IP}** is on your network but is not set up. Add it under Settings → Devices & Services → AirPrint → Configure." \
			"new_${IP//./_}"
	done

	SLUG=$(curl -sS -m 10 -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" http://supervisor/addons/self/info 2>/dev/null | jq -r '.data.slug // ""')

	jq -nc --argjson printers "${PRINTERS}" --argjson discovered "${DISCOVERED}" --arg slug "${SLUG}" \
		'{printers:$printers, discovered:$discovered, slug:$slug}' > "${STATUS}.tmp"
	mv "${STATUS}.tmp" "${STATUS}"

	sleep "${INTERVAL}"
done
