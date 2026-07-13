#!/usr/bin/env bash
set -euo pipefail

# Pushes the working tree straight onto a Home Assistant box and rebuilds it,
# with no version bump and nothing published. This is the loop to develop in.
#
# The add-on is deployed as a *local* add-on: the image key is stripped, so the
# Supervisor builds it on the machine, and `ha apps rebuild` picks up changes
# without touching the version.
#
#   scripts/dev.sh            # add-on + integration, then restart Home Assistant
#   scripts/dev.sh addon      # add-on only
#   scripts/dev.sh integration # integration only (restarts Home Assistant)
#
# It reaches the Home Assistant VM through the Proxmox guest agent:
#   PVE_HOST  ssh alias of the Proxmox host   (default: pve)
#   HA_VMID   id of the Home Assistant VM     (default: 100)

cd "$(dirname "$0")/.."

PVE_HOST=${PVE_HOST:-pve}
HA_VMID=${HA_VMID:-100}
SLUG=local_airprint
WHAT=${1:-all}

guest() {
	ssh "${PVE_HOST}" "qm guest exec ${HA_VMID} --timeout ${2:-300} -- /bin/sh -c $(printf '%q' "$1")" |
		python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("out-data") or d.get("err-data") or "")'
}

send() {
	local archive=$1 destination=$2
	scp -q "${archive}" "${PVE_HOST}:/tmp/dev.tgz"
	ssh "${PVE_HOST}" "B64=\$(base64 -w0 < /tmp/dev.tgz); qm guest exec ${HA_VMID} --timeout 120 -- /bin/sh -c \"echo \$B64 | base64 -d > /tmp/dev.tgz && tar xzf /tmp/dev.tgz -C ${destination} && chown -R root:root ${destination} && rm -f /tmp/dev.tgz\"" >/dev/null
}

if [ "${WHAT}" = "all" ] || [ "${WHAT}" = "addon" ]; then
	echo "==> add-on"

	work=$(mktemp -d)
	cp -R airprint "${work}/airprint"

	# a local add-on is built on the box; a published image would be pulled instead
	sed -i.bak '/^image:/d' "${work}/airprint/config.yaml"
	rm -f "${work}/airprint/config.yaml.bak"

	tar czf "${work}/addon.tgz" -C "${work}" airprint
	send "${work}/addon.tgz" /mnt/data/supervisor/apps/local
	rm -rf "${work}"

	guest "docker exec hassio_cli ha store reload >/dev/null 2>&1; docker exec hassio_cli ha apps rebuild ${SLUG} 2>&1 | tail -1" 900
	guest "docker exec hassio_cli ha apps start ${SLUG} >/dev/null 2>&1; sleep 20; docker logs addon_${SLUG} 2>&1 | tail -5"
fi

if [ "${WHAT}" = "all" ] || [ "${WHAT}" = "integration" ]; then
	echo "==> integration"

	rm -rf custom_components/airprint/__pycache__
	tar czf /tmp/integration.tgz custom_components
	send /tmp/integration.tgz /mnt/data/supervisor/homeassistant

	guest "docker exec hassio_cli ha core restart >/dev/null 2>&1; echo 'Home Assistant is restarting'"
fi
