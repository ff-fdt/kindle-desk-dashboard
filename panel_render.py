"""Render the portrait panel with the macOS text and vector drawing engine."""
from pathlib import Path
import json
import os
import signal
import subprocess
import threading


class PanelRenderer:
    """Release native drawing resources as soon as each frame is complete."""
    def __init__(self, base):
        self.base = str(Path(base).resolve())
        self._process = None
        self._lock = threading.Lock()
        self._closed = False

    @staticmethod
    def _terminate(process):
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    def render(self, state, restore=None, touch=None):
        with self._lock:
            if self._closed:
                raise RuntimeError('Renderer is closed')
            process = subprocess.Popen(
                [str(Path(self.base) / 'build/KindleDeskRenderer'), self.base],
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                start_new_session=True)
            self._process = process
        try:
            output, error = process.communicate(
                json.dumps({'state': state, 'ui': restore}).encode(), timeout=30)
            if process.returncode:
                raise RuntimeError('Frame rendering failed: ' + error.decode(errors='replace')[-1000:])
            return output, {'language': 'en' if (restore or {}).get('language') == 'en' else 'zh'}
        finally:
            self._terminate(process)
            process.communicate()
            with self._lock:
                self._process = None

    def close(self):
        with self._lock:
            self._closed = True
            if self._process is not None:
                self._terminate(self._process)
