from __future__ import annotations

import asyncio
import logging

from homeassistant.config_entries import ConfigEntry, ConfigSubentry
from homeassistant.const import CONF_HOST, CONF_PORT, Platform
from homeassistant.core import HomeAssistant
from homeassistant.exceptions import ConfigEntryNotReady
from homeassistant.helpers import device_registry as dr

from .const import DOMAIN, SUBENTRY, device_name
from .coordinator import AirPrintCoordinator

_LOGGER = logging.getLogger(__name__)

PLATFORMS = [Platform.BINARY_SENSOR, Platform.SENSOR]

FIELDS = ("name", "device", "location", "emoji")


def _printer(data: dict) -> dict:
    return {field: data.get(field, "") for field in FIELDS}


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
        if not subentry.data.get("discovered_name"):
            data = dict(subentry.data)
            data["discovered_name"] = data.get("name") or device_name(data.get("device", ""))
            hass.config_entries.async_update_subentry(entry, subentry, data=data)

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

    titles = {subentry.title for subentry in entry.subentries.values()}

    async def _unstamp_device_names(_now=None) -> None:
        await asyncio.sleep(3)
        devices = dr.async_get(hass)
        for device in dr.async_entries_for_config_entry(devices, entry.entry_id):
            if device.name_by_user in titles:
                devices.async_update_device(device.id, name_by_user=None)

    entry.async_create_background_task(hass, _unstamp_device_names(), "airprint_device_names")

    entry.async_on_unload(entry.add_update_listener(async_reload_entry))
    return True


async def async_reload_entry(hass: HomeAssistant, entry: ConfigEntry) -> None:
    await hass.config_entries.async_reload(entry.entry_id)


async def async_unload_entry(hass: HomeAssistant, entry: ConfigEntry) -> bool:
    unloaded = await hass.config_entries.async_unload_platforms(entry, PLATFORMS)
    if unloaded:
        hass.data[DOMAIN].pop(entry.entry_id)
    return unloaded
