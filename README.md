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

Two pieces: an **add-on** (the print server) and an **integration** (the config UI and the sensors).

1. **Add-on** — Settings → Apps → Store → ⋮ → Repositories → add `https://github.com/aaronfagan/ha-airprint`. Install **AirPrint** and start it.
2. **Integration** — install this repo in HACS as an integration (or copy `custom_components/airprint` into your HA config and restart).
3. Home Assistant **auto-discovers** the add-on over mDNS and shows an **AirPrint** card under Settings → Devices & Services. Click **Configure**.

The add-on builds on-device, which takes a few minutes. It downloads Canon's driver from Canon's own CDN at build time — the driver is proprietary and is deliberately **not** redistributed in this repo.

## Adding printers

Settings → Devices & Services → **AirPrint** → **Configure** → *Add a printer*:

| Field | Notes |
| --- | --- |
| **Name** | Shown when you go to print. Spaces are fine. |
| **Address** | Pick a printer **found on your network**, or type an IP. Leave blank to search for it. |
| **Location** | Free text, shown under the printer name. |
| **Icon** | An emoji, prefixed to the name — **this is what iOS shows as the printer's icon** (see below). |

Each printer becomes an AirPrint printer on your phones, and a **device in Home Assistant** with:

| Entity | Meaning |
| --- | --- |
| `binary_sensor.<printer>_online` | The printer answers on the network. |
| `binary_sensor.<printer>_problem` | **Powered on but refusing print jobs** — out of paper, jammed, or in an error state. |
| `sensor.<printer>_queued_jobs` | Jobs waiting in the queue. |

The `problem` sensor exists because of how these printers behave: when a Canon MF4890DW runs out of paper it **closes its print ports (9100/515) while still answering HTTP**. It looks alive but refuses every job, from every host. Probing the print port is therefore a reliable "can it actually print right now?" signal. A notification is raised when a printer is refusing jobs with work queued behind it, and when an unconfigured printer appears on the network.

**Why an integration and not just add-on options?** Add-on options only render a friendly form for *flat* schemas — a list of printers degrades to a raw YAML editor, and add-ons cannot offer real HA selectors or put entities in the entity registry (so no Areas, no renaming). The integration owns the config UI and writes the printer list into the add-on through the Supervisor API, the same way Z-Wave JS drives its add-on.

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
