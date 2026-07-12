from __future__ import annotations

from homeassistant.helpers.device_registry import DeviceInfo
from homeassistant.helpers.update_coordinator import CoordinatorEntity

from .const import DOMAIN
from .coordinator import AirPrintCoordinator


class AirPrintEntity(CoordinatorEntity[AirPrintCoordinator]):
    _attr_has_entity_name = True

    def __init__(self, coordinator: AirPrintCoordinator, printer_id: str, key: str) -> None:
        super().__init__(coordinator)
        self._printer_id = printer_id
        self._attr_unique_id = f"{printer_id}_{key}"

    @property
    def printer(self) -> dict:
        return self.coordinator.data.get(self._printer_id, {})

    @property
    def available(self) -> bool:
        return super().available and self._printer_id in self.coordinator.data

    @property
    def device_info(self) -> DeviceInfo:
        return DeviceInfo(
            identifiers={(DOMAIN, self._printer_id)},
            name=self.printer.get("name", self._printer_id),
            manufacturer="AirPrint",
            model="Network printer",
            configuration_url=f"http://{self.printer.get('host', '')}/",
        )
