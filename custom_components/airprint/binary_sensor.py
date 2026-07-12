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

    for subentry_id, subentry in entry.subentries.items():
        printer = dict(subentry.data)
        async_add_entities(
            [
                AirPrintOnline(coordinator, printer),
                AirPrintProblem(coordinator, printer),
            ],
            config_subentry_id=subentry_id,
        )


class AirPrintOnline(AirPrintEntity, BinarySensorEntity):
    _attr_name = "Online"
    _attr_device_class = BinarySensorDeviceClass.CONNECTIVITY

    def __init__(self, coordinator, printer: dict) -> None:
        super().__init__(coordinator, printer, "online")

    @property
    def is_on(self) -> bool:
        return bool(self.printer.get("online"))


class AirPrintProblem(AirPrintEntity, BinarySensorEntity):
    _attr_name = "Problem"
    _attr_device_class = BinarySensorDeviceClass.PROBLEM

    def __init__(self, coordinator, printer: dict) -> None:
        super().__init__(coordinator, printer, "problem")

    @property
    def is_on(self) -> bool:
        return bool(self.printer.get("problem")) or bool(self.printer.get("reasons"))

    @property
    def extra_state_attributes(self) -> dict:
        reasons = self.printer.get("reasons") or []
        return {"reason": ", ".join(reasons), "reasons": reasons}
