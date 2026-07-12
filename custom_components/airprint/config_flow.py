from __future__ import annotations

from typing import Any

import aiohttp
import voluptuous as vol
from homeassistant.config_entries import (
    ConfigEntry,
    ConfigFlow,
    ConfigFlowResult,
    ConfigSubentryData,
    ConfigSubentryFlow,
    SubentryFlowResult,
)
from homeassistant.const import CONF_HOST, CONF_PORT
from homeassistant.core import callback
from homeassistant.helpers.aiohttp_client import async_get_clientsession
from homeassistant.helpers.selector import (
    SelectSelector,
    SelectSelectorConfig,
    SelectSelectorMode,
    TextSelector,
)
from homeassistant.helpers.service_info.zeroconf import ZeroconfServiceInfo

from .const import DEFAULT_EMOJI, DEFAULT_PORT, DOMAIN, EMOJI, SUBENTRY


def printer_schema(discovered: list[str], current: dict[str, Any] | None = None) -> vol.Schema:
    current = current or {}

    addresses = [address for address in discovered if address]
    if current.get("address"):
        addresses = list(dict.fromkeys([*addresses, current["address"]]))

    return vol.Schema(
        {
            vol.Required("name", default=current.get("name", "")): TextSelector(),
            vol.Optional("address", default=current.get("address", "")): SelectSelector(
                SelectSelectorConfig(
                    options=addresses, custom_value=True, mode=SelectSelectorMode.DROPDOWN
                )
            ),
            vol.Optional("location", default=current.get("location", "")): TextSelector(),
            vol.Optional("emoji", default=current.get("emoji", DEFAULT_EMOJI)): SelectSelector(
                SelectSelectorConfig(
                    options=EMOJI, custom_value=True, mode=SelectSelectorMode.DROPDOWN
                )
            ),
        }
    )


class AirPrintConfigFlow(ConfigFlow, domain=DOMAIN):
    VERSION = 1

    def __init__(self) -> None:
        self._host: str | None = None
        self._port: int = DEFAULT_PORT

    @classmethod
    @callback
    def async_get_supported_subentry_types(
        cls, config_entry: ConfigEntry
    ) -> dict[str, type[ConfigSubentryFlow]]:
        return {SUBENTRY: PrinterSubentryFlow}

    async def async_step_zeroconf(self, discovery_info: ZeroconfServiceInfo) -> ConfigFlowResult:
        self._host = discovery_info.host
        self._port = discovery_info.port or DEFAULT_PORT

        await self.async_set_unique_id(DOMAIN)
        self._abort_if_unique_id_configured(updates={CONF_HOST: self._host, CONF_PORT: self._port})

        self.context["title_placeholders"] = {"host": self._host}
        return await self.async_step_confirm()

    async def _async_status(self) -> dict[str, Any]:
        session = async_get_clientsession(self.hass)
        try:
            async with session.get(
                f"http://{self._host}:{self._port}/status.json",
                timeout=aiohttp.ClientTimeout(total=15),
            ) as response:
                response.raise_for_status()
                return await response.json(content_type=None)
        except Exception:
            return {}

    async def async_step_confirm(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        data = {CONF_HOST: self._host, CONF_PORT: self._port}

        if user_input is not None:
            return self.async_create_entry(
                title="AirPrint",
                data=data,
                subentries=[
                    ConfigSubentryData(
                        data=user_input,
                        subentry_type=SUBENTRY,
                        title=user_input["name"],
                        unique_id=user_input["name"],
                    )
                ],
            )

        status = await self._async_status()

        if status.get("printers"):
            return self.async_create_entry(title="AirPrint", data=data)

        discovered = [address for address in status.get("discovered", []) if address]

        return self.async_show_form(
            step_id="confirm",
            data_schema=printer_schema(discovered),
            description_placeholders={
                "host": self._host or "",
                "found": ", ".join(discovered) if discovered else "no printers yet",
            },
        )

    async def async_step_user(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        if user_input is not None:
            await self.async_set_unique_id(DOMAIN)
            self._abort_if_unique_id_configured()
            return self.async_create_entry(title="AirPrint", data=user_input)

        return self.async_show_form(
            step_id="user",
            data_schema=vol.Schema(
                {
                    vol.Required(CONF_HOST): str,
                    vol.Required(CONF_PORT, default=DEFAULT_PORT): int,
                }
            ),
        )


class PrinterSubentryFlow(ConfigSubentryFlow):
    def _schema(self, current: dict[str, Any] | None = None) -> vol.Schema:
        coordinator = self.hass.data[DOMAIN][self._get_entry().entry_id]
        return printer_schema(coordinator.discovered, current)

    async def async_step_user(self, user_input: dict[str, Any] | None = None) -> SubentryFlowResult:
        if user_input is not None:
            return self.async_create_entry(title=user_input["name"], data=user_input)

        return self.async_show_form(step_id="user", data_schema=self._schema())

    async def async_step_reconfigure(
        self, user_input: dict[str, Any] | None = None
    ) -> SubentryFlowResult:
        subentry = self._get_reconfigure_subentry()

        if user_input is not None:
            return self.async_update_and_abort(
                self._get_entry(),
                subentry,
                title=user_input["name"],
                data=user_input,
            )

        return self.async_show_form(
            step_id="reconfigure", data_schema=self._schema(dict(subentry.data))
        )
