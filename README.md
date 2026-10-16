# Kindle Desk

An interactive, monochrome desk dashboard for a jailbroken Kindle and a Mac. A large clock, weather, recent Codex questions and replies, Mac resource usage, and the Kindle's own battery level — sent over Bluetooth without requiring a shared Wi-Fi network.

[中文说明](docs/README.zh-CN.md) · [Setup](docs/SETUP.md) · [Protocol](docs/PROTOCOL.md) · [License](LICENSE)

## Interface

- Portrait 1236 × 1648 layout, designed for e-ink.
- Chinese / English switch on the panel; the choice survives a service restart. Conversation text stays in its original language.
- Tap a conversation to read its full question and reply; use previous / next and return to the overview.
- Two conversation-turn states: **In progress** and **Completed**. Completed means the reply ended, not that every project objective succeeded.
- Native Kindle top-edge quick settings remain available for brightness and warm-light adjustments.
- CPU, memory, APFS storage and authenticated Kindle battery telemetry. Stale readings are marked.

![English panel with fictional example data](docs/images/panel-en.png)

The image uses only fictional demonstration conversations. Render either language with `.venv/bin/python scripts/render-demo.py`.

## Supported environment and status

Development hardware is a Kindle Paperwhite 5 Signature Edition, firmware 5.18.3, with ARMv7 Linux and a 1236 × 1648 display, plus an Apple Silicon Mac. Other Kindle generations and firmware versions have not been qualified. This project does not provide a jailbreak or flash replacement firmware.

The dashboard runs as an ordinary GTK/X11 application while the native X server, framework and window manager remain running. The boot job starts after `framework_ready` and has no respawn loop. Installation leaves autostart off; qualify manual mode before enabling it. Native quick-settings brightness and repeated swipes have been physically verified with the preceding receiver. New touch forwarding and battery telemetry still require end-to-end physical qualification; cold-boot autostart is not yet qualified. Updating the ad-hoc-signed Mac app can require a new macOS Bluetooth authorization.

## Try the Mac preview

Requires Python 3.10+ and Node is only needed for optional JavaScript syntax checks.

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.lock
.venv/bin/python -m playwright install chromium
.venv/bin/python desk.py --port 8791
```

Open **http://127.0.0.1:8791/panel/**. The preview works without a Kindle; battery remains unavailable until the receiver reports it. Codex data is read from the current user's local SQLite registry and JSONL logs in read-only mode. No OpenAI API key is required. An unsupported local log format may yield no conversations.

Copy `config/example.json` to `config/local.json` to set coordinates, city, timezone, refresh intervals and the initial UI language (`zh` or `en`). Runtime state defaults to `state/`; set `KINDLE_DESK_STATE_DIR` to keep it elsewhere. Set `KINDLE_DESK_CHROMIUM` to pin a Chromium executable for a service installation. System fonts render locally and are not distributed.

The macOS BLE app, device builds, USB provisioning and recovery procedures are documented in [Setup](docs/SETUP.md). Device SDK headers, stock libraries and jailbreak utilities must be obtained separately. There are no bundled firmware images or ready-to-flash binaries.

## Repository map

| Path | Purpose |
| --- | --- |
| `panel/` | Shared HTML/CSS/JS interface for browser and Kindle screenshots |
| `desk.py`, `conversations.py` | Read-only collectors, loopback API and rendering worker |
| `panel_render.py`, `mac_metrics.py` | Chromium-to-PNG rendering and local resources |
| `mac/` | CoreBluetooth peripheral and maintenance UI |
| `kindle/` | BLE client, native GTK viewer, lifecycle and recovery scripts |
| `scripts/` | Build and launch entry points |
| `tests/` | Conversation parsing, control bounds and device lifecycle checks |
| `vendor/` | Third-party notices and retained upstream helpers |
| `docs/` | Setup, protocol, privacy and Chinese documentation |

## Privacy and transport

The HTTP server binds to `127.0.0.1`, without cross-origin access. Rendering is local. Conversation text is sent only to the paired Kindle through an application-authenticated, AES-256-GCM encrypted BLE session. The shared pairing key is provisioned over USB, never transmitted over BLE. See [Protocol](docs/PROTOCOL.md) and [Privacy](docs/PRIVACY.md).

Do not commit runtime state, real conversation screenshots, books, device backups, SSH material, pairing keys or local configuration. The public repository starts from a reviewed source snapshot and does not contain personal deployment history.

## Checks

```sh
.venv/bin/python -m pip install pytest
.venv/bin/python -m pytest -q
node --check panel/panel.js
```

## Credits

Weather data: [Open-Meteo](https://open-meteo.com/), [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Attribution is kept here rather than on the panel. Icons: [Tabler Icons](https://github.com/tabler/tabler-icons), MIT, version 3.34.1. See `panel/assets/SOURCE.json` and `vendor/LICENSE.tabler-icons`.

Earlier renderer/system helpers derive from [codecube/kindle-mcp-dashboard](https://github.com/codecube/kindle-mcp-dashboard), MIT, commit `aafc74f035597a1fca8ffd39ce1f4c554e8438c2`. Bluetooth support builds against [Sighery/kindlebt](https://github.com/Sighery/kindlebt), MIT, commit `59e1d8e69a52e3cd58cee6fcc416d1774ad55791`, and [rxi/log.c](https://github.com/rxi/log.c), MIT, commit `f9ea34994bd58ed342d2245cd4110bb5c6790153`. Their notices are retained in `vendor/`. Proprietary device libraries and SDK files are not redistributed.

Original project code is available under the MIT license. Third-party material retains its own license. This is an independent project, unaffiliated with Amazon or OpenAI.
