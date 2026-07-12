from __future__ import annotations

from homeassistant.helpers.device_registry import DeviceInfo
from homeassistant.helpers.update_coordinator import CoordinatorEntity

from .const import DOMAIN, queue_id
from .coordinator import AirPrintCoordinator


class AirPrintEntity(CoordinatorEntity[AirPrintCoordinator]):
    _attr_has_entity_name = True

    def __init__(self, coordinator: AirPrintCoordinator, printer: dict, key: str) -> None:
        super().__init__(coordinator)
        self._name = printer.get("name", "")
        self._queue = queue_id(self._name)
        self._attr_unique_id = f"{self._queue}_{key}"

    @property
    def printer(self) -> dict:
        return self.coordinator.data.get(self._queue, {})

    @property
    def available(self) -> bool:
        return super().available and self._queue in self.coordinator.data

    @property
    def device_info(self) -> DeviceInfo:
        host = self.printer.get("host", "")
        return DeviceInfo(
            identifiers={(DOMAIN, self._queue)},
            name=self._name,
            manufacturer="AirPrint",
            model="Network printer",
            configuration_url=f"http://{host}/" if host else None,
        )
