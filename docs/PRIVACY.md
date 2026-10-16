# Data handling

The collector reads the current user's local Codex registry and rollout logs without modifying them. It publishes recent questions, replies and turn states to a loopback-only API and locally rendered PNG. It does not call the OpenAI API or upload conversations to a rendering service.

Weather requests send the configured coordinates to Open-Meteo. The Mac-to-Kindle transport uses a provisioned shared key, nonce-based authentication and AES-256-GCM payload encryption. The native system Bluetooth pairing flow is separate from this application protocol. Bounded control and telemetry packets are authenticated with the session key.

`state/` can contain conversation text, rendered frames, UI preferences and pairing material. Anyone with access to the running local account or the paired Kindle can view these conversations. Keep those files and screenshots out of source control and public issue reports. The collector is coupled to local Codex storage formats; review it before using it with different versions.

SSH maintenance is restricted to USB addresses and provisioned keys, with password authentication disabled. No arbitrary shell command is accepted over the BLE control API. Do not expose the HTTP service through a LAN proxy or a public tunnel.
