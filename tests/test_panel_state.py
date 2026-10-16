"""A restart must retain language and must not apply an old tap twice."""
import io
import json
from types import SimpleNamespace
from PIL import Image
import desk


def test_language_and_consumed_tap_survive_collector_restart(tmp_path, monkeypatch):
    output = io.BytesIO()
    Image.new('L', (1236, 1648), 255).save(output, format='PNG')
    png = output.getvalue()
    monkeypatch.setattr(desk, 'STATE', tmp_path)
    monkeypatch.setattr(desk, 'CodexCollector', lambda: SimpleNamespace(snapshot=lambda _: {}))
    monkeypatch.setattr(desk, 'WeatherCollector', lambda _: SimpleNamespace(snapshot=lambda: {}))
    monkeypatch.setattr(desk, 'MacMetrics', lambda _: SimpleNamespace(snapshot=lambda: {}, kindle=lambda: {}))

    class Renderer:
        def __init__(self, _):
            pass

        def render(self, state, restore=None, touch=None):
            ui = dict(restore)
            if touch:
                ui['language'] = 'en' if ui.get('language') == 'zh' else 'zh'
            return png, ui

    monkeypatch.setattr(desk, 'PanelRenderer', Renderer)
    # The browser chose Chinese, then the Kindle tap selected English.
    (tmp_path/'panel-request.json').write_text(json.dumps({'seq':'browser-1','ui':{'language':'zh'}}))
    (tmp_path/'panel-event.json').write_text(json.dumps({'seq':'tap-1','x':1000,'y':1600}))
    assert desk.Desk().collect()['panel_ui']['language'] == 'en'
    restarted = desk.Desk()
    assert restarted.collect()['panel_ui']['language'] == 'en'
    # A newly arrived tap still changes the language.
    (tmp_path/'panel-event.json').write_text(json.dumps({'seq':'tap-2','x':1000,'y':1600}))
    assert restarted.collect(fresh=False)['panel_ui']['language'] == 'zh'
