from __future__ import annotations

from homeassistant.components.sensor import SensorEntity, SensorStateClass
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from .const import DOMAIN
from .entity import AirPrintEntity


async def async_setup_entry(
    hass: HomeAssistant, entry: ConfigEntry, async_add_entities: AddEntitiesCallback
) -> None:
    coordinator = hass.data[DOMAIN][entry.entry_id]

    for subentry_id, subentry in entry.subentries.items():
        async_add_entities(
            [AirPrintJobs(coordinator, dict(subentry.data))],
            config_subentry_id=subentry_id,
        )


class AirPrintJobs(AirPrintEntity, SensorEntity):
    _attr_name = "Queued jobs"
    _attr_icon = "mdi:printer"
    _attr_native_unit_of_measurement = "jobs"
    _attr_state_class = SensorStateClass.MEASUREMENT

    def __init__(self, coordinator, printer: dict) -> None:
        super().__init__(coordinator, printer, "jobs")

    @property
    def native_value(self) -> int:
        return int(self.printer.get("jobs", 0))
