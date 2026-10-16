"""Render the same HTML panel used by the preview into the Kindle's native PNG."""
from pathlib import Path
import io
import os
from playwright.sync_api import sync_playwright
from PIL import Image


class PanelRenderer:
    def __init__(self, base):
        self.runtime = sync_playwright().start()
        executable = os.environ.get('KINDLE_DESK_CHROMIUM')
        if not executable:
            candidates = list((Path.home() / 'Library/Caches/ms-playwright').glob(
                'chromium-*/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing'))
            if candidates:
                executable = str(sorted(candidates, key=lambda p: int(p.parents[4].name.split('-')[-1]))[-1])
        self.browser = self.runtime.chromium.launch(headless=True, executable_path=executable)
        self.page = self.browser.new_page(viewport={'width': 1236, 'height': 1648}, device_scale_factor=1)
        self.page.goto((Path(base) / 'panel/index.html').as_uri() + '?capture=1')
        self.page.evaluate('document.fonts.ready')

    def render(self, state, restore=None, touch=None):
        self.page.evaluate('([state,ui]) => window.renderDashboard(state,ui)', [state, restore])
        self.page.evaluate('document.fonts.ready')
        raw = self.page.screenshot(animations='disabled')
        image = Image.open(io.BytesIO(raw)).convert('L').quantize(
            colors=16, method=Image.Quantize.MAXCOVERAGE, dither=Image.Dither.NONE)
        output = io.BytesIO(); image.save(output, format='PNG', optimize=True)
        return output.getvalue(), self.page.evaluate('window.panelUI')

    def close(self):
        self.browser.close(); self.runtime.stop()
