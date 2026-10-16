import json
import io
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import desk
import pytest
from PIL import Image

def event(kind, **fields):
    return json.dumps({'timestamp': '2026-10-16T00:00:00Z',
                       'type': 'event_msg', 'payload': {'type': kind, **fields}}) + '\n'

def test_new_running_turn_does_not_hide_previous_completion(tmp_path):
    p = tmp_path/'rollout.jsonl'
    p.write_text(event('task_complete', turn_id='old', last_agent_message='Done', completed_at=100)
                 + event('task_started', turn_id='new', started_at=200))
    x = desk.parse_rollout(p)
    assert x['latest']['event'] == 'task_started'
    assert x['completed']['turn_id'] == 'old'

def test_abort_is_not_reported_as_completion(tmp_path):
    p = tmp_path/'rollout.jsonl'
    p.write_text(event('task_started') + event('task_aborted'))
    x = desk.parse_rollout(p)
    assert x['latest']['event'] == 'task_aborted'
    assert x['completed'] is None

def test_partial_tail_record_is_ignored(tmp_path):
    p = tmp_path/'rollout.jsonl'
    p.write_text(event('task_complete', completed_at=123, last_agent_message='已完成') + '{"type":')
    assert desk.parse_rollout(p)['completed']['reply'] == '已完成'

def test_offline_weather_keeps_cache_and_marks_stale(tmp_path, monkeypatch):
    cached = {'city': 'London', 'temperature': 12, 'fetched_at': 1}
    (tmp_path/'weather-cache.json').write_text(json.dumps(cached))
    collector = desk.WeatherCollector(desk.CONFIG, tmp_path)
    def offline(*a, **kw):
        raise OSError('offline')
    monkeypatch.setattr(desk, 'urlopen', offline)
    x = collector.snapshot()
    assert x['available'] and x['stale']
    assert x['temperature'] == 12

def test_missing_codex_database_is_not_empty_success(tmp_path):
    x = desk.CodexCollector(tmp_path/'missing.sqlite').snapshot()
    assert not x['available']
    assert x['completed'] == []

def test_summary_removes_hidden_memory_markup_and_links():
    assert desk.clean('**完成** [报告](/private/report) <oai-mem-citation>private</oai-mem-citation>') == '完成 报告'

def test_frame_contract_accepts_native_portrait_only():
    for dimensions in [(1236,1648),(1648,1236)]:
        output=io.BytesIO();Image.new('L',dimensions,255).save(output,format='PNG')
        if dimensions==(1236,1648):
            desk.validate_frame(output.getvalue())
        else:
            with pytest.raises(ValueError):desk.validate_frame(output.getvalue())

def test_frame_contract_rejects_truncated_png():
    output=io.BytesIO();Image.new('L',(1236,1648),255).save(output,format='PNG')
    with pytest.raises((OSError,SyntaxError)):desk.validate_frame(output.getvalue()[:50])

@pytest.mark.parametrize('payload', [
    {'action':'brightness','value':25}, {'action':'brightness','value':-1},
    {'action':'brightness','value':True}, {'action':'shell','value':0},
    {'action':'warmth','value':'12'}, {'action':[]}, [],
])
def test_device_actions_are_bounded_and_allowlisted(payload):
    with pytest.raises(ValueError):desk.device_request(payload)

def test_device_request_records_intent_not_execution():
    x=desk.device_request({'action':'brightness','value':12})
    assert x['value']==12 and x['action']=='brightness' and len(x['seq'])==16
    assert 'ok' not in x and 'observed_at' not in x
