"""The renderer must release its entire subprocess group on every exit path."""
import io
from PIL import Image
import subprocess
from unittest.mock import Mock
import pytest
import panel_render


@pytest.mark.parametrize('failure', [None, 'timeout', 'exit'])
def test_render_reaps_worker_on_success_and_failure(monkeypatch, tmp_path, failure):
    process = Mock(pid=12345, returncode=1 if failure == 'exit' else 0)
    buffer = io.BytesIO()
    Image.new('L', (1236, 1648), 255).save(buffer, format='PNG')
    output = b'invalid' if failure == 'invalid' else buffer.getvalue()
    if failure == 'timeout':
        process.communicate.side_effect = [subprocess.TimeoutExpired('worker', 30), (b'', b'')]
    else:
        process.communicate.return_value = (output, b'failed')
    popen = Mock(return_value=process)
    kill = Mock()
    monkeypatch.setattr(panel_render.subprocess, 'Popen', popen)
    monkeypatch.setattr(panel_render.os, 'killpg', kill)
    renderer = panel_render.PanelRenderer(tmp_path)
    if failure:
        with pytest.raises((RuntimeError, ValueError, OSError, subprocess.TimeoutExpired)):
            renderer.render({})
    else:
        png, ui = renderer.render({})
        assert Image.open(io.BytesIO(png)).size == (1236, 1648)
        assert ui == {'language':'zh'}
    assert popen.call_args.kwargs['start_new_session']
    kill.assert_called_once()
    assert process.communicate.call_count == 2
    assert renderer._process is None
    renderer.close()
    with pytest.raises(RuntimeError, match='closed'):
        renderer.render({})
