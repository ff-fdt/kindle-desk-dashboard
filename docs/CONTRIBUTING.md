# Contributing

Start with the [Mac preview](../README.md#quick-start). Use `examples/demo-state.json` for screenshots and examples.

- Include the Kindle model, firmware, macOS version and reproduction steps in device bug reports.
- Keep the browser layout in `panel/` and native layout in `mac/Renderer/main.swift` aligned. For layout changes, render both languages at 1236 × 1648 and check long questions and replies.
- For device changes, check startup, sleep/wake, Bluetooth reconnection and native quick settings.
- Use sample conversations in shared screenshots and logs; keep pairing keys in the local state directory.

Run the checks before submitting a pull request:

```sh
.venv/bin/python -m pip install pytest
.venv/bin/python -m pytest -q
node --check panel/panel.js
sh scripts/build-renderer.sh
.venv/bin/python scripts/render-demo.py
```

Describe the resulting behavior and include a relevant screenshot or reproduction example.
