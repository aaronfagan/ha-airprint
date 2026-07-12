from __future__ import annotations

import logging
import os
from datetime import timedelta

import aiohttp
from homeassistant.core import HomeAssistant
from homeassistant.helpers.aiohttp_client import async_get_clientsession
from homeassistant.helpers.update_coordinator import DataUpdateCoordinator, UpdateFailed

from .const import DOMAIN, SUPERVISOR, UPDATE_INTERVAL

_LOGGER = logging.getLogger(__name__)


class AirPrintCoordinator(DataUpdateCoordinator):
    def __init__(self, hass: HomeAssistant, host: str, port: int) -> None:
        super().__init__(
            hass,
            _LOGGER,
            name=DOMAIN,
            update_interval=timedelta(seconds=UPDATE_INTERVAL),
        )
        self._url = f"http://{host}:{port}/status.json"
        self._session = async_get_clientsession(hass)
        self.slug: str | None = None
        self.discovered: list[str] = []

    async def _async_update_data(self) -> dict:
        try:
            async with self._session.get(
                self._url, timeout=aiohttp.ClientTimeout(total=15)
            ) as response:
                response.raise_for_status()
                data = await response.json(content_type=None)
        except Exception as err:
            raise UpdateFailed(f"Cannot reach the AirPrint add-on: {err}") from err

        self.slug = data.get("slug") or self.slug
        self.discovered = data.get("discovered", [])

        return {printer["id"]: printer for printer in data.get("printers", [])}

    async def _supervisor(self, method: str, path: str, json: dict | None = None) -> dict:
        token = os.environ.get("SUPERVISOR_TOKEN")
        if not token:
            raise RuntimeError("Not running under the Home Assistant Supervisor")

        async with self._session.request(
            method,
            f"{SUPERVISOR}/{path}",
            headers={"Authorization": f"Bearer {token}"},
            json=json,
            timeout=aiohttp.ClientTimeout(total=60),
        ) as response:
            response.raise_for_status()
            return await response.json()

    async def async_get_printers(self) -> list[dict]:
        if not self.slug:
            return []
        info = await self._supervisor("GET", f"addons/{self.slug}/info")
        return info.get("data", {}).get("options", {}).get("printers", [])

    async def async_save_printers(self, printers: list[dict]) -> None:
        if not self.slug:
            raise RuntimeError("The AirPrint add-on was not found")
        await self._supervisor(
            "POST", f"addons/{self.slug}/options", {"options": {"printers": printers}}
        )
        await self._supervisor("POST", f"addons/{self.slug}/restart")
