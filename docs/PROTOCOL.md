# Bluetooth protocol v2

Service UUID `E07E1000-7A51-4C44-A65A-5D45534B0001`. Characteristics end in `1001` (info/read/notify), `1002` (control/write), `1003` (data/read/notify), `1004` (authenticated device command/read).

The shared 32-byte binary key is provisioned over USB and never sent over BLE. `00` resets the session; an unauthenticated INFO read returns a fresh 16-byte nonce. `01 + HMAC-SHA256(key, "kindle-desk-auth-v2" || nonce)` authenticates. The session key is `HMAC-SHA256(key, "kindle-desk-data-v2" || nonce)`. Challenges expire after 60 seconds and sessions after five idle minutes.

`02` pins JSON and `05` pins a portrait PNG. Encryption uses AES-256-GCM with random 12-byte nonce and 16-byte tag. Wire format: nonce || ciphertext || tag. INFO contains `v,bytes,chunk,pages,revision,sha256,format`; SHA-256 covers encrypted bytes and the revision is its first 16 hex digits.

Subscribe to DATA, then `07` streams the pinned payload with CoreBluetooth backpressure. Each notification starts with a uint32-LE offset. The receiver checks order, length, SHA-256, GCM authentication and PNG validity before replacing the last frame. `03 + uint16-LE page` retains a page-read fallback. `04 + 16 ASCII revision bytes + HMAC-SHA256(session_key, preceding bytes)` acknowledges receipt; `06` similarly acknowledges completed GTK/X11 drawing and synchronization.

Device commands use a separate characteristic: 16 ASCII hex sequence bytes, one opcode, one level, then HMAC-SHA256 over those 18 bytes. Opcodes allow brightness, warmth, native mode, dashboard and status only. Values are bounded 0–24. Opcode `08` sends the device execution result; the HTTP response supplies the queue identifier.

Opcode `09` reports telemetry: one opcode byte, uint32-LE counter, five bytes (battery percent, charging, brightness, warmth, mode), then HMAC-SHA256 over the first 10 bytes. Battery is 0–100, charging 0/1, levels 0–24, mode 0/1; 255 denotes unavailable values except mode. The Mac rejects non-monotonic counters within a session.

Opcode `0A` carries an authenticated tap (16 hex sequence bytes, uint16-LE x and y, HMAC-SHA256). Taps inside the refresh button at x=934..1187, y=1518..1575 request a fresh snapshot. Sequence IDs are persisted to avoid replay after reconnect. Native top-edge gestures are handled locally by the GTK viewer.

Protocol opcodes above use hexadecimal notation.
