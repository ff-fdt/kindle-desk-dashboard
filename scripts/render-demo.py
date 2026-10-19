#!/usr/bin/env python3
"""Render clearly fictional sample data; never read local Codex conversations."""
from pathlib import Path
import json
import sys
import time

BASE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BASE))
from panel_render import PanelRenderer

fixture = 'math-state.json' if '--math' in sys.argv else 'demo-state.json'
state = json.loads((BASE / 'examples' / fixture).read_text())
prefix = 'math' if '--math' in sys.argv else 'panel'
state['generated_at'] = int(time.time())
state['kindle']['observed_at'] = state['generated_at']
output = BASE / 'docs/images'
output.mkdir(exist_ok=True)
renderer = PanelRenderer(BASE)
try:
    for language in ('zh', 'en'):
        png, _ = renderer.render(state, {'language': language})
        (output / f'{prefix}-{language}.png').write_bytes(png)
        print(output / f'{prefix}-{language}.png')
finally:
    renderer.close()
