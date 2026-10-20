"""Read-only host resources and authenticated Kindle telemetry."""
import json
import math
import subprocess
import time
import psutil

class MacMetrics:
    def __init__(self, state):
        self.state = state
        self.history = {}
        try:
            rows = json.loads((state / 'cpu-history.json').read_text())
            minute = int(time.time() // 60)
            self.history = {int(m): float(v) for m, v in rows
                            if minute-31 <= int(m) <= minute and math.isfinite(float(v)) and 0 <= float(v) <= 100}
        except (OSError, ValueError, TypeError):
            self.history = {}
        self.name, self.chip = 'Mac', 'macOS'
        try:
            value = json.loads(subprocess.check_output(['system_profiler', 'SPHardwareDataType', '-json'], timeout=8))['SPHardwareDataType'][0]
            self.name = value.get('machine_name', 'Mac')
            self.chip = value.get('chip_type', 'macOS')
        except (OSError, ValueError, KeyError, IndexError, subprocess.SubprocessError):
            pass

    def snapshot(self):
        # Sample on the calling thread; a new thread's first nonblocking read is zero.
        cpu = psutil.cpu_percent(interval=0.1)
        minute = int(time.time() // 60)
        self.history = {m: v for m, v in self.history.items() if minute-31 <= m <= minute}
        self.history[minute] = round(cpu, 1)
        self.state.mkdir(parents=True, exist_ok=True)
        temporary = self.state / 'cpu-history.json.tmp'
        temporary.write_text(json.dumps(sorted(self.history.items())))
        temporary.replace(self.state / 'cpu-history.json')
        # Missing minutes remain gaps rather than invented zero-percent readings.
        history = [self.history.get(m) for m in range(min(self.history), minute+1)]
        memory = psutil.virtual_memory(); disk = psutil.disk_usage('/System/Volumes/Data')
        return {'name': self.name, 'chip': self.chip, 'cpu_percent': cpu, 'cpu_history': history,
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
