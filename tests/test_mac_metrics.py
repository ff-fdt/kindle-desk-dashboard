import json
from types import SimpleNamespace
import mac_metrics


def setup_metrics(monkeypatch):
    clock = [6000]
    monkeypatch.setattr(mac_metrics.time, 'time', lambda: clock[0])
    monkeypatch.setattr(mac_metrics.subprocess, 'check_output', lambda *a, **kw: b'{"SPHardwareDataType":[{}]}')
    def cpu(*, interval):
        assert interval == 0.1
        return 92.5
    monkeypatch.setattr(mac_metrics.psutil, 'cpu_percent', cpu)
    monkeypatch.setattr(mac_metrics.psutil, 'virtual_memory', lambda: SimpleNamespace(total=32*1024**3, available=16*1024**3, percent=50))
    monkeypatch.setattr(mac_metrics.psutil, 'disk_usage', lambda _: SimpleNamespace(total=100, free=50))
    return clock


def test_history_survives_restart_and_refresh_does_not_add_minutes(tmp_path, monkeypatch):
    clock = setup_metrics(monkeypatch)
    metrics = mac_metrics.MacMetrics(tmp_path)
    assert metrics.snapshot()['cpu_history'] == [92.5]
    clock[0] += 5
    assert metrics.snapshot()['cpu_history'] == [92.5]
    clock[0] += 55
    restarted = mac_metrics.MacMetrics(tmp_path)
    assert restarted.snapshot()['cpu_history'] == [92.5, 92.5]
    clock[0] += 120
    assert restarted.snapshot()['cpu_history'] == [92.5,92.5,None,92.5]
    clock[0] += 3600
    assert mac_metrics.MacMetrics(tmp_path).snapshot()['cpu_history'] == [92.5]


def test_corrupt_cache_recovers_and_retention_is_bounded(tmp_path, monkeypatch):
    clock = setup_metrics(monkeypatch)
    (tmp_path/'cpu-history.json').write_text('broken')
    metrics = mac_metrics.MacMetrics(tmp_path)
    for _ in range(40):
        result = metrics.snapshot()
        clock[0] += 60
    assert len(result['cpu_history']) == 32
    assert len(json.loads((tmp_path/'cpu-history.json').read_text())) == 32
