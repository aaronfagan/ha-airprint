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

FOUND="[]"
SEEN=""

while IFS=';' read -r _ _ _ SERVICE _ _ _ IP _ _; do
	[ -n "${SERVICE}" ] || continue
	ROW=$(printf '%s\n' "${DEVICES}" | awk -F'\t' -v ip="${IP}" '$1 == ip { print; exit }')
	MODEL=$(printf '%s' "${ROW}" | cut -f2)
	DEVICE_ID=$(printf '%s' "${ROW}" | cut -f3)
	[ -n "${MODEL}" ] || MODEL="${SERVICE}"
	FOUND=$(printf '%s' "${FOUND}" | jq -c \
		--arg device "dnssd://${SERVICE}._pdl-datastream._tcp.local/" \
		--arg name "${MODEL}" --arg address "${IP}" --arg id "${DEVICE_ID}" \
		'. + [{device:$device, name:$name, address:$address, device_id:$id}]')
	SEEN="${SEEN} ${IP}"
done < <(timeout 6 avahi-browse -rtp _pdl-datastream._tcp 2>/dev/null | grep '^=' | grep ';IPv4;')

while IFS=$'\t' read -r IP MODEL DEVICE_ID; do
	[ -n "${IP}" ] || continue
	case " ${SEEN} " in
	*" ${IP} "*) continue ;;
	esac
	FOUND=$(printf '%s' "${FOUND}" | jq -c \
		--arg device "socket://${IP}" --arg name "${MODEL}" \
		--arg address "${IP}" --arg id "${DEVICE_ID}" \
		'. + [{device:$device, name:$name, address:$address, device_id:$id}]')
done <<<"${DEVICES}"

printf '%s' "${FOUND}" | jq -c 'unique_by(.device)'
