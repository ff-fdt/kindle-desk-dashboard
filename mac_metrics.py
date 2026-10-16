"""Read-only host resources and authenticated Kindle telemetry."""
from collections import deque
import json
import subprocess
import time
import psutil

class MacMetrics:
    def __init__(self, state):
        self.state = state
        self.history = deque(maxlen=32)
        self.name, self.chip = 'Mac', 'macOS'
        try:
            value = json.loads(subprocess.check_output(['system_profiler', 'SPHardwareDataType', '-json'], timeout=8))['SPHardwareDataType'][0]
            self.name = value.get('machine_name', 'Mac')
            self.chip = value.get('chip_type', 'macOS')
        except (OSError, ValueError, KeyError, IndexError, subprocess.SubprocessError):
            pass
        psutil.cpu_percent()

    def snapshot(self):
        cpu = psutil.cpu_percent()
        self.history.append(round(cpu, 1))
        memory = psutil.virtual_memory(); disk = psutil.disk_usage('/System/Volumes/Data')
        return {'name': self.name, 'chip': self.chip, 'cpu_percent': cpu, 'cpu_history': list(self.history),
                'memory_percent': memory.percent, 'memory_used_gb': (memory.total-memory.available)/1024**3,
                'memory_total_gb': memory.total/1024**3, 'disk_percent': 100*(disk.total-disk.free)/disk.total,
                'disk_used_gb': (disk.total-disk.free)/1024**3, 'disk_total_gb': disk.total/1024**3}

    def kindle(self):
        try:
            data = json.loads((self.state / 'telemetry.json').read_text())
            data['stale'] = time.time()-data.get('observed_at', 0) > 180
            return data
        except (OSError, ValueError):
            return {'battery_percent': None, 'charging': None, 'observed_at': None, 'stale': True}
