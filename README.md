<p align="center">
  <img src="custom_components/airprint/brand/icon.png" width="128" alt="AirPrint">
</p>

<h1 align="center">AirPrint for Home Assistant</h1>

<p align="center">
  Print from your iPhone to a printer that has never heard of AirPrint.
</p>

---

Plenty of perfectly good network printers cannot be printed to from a phone. They are **host-based**: they speak no IPP, no PostScript and no PCL, and rely entirely on a driver on your computer to turn a document into something they understand. iOS will not see them, and no amount of Bonjour trickery changes that — something on the network has to run the driver and do the rasterising.

Until now, in this house, that something was a **Mac running [Printopia](https://www.decisivetactics.com/products/printopia/)**: quietly on, forever, so that the household could print.

This is that Mac, replaced by Home Assistant.

```
iPhone  ──IPP/AirPrint──▶  AirPrint add-on  ──driver──▶  your printer
                           (CUPS + Avahi)                (socket / LPD)
```

Built against a **Canon imageCLASS MF4890DW** — no IPP, no PostScript, no PCL, does not even answer a PJL probe — which is now printed to from an iPhone.

## What you get

Each printer you add becomes:

- **An AirPrint printer** on every iPhone, iPad and Mac in the house.
- **A device in Home Assistant**, with:

| Entity | What it tells you |
| --- | --- |
| **Status** | `Ready`, `Printing`, `Out of paper`, `Paper jam`, `Toner low`, `Door open`, `Offline` |
| **Health** | `OK` / `Problem` — the one to alert on |
| **Online** | Whether the printer answers on the network |
| **Queue** | Jobs waiting |
| **Toner** | Percentage remaining, with the cartridge name |
| **Printed** | The printer's lifetime page counter |

Toner, page count and the *reason* behind a problem come from **SNMP** (the standard Printer MIB). Printers that don't expose it simply don't get those sensors; everything else works regardless.

You also get a **notification** when a printer is refusing jobs with work queued behind it — *"Out of paper"* — and when a printer appears on the network that isn't set up yet. A print server that fails silently is worse than no print server at all.

## Install

Two pieces: an **add-on** (the print server) and an **integration** (the config UI and the sensors).

**1. Add-on** — Settings → Add-ons → Add-on Store → ⋮ → **Repositories** → add:

```
https://github.com/aaronfagan/ha-airprint
```

Install **AirPrint** and start it.

**2. Integration** — add this repository to [HACS](https://hacs.xyz) as an Integration, install **AirPrint**, and restart Home Assistant. (Or copy `custom_components/airprint` into your `config` folder and restart.)

**3. Add your printer** — Home Assistant discovers the add-on by itself and shows an **AirPrint** card under Settings → Devices & Services. Click **Add**, and your printer is already filled in:

| Field | |
| --- | --- |
| **Name** | Pre-filled with the printer's make and model. This is what your phone shows. |
| **Location** | Optional. Shown under the name when you print. |
| **Icon** | An emoji, shown in front of the name — see [Icons](#icons). |

There is **no IP address to enter**. See [How it finds your printer](#how-it-finds-your-printer).

## Drivers

The free driver set is bundled — Gutenprint, brlaser, foomatic, the OpenPrinting PPDs, `printer-driver-all` — and the right one is **matched to your printer automatically** from its IEEE 1284 device ID. Most printers need nothing further.

**Proprietary drivers are not, and cannot be, bundled.** Vendor drivers are non-redistributable — and the host-based printers that need this project most are exactly the ones no free driver can drive. So you supply those yourself, in one of two ways.

**Point the add-on at the driver.** In the add-on's configuration:

```yaml
drivers:
  - https://gdlp01.c-wss.com/gds/0/0100009240/41/linux-UFRII-drv-v630-m17n-10.tar.gz
```

It is downloaded once, cached, and installed on start. A `.deb`, a `.ppd`, or a vendor `.tar.gz` all work — for a tarball, the add-on finds the packages inside that match your architecture.

**Or drop the file in.** Put a `.deb`, `.ppd` or `.tar.gz` into `/share/airprint/drivers` (Home Assistant's *share* folder, reachable with the Samba or File Editor add-on). It is installed on start.

<details>
<summary><b>Worked example: Canon (UFR II / UFRII LT)</b></summary>

<br>

The Canon imageCLASS / i-SENSYS lasers are host-based, and no free driver drives them. Canon publishes a Linux driver that covers the whole family — a single package contains **429 PPDs**, and there is an arm64 build too.

1. Open Canon's [UFR II/UFRII LT Printer Driver for Linux](https://asia.canon/en/support/0100924010) page and copy the download link for the `.tar.gz`.
2. Put it in the add-on's `drivers` option, as above.
3. Start the add-on. It logs the driver it installed and the PPD it matched:

```
[airprint] downloading driver linux-UFRII-drv-v630-m17n-10.tar.gz
[airprint] unpacking linux-UFRII-drv-v630-m17n-10.tar.gz
[airprint] installing cnrdrvcups-ufr2-uk_6.30-1.10_amd64.deb
[airprint] Canon MF4800 Series: driver CNRCUPSMF4800ZK.ppd
```

The PPD for the MF4800 series is `CNRCUPSMF4800ZK.ppd` — **`CNR`**, not the `CNCUPS…` that most guides, and some of Canon's own documentation, will tell you.

</details>

If nothing matches, the add-on says so in its log and skips that printer rather than pretending.

## How it finds your printer

**It does not store an IP address.** The print queue holds the printer's Bonjour name:

```
dnssd://MF4890DW._pdl-datastream._tcp.local/
```

CUPS resolves that to an address **at the moment you print** — which is exactly the *"Looking for printer…"* step your laptop does. So the printer's IP can change, DHCP can move it, and it is simply found again. Nothing to reconfigure, no address to keep in sync, and no self-healing machinery to go wrong.

If it cannot be resolved, the printer reports **Offline** and the job fails at the device — rather than the print server pretending it knows where the printer lives.

A printer that advertises no Bonjour service at all is the one case where you are asked for an address.

## Icons

**On iOS, a printer's "icon" is an emoji in its name.** iOS's print picker renders the Bonjour service name and ignores the IPP icon image entirely — which is precisely what Printopia does, advertising `🖨 <name>`. So the add-on has an **Icon** field: pick an emoji, and it is prefixed to the name your phone sees.

macOS *does* fetch the IPP icon, and the add-on serves one automatically. Nothing to configure.

## Notes

- **Multiple printers** — add as many as you like. Each is its own device, with its own name, icon and sensors.
- **CUPS 3.x** drops the classic PPD driver model that every proprietary vendor driver depends on. This image is pinned to Debian bookworm (CUPS 2.4). Not urgent, but it is a shrinking road, and not one this project can pave.
- **mDNS on Home Assistant OS** — HAOS runs its own mDNS stack, and this add-on runs Avahi alongside it; both bind UDP 5353. It works here, and it is [known to fail for some people](https://github.com/MaxWinterstein/homeassistant-addons/issues/508). If your printer is advertised but iOS never connects, start there.
- **Home Assistant's IPP integration will discover this add-on** and offer to set it up. That is not a bug — the add-on genuinely *is* an IPP printer now, which is the entire point. Ignore the card.

## Licence

[MIT](LICENSE) for everything in this repository. Vendor drivers are downloaded from the vendor and covered by their own licences; none are redistributed here.
