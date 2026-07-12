from __future__ import annotations

from homeassistant.components.binary_sensor import (
    BinarySensorDeviceClass,
    BinarySensorEntity,
)
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from .const import DOMAIN
from .entity import AirPrintEntity


async def async_setup_entry(
    hass: HomeAssistant, entry: ConfigEntry, async_add_entities: AddEntitiesCallback
) -> None:
    coordinator = hass.data[DOMAIN][entry.entry_id]

    entities = []
    for printer_id in coordinator.data:
        entities.append(AirPrintOnline(coordinator, printer_id))
        entities.append(AirPrintProblem(coordinator, printer_id))

    async_add_entities(entities)


class AirPrintOnline(AirPrintEntity, BinarySensorEntity):
    _attr_translation_key = "online"
    _attr_name = "Online"
    _attr_device_class = BinarySensorDeviceClass.CONNECTIVITY

    def __init__(self, coordinator, printer_id: str) -> None:
        super().__init__(coordinator, printer_id, "online")

    @property
    def is_on(self) -> bool:
        return bool(self.printer.get("online"))


class AirPrintProblem(AirPrintEntity, BinarySensorEntity):
    _attr_translation_key = "problem"
    _attr_name = "Problem"
    _attr_device_class = BinarySensorDeviceClass.PROBLEM

    def __init__(self, coordinator, printer_id: str) -> None:
        super().__init__(coordinator, printer_id, "problem")

    @property
    def is_on(self) -> bool:
        return bool(self.printer.get("problem"))
