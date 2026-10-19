"""Exercise the shipping rasterizer with both editions and long CJK replies."""
import io
import json
from pathlib import Path
import sys
import pytest
from PIL import Image
from panel_render import PanelRenderer

BASE = Path(__file__).resolve().parents[1]
pytestmark = pytest.mark.skipif(sys.platform != 'darwin' or not (BASE/'build/KindleDeskRenderer').exists(), reason='Native macOS renderer build')


@pytest.mark.parametrize('language', ['zh', 'en'])
@pytest.mark.parametrize('content', ['demo', 'long', 'empty'])
def test_native_panel_contract(language, content):
    state = json.loads((BASE/'examples/demo-state.json').read_text())
    if content == 'long':
        for item in state['codex']['items']:
            item['question'] = '请核对今天的任务、天气与电量。' * 120
            item['reply'] = ('第一行已经完成。\n第二行继续处理，把完整句子显示在看板上。\n' * 200)[:8192]
        state['kindle']['charging'] = True
        state['weather']['code'] = 95
    elif content == 'empty':
        state['codex']['items'] = []
        state['kindle'] = {}
        state['weather'] = {}
    renderer = PanelRenderer(BASE)
    try:
        png, ui = renderer.render(state, {'language':language})
    finally:
        renderer.close()
    assert ui == {'language':language}
    assert 8000 < len(png) < 262116
    with Image.open(io.BytesIO(png)) as image:
        assert image.size == (1236,1648) and image.mode == 'L'
        assert len(image.getcolors(256)) <= 16
        # The refresh button's native touch boundary stays in the same place.
        assert image.getpixel((1000,1518)) < 200
        assert image.getpixel((1000,1575)) < 200
