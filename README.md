# ha-airprint

A Home Assistant add-on that turns a non-AirPrint network printer into an AirPrint printer, so iPhones and iPads can print to it directly.

It replaces a Mac running [Printopia](https://www.decisivetactics.com/products/printopia/) — no always-on Mac required.

## The problem it solves

Many otherwise-fine network printers are **host-based**: they speak no IPP, no PostScript and no PCL, and rely entirely on a vendor driver to turn a document into something they understand. iOS cannot print to them, and no amount of Bonjour trickery changes that — something on the network has to run the driver and do the rasterizing.

This add-on is that something. It runs CUPS + Avahi + the vendor driver inside Home Assistant:

```
iPhone  --IPP/AirPrint-->  CUPS (this add-on)  --rasterize-->  vendor driver  --socket:9100-->  printer
```

Developed against a **Canon imageCLASS MF4890DW** (MF4800 series, UFR II LT — open ports 80/515/9100, no IPP).

## Status

Working, and in daily use — but currently **hardcoded to the Canon UFR II driver family**. See [Roadmap](#roadmap).

## Installation

1. Home Assistant → **Settings → Add-ons → Add-on Store → ⋮ → Repositories**
2. Add `https://github.com/aaronfagan/ha-airprint`
3. Install **AirPrint**, set the options below, and start it.

The add-on builds on-device, which takes a few minutes. It downloads Canon's driver from Canon's own CDN at build time — the driver is proprietary and is deliberately **not** redistributed in this repo.

## Options

Add one block per printer. Each printer gets its own AirPrint entry.

```yaml
printers:
  - name: Canon MF4890DW
    address: ""          # blank = find it on the network
    location: Office
    emoji: 🖨️
  - name: Brother HL-2270
    address: 192.168.1.22
    emoji: 📠
```

| Field | Notes |
| --- | --- |
| `name` | Shown when you go to print. Spaces are fine; the CUPS queue id is slugified from it. |
| `address` | **Leave blank to auto-discover.** Or give an IP (`192.168.1.50`) — `socket://` and port 9100 are implied. A full URI (`lpd://…`) is used as-is. |
| `location` | Free text, shown under the printer name. |
| `emoji` | Prefixed to the name — **this is what shows as the "icon" on iOS** (see below). `none` to disable. |

**Auto-discovery** uses CUPS' `dnssd` and `snmp` backends (`lpinfo -v`). It resolves a printer's Bonjour advert (`_pdl-datastream._tcp` for raw 9100 printing) to an IP. It only auto-picks when **exactly one** printer is found — with several on the network it lists them in the log and asks you to set an address, rather than guessing. A printer with no Bonjour advert and SNMP disabled is undiscoverable; type its IP.

Give the printer a DHCP reservation: discovery runs at startup, so a printer that moves IP will otherwise go stale.

## How it works

- **CUPS 2.4 + Avahi does the AirPrint advertising automatically.** Sharing a PPD-backed queue is enough: CUPS synthesizes the required `URF` TXT record from the PPD and publishes `_ipp._tcp`. The hand-written Avahi `.service` files and `*cupsFilter2` PPD hacks found in older guides are pre-CUPS-2.4 and are actively harmful now.
- **`cups-filters` bridges iOS to the vendor driver**: `image/urf` → PDF → CUPS raster → the vendor's rasterizer → the printer.
- **The queue is declarative.** It is recreated from the add-on options on every start, so there is no persisted CUPS state to rot.
- **The "icon" on iOS is an emoji, not an image.** iOS's print picker renders the Bonjour *service name* and ignores the IPP `printer-icons` image entirely. Printopia advertises `🖨 <name>` — the emoji IS the icon. Hence `printer_emoji`, which is prefixed to the advertised name (the CUPS queue id is slugified from `printer_name` alone, so it stays clean).
- **A printer icon is served automatically** — no configuration. It only matters on macOS, which *does* fetch `printer-icons`; iOS ignores it. cupsd serves it from `CacheDir` (`/var/cache/cups/images/<queue>.png`) — not the document root, as most guides claim. The directory does not exist by default, so stock CUPS advertises an icon URL that always 404s. Vendor artwork is not automatable: Linux drivers ship no product images (only macOS drivers bundle `.icns`), so the add-on ships a neutral one.

## Notes and gotchas

- **The PPD for the MF4800 series is `CNRCUPSMF4800ZK.ppd`** — note `CNR`, not the `CNCUPS…` name that most sources (and Canon's own older docs) give.
- **mDNS on HAOS.** Home Assistant already runs an mDNS stack, and this add-on runs its own Avahi in `host_network` mode. Both bind UDP 5353. Avahi logs `Detected another IPv4 mDNS stack running on this host`, and discovery is [known to fail for some users](https://github.com/MaxWinterstein/homeassistant-addons/issues/508). It works here. If it doesn't work for you, an AirPrint `.mobileconfig` profile that pins the printer by IP avoids Bonjour entirely.
- **CUPS 3.x will break this.** It drops PPD/classic-driver support, and every proprietary vendor driver is PPD-based. Pinned to Debian bookworm (CUPS 2.4) to stay ahead of that.
- **Canon's CDN URL is version-pinned** (`CANON_URL` build arg) and will 404 when Canon ships a new version. Grab the new link from Canon's Linux UFR II driver page and override the build arg.

## Roadmap

To make this generally useful rather than Canon-specific:

- Bring-your-own driver: install a user-supplied `.deb`/`.ppd` from `/share` at startup.
- Bundle the free `printer-driver-*` packages (brlaser, foo2zjs, splix, gutenprint) so most open-driver printers work with no extra steps.
- Populate the PPD choice from `lpinfo -m` as a dropdown instead of hardcoding the model.
- Publish prebuilt multi-arch images (Canon ships arm64 too) so installs don't require an on-device build.

## Licence

MIT for the contents of this repo. Canon's driver is proprietary, is downloaded from Canon at build time, and is covered by Canon's own licence.
