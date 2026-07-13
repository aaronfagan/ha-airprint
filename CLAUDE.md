# CLAUDE.md

An AirPrint bridge for Home Assistant: an **add-on** (`airprint/`, the CUPS print server) and an **integration** (`custom_components/airprint/`, the setup screens and sensors). The integration owns the printer list and writes it into the add-on's options through the Supervisor API.

## Keep the README current

The README is the front door. **Any change to features, options, fields or behaviour must land in the README in the same commit.** A user who finds this repo should be able to read it once and have their printer printing.

Write it for **someone who uses Home Assistant and wants their printer on AirPrint** — not for the author, and not as a story about the problem. Keep it light:

- Lead with whether they need this at all, then install, then adding the printer. Say "that's it" at the point they are actually done.
- Document what a user sees and touches: the fields in the form, the sensors, what to do when a driver is missing.
- Leave out the internals unless they change what a user does.
- Keep the examples honest — they are copied from real output, so re-check them when behaviour changes.

## Versioning

`airprint/config.yaml` and `custom_components/airprint/manifest.json` carry the **same version**, bumped together, and tagged (`v1.2.3`). Patch for fixes and copy, minor for features, major only for something that breaks an existing config.

## Conventions

- **Home Assistant's conventions win.** Sentence-case entity names, its device classes and their fixed state text, its selectors. If a request conflicts with one, say so before deviating.
- **The integration is the source of truth.** It rewrites the add-on's printer list, so anything hand-edited in the add-on's YAML is overwritten on the next restart. Printer settings belong in the integration's form.
- **The data model mirrors the UI.** One key per field the user sees.
