# CLAUDE.md

An AirPrint bridge for Home Assistant, in two halves:

- **`airprint/`** — the add-on. CUPS + Avahi + the printer's driver. Published as a container image.
- **`custom_components/airprint/`** — the integration. The setup screens and the sensors.

The integration **owns the printer list** and writes it into the add-on's options through the Supervisor API. Anything hand-edited in the add-on's YAML is overwritten on the next sync — printer settings belong in the integration's form.

## Developing

Iterate with `scripts/dev.sh`. It pushes the working tree onto the Home Assistant box, strips the `image:` key so the Supervisor **builds the add-on locally**, and rebuilds it. **No version bump, nothing published, no tags.**

```bash
scripts/dev.sh              # add-on + integration, then restart Home Assistant
scripts/dev.sh addon        # add-on only
scripts/dev.sh integration  # integration only
```

Two things that will waste your time if you forget them:

- **The add-on only picks up changes on a rebuild.** `ha apps rebuild` does it without a version bump. A plain restart re-runs the *existing* image.
- **The integration only picks up changes when Home Assistant Core restarts.** Copying files in is not enough.

Verify against the real thing rather than asserting. The add-on's log and `/srv/status.json` (served on `:8099`) say what it actually did.

## Releasing

The version lives in **two files that must always match**, because the Supervisor pulls `<image>:<version from config.yaml>`:

- `airprint/config.yaml` → `version:`
- `custom_components/airprint/manifest.json` → `"version"`

Never edit them by hand. Use:

```bash
scripts/version.sh 1.11.0        # sets both, commits, tags
git push origin main && git push origin v1.11.0
```

Pushing the tag builds `amd64` and `aarch64`, publishes one multi-arch image to GHCR, and cuts a GitHub release. CI **fails the release** if the tag and the two files disagree, so they cannot drift.

**Patch** for fixes and copy. **Minor** for features. **Major** only for something that breaks an existing config.

## Keep the README current

The README is the front door. **Any change to features, options, fields or behaviour lands in the README in the same commit.** Someone who finds this repo should read it once and have their printer printing.

Write for **a Home Assistant user who wants their printer on AirPrint** — not for the author, and not as a story about the problem. Keep it light:

- Lead with whether they need this at all, then install, then adding the printer. Say "that's it" where they are actually done.
- Document what a user sees and touches: the fields, the sensors, what to do when a driver is missing.
- Leave out internals unless they change what a user does.
- Examples are copied from real output — re-check them when behaviour changes.

## Conventions

- **Home Assistant's conventions win.** Sentence-case entity names, its device classes and their fixed state text, its selectors. If a request conflicts with one, say so before deviating.
- **The data model mirrors the UI.** One key per field the user sees.
- **Proprietary drivers are never bundled.** They are downloaded at runtime from a URL on the printer, or dropped into `/share/airprint/drivers`. A published image ships only the free driver set — that is what makes it publishable at all.
