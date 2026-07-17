<p align="center">
  <img src="custom_components/airprint/brand/icon.png" width="128" alt="AirPrint">
</p>

<h1 align="center">AirPrint for Home Assistant</h1>

<p align="center">
  Share any network printer as an AirPrint printer, from Home Assistant.
</p>

---

Home Assistant becomes the print server: it advertises your printer over AirPrint, runs the printer's driver, and gives you sensors for toner, page count and whether the thing is out of paper.

It works with printers that have **no AirPrint support at all** — including host-based printers that speak no IPP, no PostScript and no PCL, and cannot otherwise be printed to from a phone or tablet.

## Does my printer need this?

If your printer already does AirPrint, you don't need this — print to it directly.

If it doesn't, and you have been keeping a computer switched on so that everyone can print, this replaces it. Any printer reachable on your network over **port 9100 (socket) or 515 (LPD)** will work.

## Install

Two pieces: an **add-on** (the print server) and an **integration** (the setup screens and the sensors).

**1. Add-on** — Settings → Add-ons → Add-on Store → ⋮ → **Repositories** → add:

```
https://github.com/aaronfagan/ha-airprint
```

Install **AirPrint** and start it. A prebuilt image is pulled — `amd64` and `aarch64`, nothing is compiled on your machine.

**2. Integration** — add this repository to [HACS](https://hacs.xyz) as an Integration, install **AirPrint**, then restart Home Assistant. (Or copy `custom_components/airprint` into your `config` folder and restart.)

**3. Add your printer** — Home Assistant finds the add-on by itself and shows an **AirPrint** card under Settings → Devices & Services. Click **Add**. Your printer is already filled in:

| Field | |
| --- | --- |
| **Name** | Pre-filled with the printer's make and model. This is the name shown in the print dialogue. Clear it to go back to the make and model. |
| **Location** | Optional. Shown under the name when printing. |
| **Icon** | Optional. An emoji shown in front of the name — see [Icons](#icons). |

There is no IP address to type. The printer is found on the network, and stays found even if its address changes — see [How it finds your printer](#how-it-finds-your-printer).

If no driver is available for your printer, you are asked for one here — see [Drivers](#drivers).

That's it. The printer now appears in the print dialogue on any device that speaks AirPrint.

## Sensors

Each printer becomes a device in Home Assistant:

| Entity | What it tells you |
| --- | --- |
| **Status** | `Ready`, `Printing`, `Out of paper`, `Paper jam`, `Toner low`, `Door open`, `Offline`, `No driver` |
| **Health** | `OK` / `Problem` — the one to alert on |
| **Online** | Whether the printer answers on the network |
| **Queue** | Jobs waiting |
| **Toner** | Percentage remaining, with the cartridge name |
| **Printed** | The printer's lifetime page counter |

Toner, page count and the *reason* behind a problem come from **SNMP** (the standard Printer MIB). Printers that don't expose it don't get those sensors; everything else still works.

You also get a notification when a printer is refusing jobs with work queued behind it — *"Out of paper"* — when a printer turns up on the network that isn't set up yet, and when a printer has no driver and so cannot print.

## Drivers

Most printers need nothing here.

The free driver set is bundled — over 11,000 drivers (Gutenprint, brlaser, foomatic, the OpenPrinting PPDs) — and the right one is **matched to your printer automatically** from its device ID. If the add-on's log shows a driver and a queue, you're done.

**If your printer needs a driver from its manufacturer**, supply it yourself — vendor drivers are proprietary and cannot be shipped with the add-on. Two ways:

**Give Home Assistant a link to it.** If no driver is matched when you add the printer, you are asked for one. Paste a link and it is downloaded, cached and installed — it belongs to that printer, and you can change it later from its **Driver file URL** field.

Skip it and the printer is still added, but its **Status** reads `No driver` and Home Assistant raises a repair until you supply one.

A `.deb`, a `.ppd` or a vendor `.tar.gz` all work — for a tarball, the packages inside that match your architecture are found and installed. Change the link and the old file is cleaned up.

Any URL works, so **host the driver yourself** if you can. Vendor links are usually version-pinned and break when the vendor ships an update.

**Or drop the file in.** Put a `.deb`, `.ppd` or `.tar.gz` into `/share/airprint/drivers` (Home Assistant's *share* folder, reachable with the Samba or File Editor add-on). It is installed on start.

If nothing matches your printer, the add-on says so in its log and skips it, rather than setting up a queue that cannot print.

<details>
<summary><b>Example: a host-based Canon laser</b></summary>

<br>

Canon's imageCLASS / i-SENSYS lasers are host-based, and no free driver drives them. Canon publishes one Linux driver covering the whole family — a single package holds **429 PPDs**, with an arm64 build too.

1. Open Canon's [UFR II/UFRII LT Printer Driver for Linux](https://asia.canon/en/support/0100924010) page and copy the download link for the `.tar.gz`.
2. Paste it into the printer's **Driver file URL** field when Home Assistant asks for a driver.
3. Start the add-on. It logs what it installed and the driver it matched:

```
[airprint] downloading driver linux-UFRII-drv-v630-m17n-10.tar.gz
[airprint] installing cnrdrvcups-ufr2-uk_6.30-1.10_amd64.deb
[airprint] Canon MF4800 Series: driver CNRCUPSMF4800ZK.ppd
```

The PPD for the MF4800 series is `CNRCUPSMF4800ZK.ppd` — **`CNR`**, not the `CNCUPS…` most guides (and some of Canon's own documentation) will tell you.

</details>

## How it finds your printer

The print queue holds the printer's Bonjour name, not its IP address:

```
dnssd://PRINTER._pdl-datastream._tcp.local/
```

CUPS resolves it to an address **at the moment you print** — the same *"Looking for printer…"* step a laptop does. The printer's IP can change and it is simply found again: nothing to reconfigure, no address to keep in sync.

If it cannot be found, the printer reports **Offline** and the job fails at the device.

A printer that advertises no Bonjour service at all is the one case where you are asked for an address.

## Icons

**On iOS, a printer's "icon" is an emoji in its name.** The print picker shows the advertised name and ignores the icon image entirely. So pick an emoji in the **Icon** field and it is prefixed to the name — in the print dialogue and in Home Assistant, so the printer reads the same in both.

It is also a way to tell two printers apart when they share a name.

Desktop clients *do* fetch the icon image, and the add-on serves one automatically. Nothing to configure.

## Troubleshooting

- **The printer doesn't appear when I print.** Check the add-on's log: it should show a driver and a queue for your printer. If it says no driver matched, see [Drivers](#drivers).
- **It appears, but jobs never print.** Check the **Status** sensor — out of paper, jammed and door-open are all reported there. Many printers refuse connections entirely when they are out of paper.
- **It never appears at all.** Home Assistant OS runs its own mDNS stack, and this add-on runs Avahi alongside it. It works, and it is [known to fail for some people](https://github.com/MaxWinterstein/homeassistant-addons/issues/508). That is the place to look.
- **Home Assistant offers to set up an "IPP" integration.** That is Home Assistant discovering this add-on, which is now genuinely an IPP printer. Ignore the card.

## Notes

- **Multiple printers** — add as many as you like. Each becomes its own device.
- **CUPS 3.x** drops the classic driver model that proprietary vendor drivers rely on. The add-on is pinned to Debian bookworm (CUPS 2.4). Not urgent, but worth knowing.

## Additional Information
- [Blog Article](https://www.aaronfagan.ca/blog/2026/airprint-for-home-assistant/)

## Licence

[MIT](LICENSE). Vendor drivers are downloaded from the vendor and covered by their own licences; none are redistributed here.
