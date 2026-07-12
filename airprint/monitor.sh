#!/usr/bin/env bash
set -uo pipefail

QUEUES=/tmp/airprint-queues
NOTIFIED=/tmp/airprint-notified
CORE=http://supervisor/core/api
INTERVAL=60

touch "${NOTIFIED}"

MQTT_HOST=""
MQTT_PORT=""
MQTT_USER=""
MQTT_PASS=""

mqtt_discover() {
	local json
	json=$(curl -sS -m 10 -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" http://supervisor/services/mqtt 2>/dev/null) || return 1
	[ "$(printf '%s' "${json}" | jq -r '.result // "error"')" = "ok" ] || return 1
	MQTT_HOST=$(printf '%s' "${json}" | jq -r '.data.host // ""')
	MQTT_PORT=$(printf '%s' "${json}" | jq -r '.data.port // ""')
	MQTT_USER=$(printf '%s' "${json}" | jq -r '.data.username // ""')
	MQTT_PASS=$(printf '%s' "${json}" | jq -r '.data.password // ""')
	[ -n "${MQTT_HOST}" ]
}

mqtt_pub() {
	local topic=$1 payload=$2 retain=${3:-}
	local args=(-h "${MQTT_HOST}" -p "${MQTT_PORT}" -t "${topic}" -m "${payload}")
	[ -n "${MQTT_USER}" ] && args+=(-u "${MQTT_USER}" -P "${MQTT_PASS}")
	[ -n "${retain}" ] && args+=(-r)
	mosquitto_pub "${args[@]}" >/dev/null 2>&1 || true
}

core_post() {
	curl -sS -o /dev/null -m 10 \
		-H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
		-H "Content-Type: application/json" \
		-X POST -d "$2" "${CORE}/$1" || true
}

core_state() {
	core_post "states/$1" "$(jq -nc --arg s "$2" --argjson a "$3" '{state:$s, attributes:$a}')"
}

notify() {
	core_post "services/persistent_notification/create" \
		"$(jq -nc --arg t "$1" --arg m "$2" --arg i "airprint_$3" \
			'{title:$t, message:$m, notification_id:$i}')"
}

port_open() {
	timeout 4 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null
}

mqtt_config() {
	local slug=$1 label=$2
	local device
	device=$(jq -nc --arg id "airprint_${slug}" --arg n "${label}" \
		'{identifiers:[$id], name:$n, manufacturer:"AirPrint", model:"Network printer"}')

	mqtt_pub "homeassistant/binary_sensor/airprint_${slug}_online/config" "$(jq -nc \
		--arg n "Online" --arg uid "airprint_${slug}_online" \
		--arg st "airprint/${slug}/online" --argjson d "${device}" \
		'{name:$n, unique_id:$uid, state_topic:$st, device_class:"connectivity", payload_on:"ON", payload_off:"OFF", device:$d}')" retain

	mqtt_pub "homeassistant/binary_sensor/airprint_${slug}_problem/config" "$(jq -nc \
		--arg n "Problem" --arg uid "airprint_${slug}_problem" \
		--arg st "airprint/${slug}/problem" --argjson d "${device}" \
		'{name:$n, unique_id:$uid, state_topic:$st, device_class:"problem", payload_on:"ON", payload_off:"OFF", device:$d}')" retain

	mqtt_pub "homeassistant/sensor/airprint_${slug}_jobs/config" "$(jq -nc \
		--arg n "Queued jobs" --arg uid "airprint_${slug}_jobs" \
		--arg st "airprint/${slug}/jobs" --argjson d "${device}" \
		'{name:$n, unique_id:$uid, state_topic:$st, unit_of_measurement:"jobs", icon:"mdi:printer", device:$d}')" retain
}

if mqtt_discover; then
	echo "[airprint] publishing printer status to MQTT (${MQTT_HOST}:${MQTT_PORT})"
	USE_MQTT=1
else
	echo "[airprint] no MQTT broker, publishing printer status directly to Home Assistant"
	USE_MQTT=0
fi

CONFIGURED_ONCE=0

while true; do
	CONFIGURED_HOSTS=""

	while IFS=$'\t' read -r QUEUE HOST PORT LABEL; do
		[ -n "${QUEUE}" ] || continue
		CONFIGURED_HOSTS="${CONFIGURED_HOSTS} ${HOST}"
		SLUG=$(printf '%s' "${QUEUE}" | tr 'A-Z-' 'a-z_')

		if port_open "${HOST}" "${PORT}"; then
			ACCEPTING=1
			ONLINE=1
		else
			ACCEPTING=0
			if port_open "${HOST}" 80 || ping -c1 -W2 "${HOST}" >/dev/null 2>&1; then
				ONLINE=1
			else
				ONLINE=0
			fi
		fi

		if [ "${ONLINE}" = "1" ] && [ "${ACCEPTING}" = "0" ]; then
			PROBLEM=1
		else
			PROBLEM=0
		fi

		JOBS=$(lpstat -o "${QUEUE}" 2>/dev/null | grep -c . || true)

		if [ "${USE_MQTT}" = "1" ]; then
			if [ "${CONFIGURED_ONCE}" = "0" ]; then
				mqtt_config "${SLUG}" "${LABEL}"
			fi
			[ "${ONLINE}" = "1" ] && mqtt_pub "airprint/${SLUG}/online" "ON" || mqtt_pub "airprint/${SLUG}/online" "OFF"
			[ "${PROBLEM}" = "1" ] && mqtt_pub "airprint/${SLUG}/problem" "ON" || mqtt_pub "airprint/${SLUG}/problem" "OFF"
			mqtt_pub "airprint/${SLUG}/jobs" "${JOBS}"
		else
			[ "${ONLINE}" = "1" ] && S=on || S=off
			core_state "binary_sensor.airprint_${SLUG}_online" "${S}" \
				"$(jq -nc --arg n "${LABEL} online" '{friendly_name:$n, device_class:"connectivity"}')"
			[ "${PROBLEM}" = "1" ] && S=on || S=off
			core_state "binary_sensor.airprint_${SLUG}_problem" "${S}" \
				"$(jq -nc --arg n "${LABEL} problem" '{friendly_name:$n, device_class:"problem"}')"
			core_state "sensor.airprint_${SLUG}_jobs" "${JOBS}" \
				"$(jq -nc --arg n "${LABEL} queued jobs" '{friendly_name:$n, unit_of_measurement:"jobs", icon:"mdi:printer"}')"
		fi

		if [ "${PROBLEM}" = "1" ] && [ "${JOBS}" -gt 0 ]; then
			if ! grep -qx "stuck_${SLUG}" "${NOTIFIED}"; then
				echo "stuck_${SLUG}" >> "${NOTIFIED}"
				notify "Printer not accepting jobs" \
					"**${LABEL}** is powered on but refusing print jobs, and ${JOBS} job(s) are waiting. It is usually out of paper, jammed, or showing an error." \
					"stuck_${SLUG}"
			fi
		elif [ "${PROBLEM}" = "0" ]; then
			sed -i "/^stuck_${SLUG}$/d" "${NOTIFIED}"
		fi
	done < "${QUEUES}"

	CONFIGURED_ONCE=1

	for URI in $(lpinfo -v 2>/dev/null | awk '/^network socket:\/\/[0-9]/ {print $2}'); do
		IP=${URI#socket://}
		IP=${IP%%:*}
		case " ${CONFIGURED_HOSTS} " in
		*" ${IP} "*) continue ;;
		esac
		grep -qx "new_${IP}" "${NOTIFIED}" && continue
		echo "new_${IP}" >> "${NOTIFIED}"
		notify "New printer found" \
			"A printer at **${IP}** is on your network but is not set up. Add it under Settings → Apps → AirPrint → Configuration." \
			"new_${IP//./_}"
	done

	sleep "${INTERVAL}"
done
