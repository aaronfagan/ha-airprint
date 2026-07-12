#!/usr/bin/env bash
set -uo pipefail

OPTIONS=/data/options.json
DRIVERS=/share/airprint/drivers
WORK=/tmp/airprint-drivers

mkdir -p "${DRIVERS}" "${WORK}"

while read -r url; do
	[ -n "${url}" ] || continue

	file="${DRIVERS}/${url##*/}"
	file="${file%%\?*}"

	if [ -f "${file}" ]; then
		continue
	fi

	echo "[airprint] downloading driver ${file##*/}"
	if ! curl -fsSL -o "${file}.part" "${url}"; then
		echo "[airprint] could not download ${url}"
		rm -f "${file}.part"
		continue
	fi
	mv "${file}.part" "${file}"
done < <(jq -r '.drivers // [] | .[]' "${OPTIONS}")

install_deb() {
	echo "[airprint] installing ${1##*/}"
	dpkg -i "$1" >/dev/null 2>&1 || {
		echo "[airprint] ${1##*/} needs extra packages, fetching them"
		apt-get update -qq >/dev/null 2>&1
		apt-get -y -qq -f install >/dev/null 2>&1 || echo "[airprint] could not install ${1##*/}"
	}
}

shopt -s nullglob

for archive in "${DRIVERS}"/*.tar.gz "${DRIVERS}"/*.tgz; do
	name=${archive##*/}
	stamp="${WORK}/${name}.extracted"
	[ -f "${stamp}" ] && continue

	echo "[airprint] unpacking ${name}"
	rm -rf "${WORK}/${name}.d"
	mkdir -p "${WORK}/${name}.d"
	tar xzf "${archive}" -C "${WORK}/${name}.d" 2>/dev/null || {
		echo "[airprint] could not unpack ${name}"
		continue
	}
	touch "${stamp}"

	arch=$(dpkg --print-architecture)
	while read -r deb; do
		install_deb "${deb}"
	done < <(find "${WORK}/${name}.d" -name "*_${arch}.deb" | sort)
done

for package in "${DRIVERS}"/*.deb; do
	install_deb "${package}"
done

for ppd in "${DRIVERS}"/*.ppd "${DRIVERS}"/*.ppd.gz; do
	echo "[airprint] adding ${ppd##*/}"
	install -m 0644 "${ppd}" /usr/share/cups/model/
done

shopt -u nullglob
