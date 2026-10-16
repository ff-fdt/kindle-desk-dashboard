# Setup and recovery

## Mac preview

Follow the README virtual environment steps. Python 3.10+, Pillow, psutil, Playwright and Chromium are required. Use the committed lock file. `KINDLE_DESK_STATE_DIR` selects a persistent runtime directory. `KINDLE_DESK_CHROMIUM` pins an installed browser executable; otherwise the renderer checks macOS Playwright caches before using the Playwright-managed browser.

The renderer uses macOS system fonts including CJK fallbacks. The current resource collector targets macOS APFS `/System/Volumes/Data`.

## Mac Bluetooth peripheral

```sh
sh scripts/build-mac.sh
```

Requires macOS Command Line Tools / Swift with CoreBluetooth, AppKit and CryptoKit. The output is `build/Kindle Desk Bluetooth.app`. Provision a random **32-byte binary** `pairing-key.bin` into the persistent state directory. Transfer the exact same binary key to `/mnt/us/kindle-desk/pairing-key.bin` over your established USB maintenance connection.

```sh
python3 -c "import secrets,pathlib; p=pathlib.Path('state/pairing-key.bin'); p.parent.mkdir(exist_ok=True); p.write_bytes(secrets.token_bytes(32)); p.chmod(0o600)"
```

For a new pairing, generate a key once and install the same key on both devices. Run the app executable with the state directory as its sole argument. For background startup, fill `mac/LaunchAgent.plist.template` with absolute `@SOURCE@`, `@PYTHON@` and `@STATE@` paths. `scripts/run-mac.sh` starts both processes. The source directory must include the built Bluetooth app. Allow Bluetooth access when macOS prompts.

## Kindle prerequisites and builds

Use a jailbroken Paperwhite 5 with a root maintenance connection. Build dependencies:

- Zig 0.17.0 (the compiler used during development).
- `kindlebt` at `59e1d8e69a52e3cd58cee6fcc416d1774ad55791`.
- `log.c` at `f9ea34994bd58ed342d2245cd4110bb5c6790153`.
- Compatible ACE SDK includes and the device's stock `libace_bt.so`.
- Suitable Dropbear maintenance binaries and, for setup notices, FBInk supplied by the device's launcher environment.

Set `ZIG`, `KINDLEBT_SOURCE`, `LOGC_SOURCE`, `ACE_INCLUDE` and `ACE_LIB_DIR` to those local inputs, then:

```sh
sh scripts/build-kindlebt.sh
KINDLEBT_LIB="$PWD/build" sh scripts/build-kindle.sh
sh scripts/build-viewer.sh
```

Compile `ble-client` and `libkindlebt.so` together. The build targets ARMv7 hard-float Linux.

## Device file layout

```text
/mnt/us/kindle-desk/
  bin/ble-client
  bin/dashboard-viewer
  bin/dropbear              # external maintenance dependency
  lib/libkindlebt.so
  pairing-key.bin           # private, provisioned over USB
  kindle-desk.conf
  *.sh                     # scripts from kindle/
```

Provision the authorized root SSH public key using the device's existing root maintenance arrangement. `usb-service.sh` restricts Dropbear to USB addresses on port 2222 and disables password login and forwarding. The host must be on a matching USB subnet.

Run `install-appliance.sh` as root to install the Upstart job and bootstrap. Use `start-manual.sh` for the current session, or `enable-autostart.sh` for startup.

The display is an ordinary GTK/X11 window. A top-edge swipe of at least 120 px opens the native quick-settings shade. Native X, framework, awesome and pillow keep running. The BLE client reconnects and keeps the last frame when the Mac is absent.

## Autostart and recovery

Run `enable-autostart.sh` to enable startup. It checks the installed job and an existing displayed frame before creating `/var/local/kindle-desk/enabled`. The boot job waits for `framework_ready`, delays bootstrap and has no respawn loop. Restart through the Kindle system menu.

To disable the dashboard and return to native mode, run `/bin/sh /mnt/us/kindle-desk/restore-reader.sh` as root. It removes the enable marker and disables the job without forcing a reboot.
