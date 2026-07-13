from __future__ import annotations

from homeassistant.helpers.device_registry import DeviceInfo
from homeassistant.helpers.update_coordinator import CoordinatorEntity

from .const import DEVICE_NAME, DOMAIN, device_id, label
from .coordinator import AirPrintCoordinator


class AirPrintEntity(CoordinatorEntity[AirPrintCoordinator]):
    _attr_has_entity_name = True

    def __init__(self, coordinator: AirPrintCoordinator, printer: dict, key: str) -> None:
        super().__init__(coordinator)
        self._name = label(printer) or DEVICE_NAME
        self._model = printer.get("discovered_name") or self._name
        self._device = printer.get("device", "")
        self._attr_unique_id = f"{device_id(self._device)}_{key}"

    @property
    def printer(self) -> dict:
        return self.coordinator.data.get(self._device, {})

    @property
    def available(self) -> bool:
        return super().available and self._device in self.coordinator.data

    @property
    def device_info(self) -> DeviceInfo:
        host = self.printer.get("host", "")
        return DeviceInfo(
            identifiers={(DOMAIN, device_id(self._device))},
            name=self._name,
            manufacturer="AirPrint",
            model=self._model,
            configuration_url=f"http://{host}/" if host else None,
        )
