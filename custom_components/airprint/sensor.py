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
    async_add_entities(AirPrintJobs(coordinator, printer_id) for printer_id in coordinator.data)


class AirPrintJobs(AirPrintEntity, SensorEntity):
    _attr_name = "Queued jobs"
    _attr_icon = "mdi:printer"
    _attr_native_unit_of_measurement = "jobs"
    _attr_state_class = SensorStateClass.MEASUREMENT

    def __init__(self, coordinator, printer_id: str) -> None:
        super().__init__(coordinator, printer_id, "jobs")

    @property
    def native_value(self) -> int:
        return int(self.printer.get("jobs", 0))
