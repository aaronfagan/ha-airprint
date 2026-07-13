from __future__ import annotations

import asyncio
import logging

from homeassistant.config_entries import ConfigEntry, ConfigSubentry
from homeassistant.const import CONF_HOST, CONF_PORT, Platform
from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers import issue_registry as ir
from homeassistant.exceptions import ConfigEntryNotReady

from .const import DOMAIN, SUBENTRY, device_name
from .coordinator import AirPrintCoordinator

_LOGGER = logging.getLogger(__name__)

PLATFORMS = [Platform.BINARY_SENSOR, Platform.SENSOR]

def _printer(data: dict) -> dict:
    printer = {
        "name": data.get("name", ""),
        "device": data.get("device", ""),
        "location": data.get("location", ""),
    }

    if data.get("icon"):
        printer = {"icon": data["icon"], **printer}

    if data.get("driver"):
        printer["driver"] = data["driver"]

    return printer


async def async_setup_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    coordinator = AirPrintCoordinator(hass, entry.data[CONF_HOST], entry.data[CONF_PORT])
    await coordinator.async_config_entry_first_refresh()

    hass.data.setdefault(DOMAIN, {})[entry.entry_id] = coordinator

    if not entry.subentries:
        for printer in await coordinator.async_get_printers():
            hass.config_entries.async_add_subentry(
                entry,
                ConfigSubentry(
                    data=_printer(printer),
                    subentry_type=SUBENTRY,
                    title=printer.get("name", ""),
                    unique_id=printer.get("device") or printer.get("name"),
                ),
            )

    for subentry in entry.subentries.values():
        data = dict(subentry.data)
        device = data.get("device", "")

        name = data.get("name", "")
        if "://" in name:
            name = ""

        discovered = data.get("discovered_name", "")
        if "://" in discovered:
            discovered = ""

        model = coordinator.data.get(device, {}).get("model", "")

        if model and discovered == device_name(device):
            discovered = model
        if model and name == device_name(device):
            name = model

        discovered = discovered or model or name or device_name(device)
        repaired = {**data, "discovered_name": discovered, "name": name or discovered}

        if repaired != data:
            hass.config_entries.async_update_subentry(entry, subentry, data=repaired)

    for subentry in entry.subentries.values():
        if subentry.title != subentry.data.get("name"):
            hass.config_entries.async_update_subentry(
                entry, subentry, title=subentry.data.get("name", "")
            )

    wanted = [_printer(subentry.data) for subentry in entry.subentries.values()]
    if wanted != await coordinator.async_get_printers():
        _LOGGER.info("Updating the AirPrint add-on with %d printer(s)", len(wanted))
        try:
            await coordinator.async_save_printers(wanted)
        except Exception as err:
            raise ConfigEntryNotReady(f"Could not update the AirPrint add-on: {err}") from err

        for _ in range(30):
            await asyncio.sleep(2)
            await coordinator.async_refresh()
            if coordinator.last_update_success and coordinator.data:
                break

    await hass.config_entries.async_forward_entry_setups(entry, PLATFORMS)

    @callback
    def _check() -> None:
        _async_check_drivers(hass, coordinator)

    _check()
    entry.async_on_unload(coordinator.async_add_listener(_check))

    entry.async_on_unload(entry.add_update_listener(async_reload_entry))
    return True


@callback
def _async_check_drivers(hass: HomeAssistant, coordinator) -> None:
    for printer in coordinator.data.values():
        issue_id = f"no_driver_{printer['id']}"

        if printer.get("driver"):
            ir.async_delete_issue(hass, DOMAIN, issue_id)
            continue

        ir.async_create_issue(
            hass,
            DOMAIN,
            issue_id,
            is_fixable=False,
            severity=ir.IssueSeverity.ERROR,
            translation_key="no_driver",
            translation_placeholders={"name": printer.get("model") or printer["id"]},
            learn_more_url="https://github.com/aaronfagan/ha-airprint#drivers",
        )


async def async_reload_entry(hass: HomeAssistant, entry: ConfigEntry) -> None:
    await hass.config_entries.async_reload(entry.entry_id)


async def async_unload_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    unloaded = await hass.config_entries.async_unload_platforms(entry, PLATFORMS)
    if unloaded:
        hass.data[DOMAIN].pop(entry.entry_id)
    return unloaded
