#!/usr/bin/env python3
"""Read-only Codex/weather collector and local preview for Kindle Desk."""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import html
import io
import json
import os
from pathlib import Path
import re
import secrets
import sqlite3
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.request import urlopen, Request
from urllib.parse import urlencode, urlparse
from zoneinfo import ZoneInfo

BASE = Path(__file__).resolve().parent
import psutil
from PIL import Image
from panel_render import PanelRenderer
from mac_metrics import MacMetrics

STATE = Path(os.environ.get('KINDLE_DESK_STATE_DIR', str(BASE / 'state')))
CONFIG = json.loads((BASE / 'config/example.json').read_text())
if (BASE / 'config/local.json').exists():
    CONFIG.update(json.loads((BASE / 'config/local.json').read_text()))

def atomic(path: Path, value: bytes):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(path.name + '.tmp')
    temp.write_bytes(value)
    os.replace(temp, path)

def encode(value):
    return json.dumps(value, ensure_ascii=False, separators=(',', ':')).encode('utf-8')

def validate_frame(png: bytes):
    if not 8 <= len(png) <= 262116:
        raise ValueError('PNG must be at most 262116 bytes')
    with Image.open(io.BytesIO(png)) as image:
        if image.format != 'PNG' or image.size != (1236, 1648):
            raise ValueError('Expected a 1236 x 1648 portrait PNG')
        image.verify()

def device_request(value):
    if not isinstance(value, dict) or not isinstance(value.get('action'), str) or value['action'] not in {
            'brightness', 'warmth', 'native_settings', 'dashboard', 'status'}:
        raise ValueError('Unsupported device action')
    level = value.get('value', 0)
    if type(level) is not int or not 0 <= level <= 24:
        raise ValueError('Level must be an integer from 0 to 24')
    return {'seq': secrets.token_hex(8), 'action': value['action'], 'value': level,
            'queued_at': time.time()}

def device_status():
    try:
        report = json.loads((STATE / 'device-status.json').read_text())
    except (OSError, ValueError):
        report = {'mode': 'unknown', 'brightness': None, 'warmth': None}
    try:
        command = json.loads((STATE / 'command.json').read_text())
        if command['seq'] != report.get('seq'):
            report['pending'] = command
            report['expired'] = time.time() - command['queued_at'] >= 120
    except (OSError, ValueError, KeyError):
        pass
    return report

def clean(text, limit=160):
    text = re.sub(r'<oai-mem-citation>.*?</oai-mem-citation>', '', str(text), flags=re.S)
    text = re.sub(r'!?\[([^\]]*)\]\([^)]*\)', r'\1', text)
    text = re.sub(r'[`*#>]+', '', text)
    return re.sub(r'\s+', ' ', text).strip()[:limit]

def event_timestamp(event, payload):
    t = payload.get('completed_at') or payload.get('started_at')
    if isinstance(t, (float, int)):
        return t / 1000 if t > 10**12 else t
    try:
        return dt.datetime.fromisoformat(event['timestamp'].replace('Z', '+00:00')).timestamp()
    except (KeyError, ValueError, TypeError):
        return None

from conversations import CodexCollector, parse_rollout

WEATHER_CODES = {0: '晴', 1: '晴间多云', 2: '局部多云', 3: '阴', 45: '雾', 48: '雾凇',
                 51: '小毛毛雨', 53: '毛毛雨', 55: '较强毛毛雨', 61: '小雨', 63: '雨', 65: '大雨',
                 71: '小雪', 73: '雪', 75: '大雪', 80: '阵雨', 81: '阵雨', 82: '强阵雨', 95: '雷雨'}

class WeatherCollector:
    def __init__(self, config, state=STATE):
        self.config, self.state = config, state
        self.cached, self.next_fetch = None, 0
        try:
            self.cached = json.loads((state / 'weather-cache.json').read_text())
        except (OSError, ValueError):
            pass

    def snapshot(self):
        now = time.time()
        if now >= self.next_fetch:
            self.next_fetch = now + self.config['weather_refresh_seconds']
            query = urlencode({'latitude': self.config['latitude'], 'longitude': self.config['longitude'],
                               'current': 'temperature_2m,apparent_temperature,weather_code,wind_speed_10m',
                               'daily': 'temperature_2m_max,temperature_2m_min,precipitation_probability_max',
                               'timezone': self.config['timezone'], 'forecast_days': 1})
            try:
                req = Request('https://api.open-meteo.com/v1/forecast?' + query,
                              headers={'User-Agent': 'KindleDesk/0.1 personal dashboard'})
                with urlopen(req, timeout=8) as response:
                    data = json.load(response)
                current, daily = data['current'], data['daily']
                code = current['weather_code']
                self.cached = {'city': self.config['city'], 'temperature': current['temperature_2m'],
                               'feels_like': current['apparent_temperature'], 'description': WEATHER_CODES.get(code, '天气代码 ' + str(code)),
                               'code': code, 'wind_kmh': current['wind_speed_10m'],
                               'high': daily['temperature_2m_max'][0], 'low': daily['temperature_2m_min'][0],
                               'rain_percent': daily['precipitation_probability_max'][0], 'observed_at': current['time'],
                               'fetched_at': now, 'source': 'Open-Meteo'}
                atomic(self.state / 'weather-cache.json', encode(self.cached))
            except (OSError, ValueError, KeyError, IndexError) as exc:
                self.next_fetch = now + 60
                return {**(self.cached or {'city': self.config['city']}), 'stale': True,
                        'available': self.cached is not None, 'error': type(exc).__name__}
        return {**(self.cached or {'city': self.config['city']}),
                'available': self.cached is not None,
                'stale': not self.cached or now - self.cached.get('fetched_at', 0) > 1800}

class Desk:
    def __init__(self):
        self.codex, self.weather = CodexCollector(), WeatherCollector(CONFIG)
        self.metrics = MacMetrics(STATE)
        self.lock = threading.Lock()
        self.current = None
        self.renderer = None
        self.ready = threading.Event()
        self.next_collect = 0
        self.last_state = None
        self.panel_ui = {'language': CONFIG.get('language', 'zh')}

    def collect(self, fresh=True):
        if self.renderer is None:
            self.renderer = PanelRenderer(BASE)
        if fresh or self.last_state is None:
            state = {'schema': 2, 'generated_at': int(time.time()), 'timezone': CONFIG['timezone'],
                     'weather': self.weather.snapshot(), 'codex': self.codex.snapshot(3),
                     'mac': self.metrics.snapshot(), 'kindle': self.metrics.kindle()}
            self.last_state = state
        else:
            state = dict(self.last_state)
        restore = {'language': CONFIG.get('language', 'zh')}
        png, ui = self.renderer.render(state, restore=restore)
        validate_frame(png)
        state['panel_ui'] = ui
        self.panel_ui = ui
        atomic(STATE / 'panel-ui.json', encode({'ui': ui}))
        state['revision'] = hashlib.sha256(encode(state)).hexdigest()[:16]
        with self.lock:
            atomic(STATE / 'snapshot.json', encode(state))
            if (STATE / 'frontend.png').exists():
                png = (STATE / 'frontend.png').read_bytes()
            atomic(STATE / 'screen.png', png)
            atomic(STATE / 'device.png', png)
            self.current = state
        self.ready.set()
        return state

    def run(self):
        while True:
            if time.monotonic() >= self.next_collect:
                try:
                    self.collect()
                    self.next_collect = time.monotonic() + CONFIG['refresh_seconds']
                except Exception as exc:
                    atomic(STATE / 'collector-error.json', encode({'at': time.time(), 'error': str(exc)}))
                    if self.renderer:
                        try: self.renderer.close()
                        except Exception: pass
                    self.renderer = None
                    time.sleep(5)
            time.sleep(.5)


def serve(port):
    desk = Desk()
    if not (STATE / 'command.json').exists():
        atomic(STATE / 'command.json', encode(device_request({'action': 'status'})))
    threading.Thread(target=desk.run, daemon=True).start()
    if not desk.ready.wait(60):
        raise RuntimeError('Initial panel render failed; inspect collector-error.json')
    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            if urlparse(self.path).path == '/api/device':
                if self.headers.get('X-Kindle-Desk') != 'control':
                    self.send_error(403); return
                try:
                    length = int(self.headers.get('Content-Length', '0'))
                    if not 1 <= length <= 1024:
                        raise ValueError('Request too large')
                    self.connection.settimeout(5)
                    command = device_request(json.loads(self.rfile.read(length)))
                    with desk.lock:
                        current = device_status()
                        if current.get('pending') and not current.get('expired'):
                            self.send_error(409, 'Device has not acknowledged the previous request'); return
                        atomic(STATE / 'command.json', encode(command))
                except (ValueError, OSError):
                    self.send_error(400, 'Unsupported action or invalid level'); return
                body = encode(command)
                self.send_response(202)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(body)))
                self.end_headers(); self.wfile.write(body); return
            if urlparse(self.path).path != '/api/frame':
                self.send_error(404); return
            if self.headers.get('X-Kindle-Desk') != 'frame':
                self.send_error(403); return
            try:
                length = int(self.headers.get('Content-Length', '0'))
                if not 8 <= length <= 262116:
                    raise ValueError('Frame size out of bounds')
                self.connection.settimeout(5)
                png = self.rfile.read(length)
                if len(png) != length:
                    raise ValueError('Incomplete frame')
                validate_frame(png)
                with desk.lock:
                    atomic(STATE / 'frontend.png', png)
                    atomic(STATE / 'device.png', png)
                    atomic(STATE / 'screen.png', png)
            except (ValueError, OSError, SyntaxError, Image.DecompressionBombError):
                self.send_error(400, 'Expected a 1236 x 1648 portrait PNG under 262116 bytes'); return
            self.send_response(204)
            self.send_header('Content-Length', '0')
            self.end_headers()
        def do_GET(self):
            route = urlparse(self.path).path
            if route in ('/', '/panel'):
                self.send_response(302); self.send_header('Location', '/panel/'); self.end_headers(); return
            elif route.startswith('/panel/'):
                import mimetypes
                path = (BASE / 'panel' / (route[len('/panel/'):] or 'index.html')).resolve()
                if not path.is_relative_to((BASE / 'panel').resolve()) or not path.is_file():
                    self.send_error(404); return
                body, content = path.read_bytes(), mimetypes.guess_type(path)[0] or 'application/octet-stream'
            elif route == '/settings':
                body, content = (BASE / 'mac/control.html').read_bytes(), 'text/html; charset=utf-8'
            elif route == '/screen.png':
                body, content = (STATE / 'screen.png').read_bytes(), 'image/png'
            elif route == '/api/state':
                body, content = (STATE / 'snapshot.json').read_bytes(), 'application/json'
            elif route == '/api/device':
                body, content = encode(device_status()), 'application/json'
            elif route == '/api/transport':
                try:
                    value = json.loads((STATE / 'bluetooth-status.json').read_text())
                except (OSError, ValueError):
                    value = {'state': 'not_started'}
                if time.time() - value.get('at', 0) > 45:
                    value = {'state': 'offline'}
                body, content = encode(value), 'application/json'
            elif route == '/health':
                body, content = encode({'ok': True, 'revision': desk.current['revision']}), 'application/json'
            else:
                self.send_error(404); return
            self.send_response(200)
            self.send_header('Content-Type', content)
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers(); self.wfile.write(body)
        def log_message(self, *args):
            pass
    server = ThreadingHTTPServer(('127.0.0.1', port), Handler)
    print(f'Kindle Desk: http://127.0.0.1:{port}', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.server_close()

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--once', action='store_true')
    parser.add_argument('--port', type=int, default=8791)
    args = parser.parse_args()
    STATE.mkdir(exist_ok=True)
    if args.once:
        instance = Desk()
        x = instance.collect()
        instance.renderer.close()
        print(json.dumps({'revision': x['revision'], 'weather': x['weather'],
                          'completed_turns': len(x['codex']['completed'])}, ensure_ascii=False))
    else:
        serve(args.port)
