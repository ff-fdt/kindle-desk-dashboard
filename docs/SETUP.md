# Setup and recovery

## Mac preview

Follow the README virtual environment steps. Python 3.10+, Pillow, psutil, Playwright and Chromium are required. Use the committed lock file. `KINDLE_DESK_STATE_DIR` selects a persistent runtime directory. `KINDLE_DESK_CHROMIUM` pins an installed browser executable; otherwise the renderer checks macOS Playwright caches before using the Playwright-managed browser.

The renderer uses macOS system fonts including CJK fallbacks. These fonts are not included. The current resource collector targets macOS APFS `/System/Volumes/Data`.

## Mac Bluetooth peripheral

```sh
sh scripts/build-mac.sh
```

Requires macOS Command Line Tools / Swift with CoreBluetooth, AppKit and CryptoKit. The output is `build/Kindle Desk Bluetooth.app`. Provision a random **32-byte binary** `pairing-key.bin` into the persistent state directory. Transfer the exact same binary key to `/mnt/us/kindle-desk/pairing-key.bin` over your established USB maintenance connection. Never put it in Git.

```sh
python3 -c "import secrets,pathlib; p=pathlib.Path('state/pairing-key.bin'); p.parent.mkdir(exist_ok=True); p.write_bytes(secrets.token_bytes(32)); p.chmod(0o600)"
```

Generate only for a new pairing; overwriting an existing key breaks that pairing. Run the app executable with the state directory as its sole argument. For background startup, fill `mac/LaunchAgent.plist.template` with absolute `@SOURCE@`, `@PYTHON@` and `@STATE@` paths. `scripts/run-mac.sh` starts both processes. The source directory must include the built Bluetooth app. macOS may request Bluetooth access again after an ad-hoc-signed binary update.

## Kindle prerequisites and builds

Use an already jailbroken Paperwhite 5 with a working root maintenance connection. Back up books and annotations first. Required external inputs are not bundled:

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

Always compile `ble-client` and `libkindlebt.so` together; the upstream prebuilt library has a different ABI. Build scripts target ARMv7 hard-float Linux. They do not install jailbreaks, fetch proprietary SDKs, or flash firmware.

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

Provision the authorized root SSH public key using the device's existing root maintenance arrangement. `usb-service.sh` restricts Dropbear to USB addresses on port 2222 and disables password login and forwarding. The host must be on a matching USB subnet; do not alter campus Wi-Fi for this.

Review and run `install-appliance.sh` as root. It installs the Upstart job and bootstrap but leaves the persistent enable marker absent. `start-manual.sh` starts a session using a `/tmp` marker, so manual mode does not survive reboot.

The display is an ordinary GTK/X11 window. A top-edge swipe of at least 120 px opens the native quick-settings shade. Do not stop X, framework, awesome or pillow. The BLE client reconnects and keeps the last frame when the Mac is absent.

## Autostart and recovery

After physically verifying manual display, Bluetooth, touch interaction, native brightness, return from native controls and a recovery path, run `enable-autostart.sh`. It checks the installed job and an existing displayed frame before creating `/var/local/kindle-desk/enabled`. The boot job waits for `framework_ready`, delays bootstrap and has no respawn loop. Perform an orderly restart and separately verify cold boot.

To disable the dashboard and return to native mode, run `/bin/sh /mnt/us/kindle-desk/restore-reader.sh` as root. It removes the enable marker and disables the job without forcing a reboot. Keep a functioning USB root connection while qualifying boot behavior. Hardware qualification is model/firmware-specific; local lifecycle tests do not establish cold-boot success.
