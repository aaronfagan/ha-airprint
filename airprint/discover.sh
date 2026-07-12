#!/usr/bin/env bash
set -uo pipefail

models() {
	lpinfo -l -v 2>/dev/null | awk '
		/^Device: uri = socket:\/\// { ip=$4; sub("socket://","",ip); sub(":.*","",ip); next }
		/make-and-model =/ && ip != "" { line=$0; sub(/^[[:space:]]*make-and-model = /,"",line); print ip "\t" line; ip="" }
	'
}

MODELS=$(models)
for _ in 1 2 3; do
	[ -n "${MODELS}" ] && break
	sleep 3
	MODELS=$(models)
done

FOUND="[]"
SEEN=""

while IFS=';' read -r _ _ _ SERVICE _ _ _ IP _ _; do
	[ -n "${SERVICE}" ] || continue
	MODEL=$(printf '%s\n' "${MODELS}" | awk -F'\t' -v ip="${IP}" '$1 == ip { print $2; exit }')
	[ -n "${MODEL}" ] || MODEL="${SERVICE}"
	FOUND=$(printf '%s' "${FOUND}" | jq -c \
		--arg device "dnssd://${SERVICE}._pdl-datastream._tcp.local/" \
		--arg name "${MODEL}" --arg address "${IP}" \
		'. + [{device:$device, name:$name, address:$address}]')
	SEEN="${SEEN} ${IP}"
done < <(timeout 6 avahi-browse -rtp _pdl-datastream._tcp 2>/dev/null | grep '^=' | grep ';IPv4;')

while IFS=$'\t' read -r IP MODEL; do
	[ -n "${IP}" ] || continue
	case " ${SEEN} " in
	*" ${IP} "*) continue ;;
	esac
	FOUND=$(printf '%s' "${FOUND}" | jq -c \
		--arg device "socket://${IP}" --arg name "${MODEL}" --arg address "${IP}" \
		'. + [{device:$device, name:$name, address:$address}]')
done <<<"${MODELS}"

printf '%s' "${FOUND}" | jq -c 'unique_by(.device)'
