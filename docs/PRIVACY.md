# Data handling

The Mac reads the current user's Codex registry and rollout logs, then renders recent questions, replies and turn states locally. The preview API listens on `127.0.0.1`.

Weather requests send the configured coordinates to Open-Meteo. Bluetooth payloads use nonce-based authentication and AES-256-GCM encryption with a key provisioned over USB. Control, touch and telemetry packets use the session key for authentication.

Runtime files live in `state/`: collected conversations, rendered frames, reading position and pairing material. The Git ignore rules keep runtime data and local configuration separate from source files. Demo images use `examples/demo-state.json`.

USB maintenance uses key-authenticated SSH on the device's USB addresses. BLE controls support brightness, warmth, native controls, dashboard return and status.
