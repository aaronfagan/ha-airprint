#!/usr/bin/env bash
set -euo pipefail

# Sets the version of the add-on and the integration together, and tags it.
# They must always match: the Supervisor pulls <image>:<version from config.yaml>.
#
#   scripts/version.sh 1.11.0

cd "$(dirname "$0")/.."

VERSION=${1:-}

if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	echo "usage: scripts/version.sh <major.minor.patch>" >&2
	exit 64
fi

if [ -n "$(git status --porcelain)" ]; then
	echo "There are uncommitted changes. Commit them first." >&2
	exit 1
fi

sed -i.bak -E "s/^version: \".*\"/version: \"${VERSION}\"/" airprint/config.yaml
rm -f airprint/config.yaml.bak

python3 - "${VERSION}" <<'PY'
import json
import sys

path = "custom_components/airprint/manifest.json"
manifest = json.load(open(path))
manifest["version"] = sys.argv[1]

with open(path, "w") as file:
    json.dump(manifest, file, indent=2)
    file.write("\n")
PY

git add airprint/config.yaml custom_components/airprint/manifest.json
git commit -m "chore: version ${VERSION}"
git tag -a "v${VERSION}" -m "AirPrint ${VERSION}"

echo
echo "Tagged v${VERSION}. Push it to build and publish:"
echo
echo "  git push origin main && git push origin v${VERSION}"
