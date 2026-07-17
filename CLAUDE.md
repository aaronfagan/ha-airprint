# CLAUDE.md

An AirPrint bridge for Home Assistant, in two halves:

- **`airprint/`** — the add-on. CUPS + Avahi + the printer's driver. Published as a container image.
- **`custom_components/airprint/`** — the integration. The setup screens and the sensors.

The integration **owns the printer list** and writes it into the add-on's options through the Supervisor API. Anything hand-edited in the add-on's YAML is overwritten on the next sync — printer settings belong in the integration's form.

## Why two pieces

The split was arrived at the hard way; do not relitigate it. An add-on's options only render a friendly form for a **flat** schema, so a list of printers collapses to a raw YAML editor, and add-ons cannot offer Home Assistant selectors. Entities pushed from an add-on via the REST states API are not registry entities, so they get no Areas and cannot be renamed. Only an **integration** gives proper registry entities (a device per printer, renameable, assignable to Areas) with no MQTT broker. So the integration owns the UI and the entities; the add-on is just the print engine plus a status feed. The integration auto-discovers the add-on from an mDNS advert (`_airprint-status._tcp`) and drives it through the Supervisor API, the same pattern Z-Wave JS uses.

## How it works

- **The add-on** runs CUPS 2.4 (pinned to Debian bookworm; CUPS 3.x drops PPD drivers) + Avahi. A shared PPD queue makes CUPS 2.4 advertise AirPrint automatically, so no `.service` files or `cupsFilter2` hacks (those are pre-2.4 and harmful). `monitor.sh` loops every 60s and writes `/srv/status.json`, served on `:8099`.
- **Discovery is passive mDNS.** `discover.sh` reads the printer's `_pdl-datastream._tcp` advert (model and device-id come from its TXT record: `usb_MFG` / `usb_MDL` / `ty` / `product`) and matches a driver from the local PPD database (`lpinfo -m`). It must **never** run CUPS device discovery (`lpinfo -v`) on a timer, for the reason below.
- **Status is SNMP, never the print port.** Liveness is an SNMP `sysUpTime` read (UDP 161, the management plane). Health is the `hrPrinterDetectedErrorState` bitmask (0x40 out of paper, 0x04 jam, 0x08 door open, 0x20 toner low, etc.). Toner and page count are SNMP too. In `status.json`, `problem` is only TCP reachability and `reasons` is only the SNMP decode; the integration ORs them (plus no-driver) for the Health entity, so `"problem": false` alongside `"reasons": ["Out of paper"]` is correct.
- **NEVER open the printer's raw print port (9100/515) on a timer.** Many printers (Canon MFPs especially) treat any TCP connection to 9100 as an incoming job and audibly wake. This caused a once-a-minute "phantom beep" that took two passes to kill: first `monitor.sh`'s own `port_open` liveness probe, then the CUPS **snmp backend** that `lpinfo -v` invokes during discovery (after finding the printer over SNMP it opens 9100 to read the IEEE-1284 device-id via PJL). Use SNMP or IPP Get-Printer-Attributes for liveness and passive mDNS for discovery. Nothing should touch 9100 except a real print job. A 9100 SYN with `UID=7` (lp) fingerprints a CUPS backend, not `monitor.sh` (root).
- **Identity is the Bonjour name.** The queue's device URI is `dnssd://<service>._pdl-datastream._tcp.local/`; CUPS' dnssd backend resolves it to an address at job time, so no IP is stored and the printer's IP can change freely.

## Testing on the Home Assistant box

There is no plain SSH into HA OS. Root + `docker` is reached through the Proxmox host and the QEMU guest agent:

```bash
ssh pve
qm guest exec 100 -- /bin/sh -c '<command>'
# for anything non-trivial, base64 it (emoji and nested quotes do not survive the shell):
qm guest exec 100 -- /bin/sh -c 'echo <BASE64> | base64 -d | sh'
```

- Supervisor CLI: `docker exec hassio_cli ha apps ...` / `ha store reload` / `ha core restart` (the CLI still accepts the old `addons` verb but prints a deprecation; prefer `apps`).
- Published-store slug: `0f9301c3_airprint`, container `addon_0f9301c3_airprint`. Local dev build: `local_airprint`.
- Inspect the running add-on with `docker exec addon_0f9301c3_airprint cat /srv/status.json`, and `docker inspect` for RestartCount/StartedAt. `ha apps logs` is a rolling buffer that keeps pre-restart lines, so do not mistake old lines for live looping.
- A printer that fell to a link-local `169.254.x` address (lost its DHCP lease) makes cupsd restart-loop; fix the printer, not the add-on.
- No tcpdump/conntrack on HA OS. To watch for stray 9100 traffic, arm an `iptables` OUTPUT LOG rule on SYNs to the printer and read hits from `dmesg`.

## Developing

Iterate with `scripts/dev.sh`. It pushes the working tree onto the Home Assistant box, strips the `image:` key so the Supervisor **builds the add-on locally**, and rebuilds it. **No version bump, nothing published, no tags.**

```bash
scripts/dev.sh              # add-on + integration, then restart Home Assistant
scripts/dev.sh addon        # add-on only
scripts/dev.sh integration  # integration only
```

Two things that will waste your time if you forget them:

- **The add-on only picks up changes on a rebuild.** `ha apps rebuild` does it without a version bump. A plain restart re-runs the *existing* image.
- **The integration only picks up changes when Home Assistant Core restarts.** Copying files in is not enough.

Verify against the real thing rather than asserting. The add-on's log and `/srv/status.json` (served on `:8099`) say what it actually did.

## Releasing

The version lives in **two files that must always match**, because the Supervisor pulls `<image>:<version from config.yaml>`:

- `airprint/config.yaml` → `version:`
- `custom_components/airprint/manifest.json` → `"version"`

Never edit them by hand. Use:

```bash
scripts/version.sh 1.11.0        # sets both, commits, tags
git push origin main && git push origin v1.11.0
```

Pushing the tag builds `amd64` and `aarch64`, publishes one multi-arch image to GHCR, and cuts a GitHub release. CI **fails the release** if the tag and the two files disagree, so they cannot drift.

**Patch** for fixes and copy. **Minor** for features. **Major** only for something that breaks an existing config.

## Keep the README current

The README is the front door. **Any change to features, options, fields or behaviour lands in the README in the same commit.** Someone who finds this repo should read it once and have their printer printing.

Write for **a Home Assistant user who wants their printer on AirPrint** — not for the author, and not as a story about the problem. Keep it light:

- Lead with whether they need this at all, then install, then adding the printer. Say "that's it" where they are actually done.
- Document what a user sees and touches: the fields, the sensors, what to do when a driver is missing.
- Leave out internals unless they change what a user does.
- Examples are copied from real output — re-check them when behaviour changes.

## Conventions

- **Home Assistant's conventions win.** Sentence-case entity names, its device classes and their fixed state text, its selectors. If a request conflicts with one, say so before deviating.
- **The data model mirrors the UI.** One key per field the user sees.
- **Proprietary drivers are never bundled.** They are downloaded at runtime from a URL on the printer, or dropped into `/share/airprint/drivers`. A published image ships only the free driver set — that is what makes it publishable at all.

## Traps worth knowing

Each of these cost real debugging time at least once.

- **iOS renders the Bonjour service name as the printer "icon", and ignores the IPP `printer-icons` image entirely.** That is why the add-on prefixes an emoji to the advertised name (the `icon` option). macOS does fetch `printer-icons`.
- **Canon UFR II is proprietary** and in no free driver set; Aaron's printer pulls its driver from his own CDN at runtime. The Canon PPD is `CNRCUPSMF4800ZK.ppd` (`CNR`, not the `CNCUPS...` most sources cite).
- **Printer icons are served from CUPS' `CacheDir`** (`/var/cache/cups/images/<queue>.png`), not doc-root. The directory must exist or the advertised icon URL always 404s.
- **Installing any cups package starts Debian's own cupsd** on port 631; ours then cannot bind and `lpadmin` talks to the wrong daemon (returns `Unauthorized`). `pkill -x cupsd` after driver install, before starting ours. This looks exactly like a permissions bug and is not one.
- **`ping` never works inside the container** (no raw-socket capability). Probe with SNMP or TCP.
- **The add-on must keep running with zero printers.** It used to `exit 1`, which killed the status API and mDNS advert, so a fresh install was undiscoverable and you could never add the first printer.
- **Home Assistant's own IPP integration will discover our CUPS queue** and offer a redundant card. Unavoidable, because we must advertise `_ipp._tcp` for AirPrint. Tell the user to Ignore it.
- **Renaming a printer leaves ghost Bonjour records** cached in resolvers for up to an hour. Verify what is really published by asking cupsd (`ipptool ... | grep printer-dns-sd-name`), not by browsing mDNS.
- **The queue id is slugified from the printer name**, so two printers with the same name collided until ids were suffixed (`_2`). That suffixing is what makes same-name-different-icon work.
