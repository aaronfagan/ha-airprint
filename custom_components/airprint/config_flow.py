from __future__ import annotations

from typing import Any

import voluptuous as vol
from homeassistant.config_entries import (
    ConfigEntry,
    ConfigFlow,
    ConfigFlowResult,
    ConfigSubentryFlow,
    SubentryFlowResult,
)
from homeassistant.const import CONF_HOST, CONF_PORT
from homeassistant.core import callback
from homeassistant.helpers.selector import (
    SelectSelector,
    SelectSelectorConfig,
    SelectSelectorMode,
    TextSelector,
)
from homeassistant.helpers.service_info.zeroconf import ZeroconfServiceInfo

from .const import DEFAULT_EMOJI, DEFAULT_PORT, DOMAIN, EMOJI, SUBENTRY


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

    async def async_step_confirm(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        if user_input is not None:
            return self.async_create_entry(
                title="AirPrint", data={CONF_HOST: self._host, CONF_PORT: self._port}
            )

        return self.async_show_form(
            step_id="confirm", description_placeholders={"host": self._host or ""}
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
        current = current or {}
        coordinator = self.hass.data[DOMAIN][self._get_entry().entry_id]

        addresses = [a for a in coordinator.discovered if a]
        if current.get("address"):
            addresses = list(dict.fromkeys([*addresses, current["address"]]))

        return vol.Schema(
            {
                vol.Required("name", default=current.get("name", "")): TextSelector(),
                vol.Optional("address", default=current.get("address", "")): SelectSelector(
                    SelectSelectorConfig(
                        options=addresses,
                        custom_value=True,
                        mode=SelectSelectorMode.DROPDOWN,
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
