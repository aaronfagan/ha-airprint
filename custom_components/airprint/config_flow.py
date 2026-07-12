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
    SelectOptionDict,
    SelectSelector,
    SelectSelectorConfig,
    SelectSelectorMode,
    TextSelector,
)
from homeassistant.helpers.service_info.zeroconf import ZeroconfServiceInfo

from .const import DEFAULT_EMOJI, DEFAULT_PORT, DOMAIN, EMOJI, SUBENTRY, device_name


def printer_schema(
    discovered: list[dict], current: dict[str, Any] | None = None, editing: bool = False
) -> vol.Schema:
    current = current or {}

    fields: dict[Any, Any] = {vol.Optional("name"): TextSelector()}

    if not editing:
        if len(discovered) > 1:
            fields[vol.Required("device", default=discovered[0]["device"])] = SelectSelector(
                SelectSelectorConfig(
                    options=[
                        SelectOptionDict(
                            value=found["device"],
                            label=f"{found['name']} ({found['address']})",
                        )
                        for found in discovered
                    ],
                    mode=SelectSelectorMode.LIST,
                )
            )
        elif not discovered:
            fields[vol.Required("device", default="")] = TextSelector()

    fields[vol.Optional("location")] = TextSelector()
    fields[vol.Optional("emoji")] = SelectSelector(
        SelectSelectorConfig(options=EMOJI, custom_value=True, mode=SelectSelectorMode.DROPDOWN)
    )

    return vol.Schema(fields)


def printer_suggested(discovered: list[dict], current: dict[str, Any] | None = None) -> dict:
    current = current or {}
    return {
        "name": current.get("name")
        or (discovered[0].get("name", "") if discovered else ""),
        "location": current.get("location", ""),
        "emoji": current.get("emoji", DEFAULT_EMOJI),
    }


def printer_data(
    user_input: dict[str, Any], discovered: list[dict], current: dict[str, Any] | None = None
) -> dict[str, Any]:
    current = current or {}

    device = user_input.get("device") or current.get("device")
    found = next((d for d in discovered if d["device"] == device), None)

    if not device and discovered:
        device = discovered[0]["device"]
        found = discovered[0]

    discovered_name = (
        current.get("discovered_name")
        or (found or {}).get("name")
        or device_name(device or "")
    )
    name = user_input.get("name", "").strip() or discovered_name

    return {
        "name": name,
        "discovered_name": discovered_name,
        "device": device or "",
        "location": user_input.get("location", ""),
        "emoji": user_input.get("emoji", ""),
    }


class AirPrintConfigFlow(ConfigFlow, domain=DOMAIN):
    VERSION = 1

    def __init__(self) -> None:
        self._host: str | None = None
        self._port: int = DEFAULT_PORT
        self._discovered: list[dict] = []

    @classmethod
    @callback
    def async_get_supported_subentry_types(
        cls, config_entry: ConfigEntry
    ) -> dict[str, type[ConfigSubentryFlow]]:
        return {SUBENTRY: PrinterSubentryFlow}

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

    async def async_step_zeroconf(self, discovery_info: ZeroconfServiceInfo) -> ConfigFlowResult:
        self._host = discovery_info.host
        self._port = discovery_info.port or DEFAULT_PORT

        await self.async_set_unique_id(DOMAIN)
        self._abort_if_unique_id_configured(updates={CONF_HOST: self._host, CONF_PORT: self._port})

        status = await self._async_status()
        self._discovered = status.get("discovered", [])
        printers = status.get("printers", [])

        if self._discovered:
            name = self._discovered[0].get("name") or "AirPrint"
        elif printers:
            name = printers[0].get("name") or "AirPrint"
        else:
            name = "AirPrint"

        self.context["title_placeholders"] = {"host": self._host, "name": name}

        if printers:
            return self.async_create_entry(
                title="AirPrint", data={CONF_HOST: self._host, CONF_PORT: self._port}
            )

        return await self.async_step_confirm()

    async def async_step_confirm(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        data = {CONF_HOST: self._host, CONF_PORT: self._port}

        if user_input is not None:
            printer = printer_data(user_input, self._discovered)
            return self.async_create_entry(
                title="AirPrint",
                data=data,
                subentries=[
                    ConfigSubentryData(
                        data=printer,
                        subentry_type=SUBENTRY,
                        title=printer["name"],
                        unique_id=printer["device"] or printer["name"],
                    )
                ],
            )

        return self.async_show_form(
            step_id="confirm",
            data_schema=self.add_suggested_values_to_schema(
                printer_schema(self._discovered), printer_suggested(self._discovered)
            ),
            description_placeholders={
                "host": self._host or "",
                "default": printer_suggested(self._discovered)["name"],
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
    @property
    def _discovered(self) -> list[dict]:
        return self.hass.data[DOMAIN][self._get_entry().entry_id].discovered

    async def async_step_user(self, user_input: dict[str, Any] | None = None) -> SubentryFlowResult:
        if user_input is not None:
            printer = printer_data(user_input, self._discovered)
            return self.async_create_entry(
                title=printer["name"],
                data=printer,
                unique_id=printer["device"] or printer["name"],
            )

        return self.async_show_form(
            step_id="user",
            data_schema=self.add_suggested_values_to_schema(
                printer_schema(self._discovered), printer_suggested(self._discovered)
            ),
            description_placeholders={"default": printer_suggested(self._discovered)["name"]},
        )

    async def async_step_reconfigure(
        self, user_input: dict[str, Any] | None = None
    ) -> SubentryFlowResult:
        subentry = self._get_reconfigure_subentry()
        current = dict(subentry.data)

        if user_input is not None:
            printer = printer_data(user_input, self._discovered, current)
            return self.async_update_and_abort(
                self._get_entry(), subentry, title=printer["name"], data=printer
            )

        return self.async_show_form(
            step_id="reconfigure",
            data_schema=self.add_suggested_values_to_schema(
                printer_schema(self._discovered, current, editing=True),
                printer_suggested(self._discovered, current),
            ),
            description_placeholders={
                "default": current.get("discovered_name") or current.get("name", "")
            },
        )
