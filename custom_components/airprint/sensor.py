from __future__ import annotations

from homeassistant.components.sensor import (
    SensorEntity,
    SensorStateClass,
)
from homeassistant.config_entries import ConfigEntry
from homeassistant.const import PERCENTAGE
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
                AirPrintStatus(coordinator, printer),
                AirPrintJobs(coordinator, printer),
                AirPrintToner(coordinator, printer),
                AirPrintPages(coordinator, printer),
            ],
            config_subentry_id=subentry_id,
        )


class AirPrintStatus(AirPrintEntity, SensorEntity):
    _attr_name = "Status"
    _attr_icon = "mdi:printer-check"

    def __init__(self, coordinator, printer: dict) -> None:
        super().__init__(coordinator, printer, "status")

    @property
    def native_value(self) -> str:
        printer = self.printer

        if not printer.get("online"):
            return "Offline"

        reasons = printer.get("reasons") or []
        if reasons:
            return ", ".join(reasons)

        if printer.get("problem"):
            return "Not accepting jobs"

        if printer.get("jobs"):
            return "Printing"

        return "Ready"


class AirPrintJobs(AirPrintEntity, SensorEntity):
    _attr_name = "Queue"
    _attr_icon = "mdi:tray-full"
    _attr_native_unit_of_measurement = "jobs"
    _attr_state_class = SensorStateClass.MEASUREMENT

    def __init__(self, coordinator, printer: dict) -> None:
        super().__init__(coordinator, printer, "jobs")

    @property
    def native_value(self) -> int:
        return int(self.printer.get("jobs", 0))


class AirPrintToner(AirPrintEntity, SensorEntity):
    _attr_name = "Toner"
    _attr_icon = "mdi:water-percent"
    _attr_native_unit_of_measurement = PERCENTAGE
    _attr_state_class = SensorStateClass.MEASUREMENT

    def __init__(self, coordinator, printer: dict) -> None:
        super().__init__(coordinator, printer, "toner")

    @property
    def available(self) -> bool:
        return super().available and self.printer.get("toner") is not None

    @property
    def native_value(self) -> int | None:
        return self.printer.get("toner")

    @property
    def extra_state_attributes(self) -> dict:
        return {"cartridge": self.printer.get("supply", "")}


class AirPrintPages(AirPrintEntity, SensorEntity):
    _attr_name = "Pages printed"
    _attr_icon = "mdi:counter"
    _attr_native_unit_of_measurement = "pages"
    _attr_state_class = SensorStateClass.TOTAL_INCREASING

    def __init__(self, coordinator, printer: dict) -> None:
        super().__init__(coordinator, printer, "pages")

    @property
    def available(self) -> bool:
        return super().available and self.printer.get("pages") is not None

    @property
    def native_value(self) -> int | None:
        return self.printer.get("pages")
