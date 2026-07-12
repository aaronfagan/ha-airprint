from __future__ import annotations

from typing import Any

import voluptuous as vol
from homeassistant.config_entries import (
    ConfigEntry,
    ConfigFlow,
    ConfigFlowResult,
    OptionsFlow,
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

from .const import DEFAULT_EMOJI, DEFAULT_PORT, DOMAIN, EMOJI


class AirPrintConfigFlow(ConfigFlow, domain=DOMAIN):
    VERSION = 1

    def __init__(self) -> None:
        self._host: str | None = None
        self._port: int = DEFAULT_PORT

    @staticmethod
    @callback
    def async_get_options_flow(entry: ConfigEntry) -> AirPrintOptionsFlow:
        return AirPrintOptionsFlow()

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


class AirPrintOptionsFlow(OptionsFlow):
    def __init__(self) -> None:
        self._editing: str | None = None

    async def async_step_init(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        return self.async_show_menu(step_id="init", menu_options=["add", "edit", "remove"])

    @property
    def _coordinator(self):
        return self.hass.data[DOMAIN][self.config_entry.entry_id]

    async def async_step_edit(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        printers = await self._coordinator.async_get_printers()

        if user_input is not None:
            self._editing = user_input["printer"]
            return await self.async_step_edit_printer()

        return self.async_show_form(
            step_id="edit",
            data_schema=vol.Schema(
                {
                    vol.Required("printer"): SelectSelector(
                        SelectSelectorConfig(
                            options=[printer["name"] for printer in printers],
                            mode=SelectSelectorMode.LIST,
                        )
                    )
                }
            ),
        )

    async def async_step_edit_printer(
        self, user_input: dict[str, Any] | None = None
    ) -> ConfigFlowResult:
        errors: dict[str, str] = {}
        printers = await self._coordinator.async_get_printers()
        current = next((p for p in printers if p["name"] == self._editing), None)

        if current is None:
            return self.async_abort(reason="unknown_printer")

        if user_input is not None:
            current.update(
                {
                    "name": user_input["name"],
                    "address": user_input.get("address", ""),
                    "location": user_input.get("location", ""),
                    "emoji": user_input.get("emoji", DEFAULT_EMOJI),
                }
            )
            try:
                await self._coordinator.async_save_printers(printers)
            except Exception:
                errors["base"] = "cannot_save"
            else:
                return self.async_create_entry(title="", data={})

        addresses = list(dict.fromkeys(self._coordinator.discovered + [current.get("address", "")]))

        return self.async_show_form(
            step_id="edit_printer",
            errors=errors,
            data_schema=vol.Schema(
                {
                    vol.Required("name", default=current.get("name", "")): TextSelector(),
                    vol.Optional("address", default=current.get("address", "")): SelectSelector(
                        SelectSelectorConfig(
                            options=[a for a in addresses if a],
                            custom_value=True,
                            mode=SelectSelectorMode.DROPDOWN,
                        )
                    ),
                    vol.Optional("location", default=current.get("location", "")): TextSelector(),
                    vol.Optional(
                        "emoji", default=current.get("emoji", DEFAULT_EMOJI)
                    ): SelectSelector(
                        SelectSelectorConfig(options=EMOJI, mode=SelectSelectorMode.DROPDOWN)
                    ),
                }
            ),
            description_placeholders={"name": current.get("name", "")},
        )

    async def async_step_add(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        errors: dict[str, str] = {}

        if user_input is not None:
            printers = await self._coordinator.async_get_printers()
            printers.append(
                {
                    "name": user_input["name"],
                    "address": user_input.get("address", ""),
                    "location": user_input.get("location", ""),
                    "emoji": user_input.get("emoji", DEFAULT_EMOJI),
                }
            )
            try:
                await self._coordinator.async_save_printers(printers)
            except Exception:
                errors["base"] = "cannot_save"
            else:
                return self.async_create_entry(title="", data={})

        discovered = list(self._coordinator.discovered)

        return self.async_show_form(
            step_id="add",
            errors=errors,
            data_schema=vol.Schema(
                {
                    vol.Required("name"): TextSelector(),
                    vol.Optional("address", default=""): SelectSelector(
                        SelectSelectorConfig(
                            options=discovered,
                            custom_value=True,
                            mode=SelectSelectorMode.DROPDOWN,
                        )
                    ),
                    vol.Optional("location", default=""): TextSelector(),
                    vol.Optional("emoji", default=DEFAULT_EMOJI): SelectSelector(
                        SelectSelectorConfig(options=EMOJI, mode=SelectSelectorMode.DROPDOWN)
                    ),
                }
            ),
            description_placeholders={
                "found": ", ".join(discovered) if discovered else "nothing new"
            },
        )

    async def async_step_remove(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        printers = await self._coordinator.async_get_printers()
        names = [printer["name"] for printer in printers]

        if user_input is not None:
            keep = [p for p in printers if p["name"] not in user_input["remove"]]
            await self._coordinator.async_save_printers(keep)
            return self.async_create_entry(title="", data={})

        return self.async_show_form(
            step_id="remove",
            data_schema=vol.Schema(
                {
                    vol.Required("remove"): SelectSelector(
                        SelectSelectorConfig(
                            options=names, multiple=True, mode=SelectSelectorMode.LIST
                        )
                    )
                }
            ),
        )
