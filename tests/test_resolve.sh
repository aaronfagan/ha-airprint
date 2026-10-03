#!/usr/bin/env bash
# Regression test for monitor.sh::resolve().
#
# A printer whose Bonjour service name contains Avahi-escaped characters
# (e.g. "\032" for a space) must still resolve to its address. Passing the
# escaped name to `awk -v` corrupts it, because awk interprets backslash
# escapes in the assignment; the name must reach awk as opaque data.
#
#   tests/test_resolve.sh

set -uo pipefail

cd "$(dirname "$0")/.."

MONITOR=airprint/monitor.sh
failed=0

stub_dir=$(mktemp -d)
trap 'rm -rf "${stub_dir}"' EXIT

# A fake avahi-browse that replays representative `avahi-browse -rtp` output
# and ignores its arguments, like the real one does for our invocation.
cat > "${stub_dir}/avahi-browse" <<'STUB'
#!/usr/bin/env bash
cat <<'OUT'
=;wlu1;IPv4;Brother\032HL-2270DW\032series;PDL Printer;local;BRN30055C473DC4.local;192.168.1.121;9100;usb_MFG=Brother;usb_MDL=HL-2270DW series
=;wlu1;IPv4;Plain Printer;PDL Printer;local;plain.local;10.0.0.5;9100;
OUT
STUB
chmod +x "${stub_dir}/avahi-browse"

# A fake timeout that just runs the command, so the stub is used directly.
cat > "${stub_dir}/timeout" <<'STUB'
#!/usr/bin/env bash
shift
exec "$@"
STUB
chmod +x "${stub_dir}/timeout"

run() {
	PATH="${stub_dir}:${PATH}" AIRPRINT_RESOLVE_TEST="$1" bash "${MONITOR}"
}

check() {
	local label=$1 device=$2 expected=$3 actual
	actual=$(run "${device}")
	if [ "${actual}" = "${expected}" ]; then
		echo "ok   - ${label}"
	else
		echo "FAIL - ${label}"
		echo "       expected: <$(printf '%s' "${expected}" | tr '\t' ' ')>"
		echo "       actual:   <$(printf '%s' "${actual}" | tr '\t' ' ')>"
		failed=1
	fi
}

check "service name with escaped spaces" \
	'dnssd://Brother\032HL-2270DW\032series._pdl-datastream._tcp.local/' \
	"$(printf '192.168.1.121\t9100')"

check "plain service name" \
	'dnssd://Plain Printer._pdl-datastream._tcp.local/' \
	"$(printf '10.0.0.5\t9100')"

check "socket URI" \
	'socket://192.168.1.50:9100' \
	"$(printf '192.168.1.50\t9100')"

exit "${failed}"
