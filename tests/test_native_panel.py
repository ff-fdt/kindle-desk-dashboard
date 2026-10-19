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


@pytest.mark.parametrize('latex', [
    r'\frac{\partial E}{\partial x}=\sum_{i=1}^{N}\frac{\hbar^2 k_i^2}{2m}',
    r'\begin{pmatrix}1&2\\3&4\end{pmatrix}',
    r'\int_{-\infty}^{\infty}e^{-x^2}\,dx=\sqrt{\pi}',
    r'\begin{aligned}a&=b+c\\d&=e-f\end{aligned}',
    r'\unknowncommand{x}', r'\frac{a}{',
])
def test_formula_rendering_and_invalid_formula_fallback(latex):
    state=json.loads((BASE/'examples/demo-state.json').read_text())
    state['codex']['items'][0]['question']=r'计算 $E=mc^2$'
    state['codex']['items'][0]['reply']='结果如下：\n\\['+latex+'\\]\n保留后续文字。'
    import subprocess, os
    from math_text import prepare_state
    result=subprocess.run([str(BASE/'build/KindleDeskRenderer'),str(BASE)],
        input=json.dumps({'state':prepare_state(state),'ui':{'language':'zh'}}).encode(),
        capture_output=True,timeout=15,check=True,
        env={**os.environ,'KINDLE_DESK_RENDER_STATS':'1'})
    stats=json.loads(result.stderr.decode().split('KINDLE_DESK_MATH_STATS ')[1])
    invalid=latex in (r'\unknowncommand{x}',r'\frac{a}{')
    assert stats=={'rendered':1 if invalid else 2,'fallback':1 if invalid else 0}
    png=result.stdout
    with Image.open(io.BytesIO(png)) as image:
        assert image.size==(1236,1648)
        # Formula/fallback occupies the reply area, and leaves the inter-card margin clear.
        assert image.crop((48,560,866,730)).getextrema()[0]<100
        assert image.crop((48,765,866,777)).getextrema()==(255,255)
