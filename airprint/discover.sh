#!/usr/bin/env bash
set -uo pipefail

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

txt_value() {
	printf '%s' "$1" | grep -o "\"$2=[^\"]*\"" | head -1 | sed "s/^\"$2=//; s/\"\$//"
}

FOUND="[]"

while IFS=';' read -r _ _ _ SERVICE _ _ _ IP _ TXT; do
	[ -n "${SERVICE}" ] || continue

	MFG=$(txt_value "${TXT}" usb_MFG)
	MDL=$(txt_value "${TXT}" usb_MDL)

	MODEL="${MDL}"
	[ -n "${MODEL}" ] || MODEL=$(txt_value "${TXT}" ty)
	[ -n "${MODEL}" ] || MODEL=$(txt_value "${TXT}" product | tr -d '()')
	[ -n "${MODEL}" ] || MODEL="${SERVICE}"

	DEVICE_ID=""
	[ -n "${MFG}" ] && DEVICE_ID="MFG:${MFG};"
	[ -n "${MDL}" ] && DEVICE_ID="${DEVICE_ID}MDL:${MDL};"

	DRIVER=$(driver_for "${DEVICE_ID}" "${MODEL}")
	FOUND=$(printf '%s' "${FOUND}" | jq -c \
		--arg device "dnssd://${SERVICE}._pdl-datastream._tcp.local/" \
		--arg name "${MODEL}" --arg address "${IP}" --arg id "${DEVICE_ID}" --arg driver "${DRIVER}" \
		'. + [{device:$device, name:$name, address:$address, device_id:$id, driver:$driver}]')
done < <(timeout 6 avahi-browse -rtp _pdl-datastream._tcp 2>/dev/null | grep '^=' | grep ';IPv4;')

printf '%s' "${FOUND}" | jq -c 'unique_by(.device)'
