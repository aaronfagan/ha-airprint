#!/usr/bin/env bash
set -uo pipefail

devices() {
	lpinfo -l -v 2>/dev/null | awk '
		/^Device: uri = socket:\/\// { ip=$4; sub("socket://","",ip); sub(":.*","",ip); model=""; id=""; next }
		/make-and-model =/ && ip != "" { model=$0; sub(/^[[:space:]]*make-and-model = /,"",model); next }
		/device-id =/ && ip != "" {
			id=$0; sub(/^[[:space:]]*device-id = /,"",id)
			print ip "\t" model "\t" id
			ip=""; model=""; id=""
		}
	'
}

DEVICES=$(devices)
for _ in 1 2 3; do
	[ -n "${DEVICES}" ] && break
	sleep 3
	DEVICES=$(devices)
done

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

FOUND="[]"
SEEN=""

while IFS=';' read -r _ _ _ SERVICE _ _ _ IP _ _; do
	[ -n "${SERVICE}" ] || continue
	ROW=$(printf '%s\n' "${DEVICES}" | awk -F'\t' -v ip="${IP}" '$1 == ip { print; exit }')
	MODEL=$(printf '%s' "${ROW}" | cut -f2)
	DEVICE_ID=$(printf '%s' "${ROW}" | cut -f3)
	[ -n "${MODEL}" ] || MODEL="${SERVICE}"
	DRIVER=$(driver_for "${DEVICE_ID}" "${MODEL}")
	FOUND=$(printf '%s' "${FOUND}" | jq -c \
		--arg device "dnssd://${SERVICE}._pdl-datastream._tcp.local/" \
		--arg name "${MODEL}" --arg address "${IP}" --arg id "${DEVICE_ID}" --arg driver "${DRIVER}" \
		'. + [{device:$device, name:$name, address:$address, device_id:$id, driver:$driver}]')
	SEEN="${SEEN} ${IP}"
done < <(timeout 6 avahi-browse -rtp _pdl-datastream._tcp 2>/dev/null | grep '^=' | grep ';IPv4;')

while IFS=$'\t' read -r IP MODEL DEVICE_ID; do
	[ -n "${IP}" ] || continue
	case " ${SEEN} " in
	*" ${IP} "*) continue ;;
	esac
	DRIVER=$(driver_for "${DEVICE_ID}" "${MODEL}")
	FOUND=$(printf '%s' "${FOUND}" | jq -c \
		--arg device "socket://${IP}" --arg name "${MODEL}" \
		--arg address "${IP}" --arg id "${DEVICE_ID}" --arg driver "${DRIVER}" \
		'. + [{device:$device, name:$name, address:$address, device_id:$id, driver:$driver}]')
done <<<"${DEVICES}"

printf '%s' "${FOUND}" | jq -c 'unique_by(.device)'
