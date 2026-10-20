"""Read real user/assistant turns; never derive a question from a thread title."""
from __future__ import annotations
import datetime as dt
import json
from pathlib import Path
import re
import sqlite3
from math_text import protect_math

MAX_TEXT = 8192
MAX_RECORD = 4 * 1024 * 1024
READ_CHUNK = 64 * 1024
MAX_TURNS = 4


def timestamp(event, payload):
    value = payload.get('completed_at') or payload.get('started_at')
    if isinstance(value, (float, int)):
        return value / 1000 if value > 10**12 else value
    try:
        return dt.datetime.fromisoformat(event['timestamp'].replace('Z', '+00:00')).timestamp()
    except (KeyError, ValueError, TypeError):
        return None


def plain(text):
    text = str(text or '')[:MAX_TEXT]
    text = re.sub(r'<oai-mem-citation>.*?</oai-mem-citation>', '', text, flags=re.S)
    return protect_math(text, clean_prose).strip()


def clean_prose(text):
    text = re.sub(r'<oai-mem-citation>.*?</oai-mem-citation>', '', text, flags=re.S)
    text = re.sub(r'!?\[([^\]]*)\]\([^)]*\)', r'\1', text)
    text = re.sub(r'^\s{0,3}#{1,6}\s+', '', text, flags=re.M)
    text = re.sub(r'\*\*([^*]+)\*\*', r'\1', text)
    text = re.sub(r'`{1,3}', '', text)
    text = re.sub(r'\n{3,}', '\n\n', text)
    return text


def question_text(text):
    if re.match(r'^\s*<(?:heartbeat|automation_trigger)(?:\s|>)', text):
        return ''
    if '## My request:' in text:
        text = text.split('## My request:', 1)[1]
    if '<send_user_message_question_reply>' in text:
        try:
            body = text.split('<send_user_message_question_reply>', 1)[1].split('</', 1)[0]
            text = '\n'.join(str(item['answer']) for item in json.loads(body))
        except (ValueError, KeyError, TypeError):
            return ''
    for marker in ('<environment_context>', '<in-app-browser-context', '<external_codex_apps_open_page', '# AGENTS.md instructions'):
        if text.lstrip().startswith(marker):
            return ''
    text = re.sub(r'<image\s[^>]*>', '', text)
    return plain(text)


def content_text(item):
    content = item.get('content', [])
    if isinstance(content, str):
        return content
    return '\n'.join(part.get('text', '') for part in content if isinstance(part, dict) and isinstance(part.get('text'), str))


class RolloutReader:
    def __init__(self, path):
        self.path = Path(path)
        self.offset = 0
        self.identity = None
        self.turns = {}
        self.current = None
        self.latest = None
        self.completed = None

    def turn(self, key, at):
        key = key or self.current or 'legacy'
        if key not in self.turns:
            self.turns[key] = {'turn_id': key, 'question': '', 'reply': '', 'at': at,
                               'updated_at': at, 'status': 'running'}
        while len(self.turns) > MAX_TURNS:
            del self.turns[next(iter(self.turns))]
        return self.turns[key]

    def consume(self, event):
        payload = event.get('payload', {})
        kind = payload.get('type')
        at = timestamp(event, payload)
        if kind in {'task_started', 'task_complete', 'task_aborted', 'turn_aborted'}:
            if kind == 'task_started':
                self.current = payload.get('turn_id') or 'legacy'
            turn = self.turn(payload.get('turn_id'), at)
            turn['updated_at'] = at
            self.latest = {'event': kind, 'at': at, 'turn_id': turn['turn_id']}
            if kind == 'task_complete':
                turn.update(status='completed', reply=plain(payload.get('last_agent_message') or turn['reply']))
                self.completed = {**self.latest, 'reply': turn['reply'], 'question': turn['question']}
            elif kind in {'task_aborted', 'turn_aborted'}:
                turn['status'] = 'aborted'
            else:
                turn['status'] = 'running'
            return
        if kind == 'item_completed':
            item = payload.get('item', {})
            typ = item.get('type')
            if typ not in ('UserMessage', 'AgentMessage'):
                return
            turn = self.turn(payload.get('turn_id'), at)
            text = content_text(item)
            if typ == 'UserMessage':
                value = question_text(text)
                if value and value not in turn.get('questions', []):
                    questions = turn.setdefault('questions', [])
                    remaining = MAX_TEXT - len(turn['question']) - (2 if questions else 0)
                    if remaining > 0:
                        questions.append(value[:remaining])
                        turn['question'] = '\n\n'.join(questions)
            else:
                value = plain(text)
                if value:
                    turn['reply'] = value
            turn['updated_at'] = at
        elif kind in ('user_message', 'agent_message'):
            turn = self.turn(payload.get('turn_id'), at)
            value = question_text(payload.get('message', '')) if kind == 'user_message' else plain(payload.get('message'))
            if value:
                turn['question' if kind == 'user_message' else 'reply'] = value
                turn['updated_at'] = at

    def read(self):
        stat = self.path.stat()
        identity = (stat.st_dev, stat.st_ino)
        if self.identity != identity or stat.st_size < self.offset:
            self.offset = 0; self.turns = {}; self.current = None
            self.latest = self.completed = None; self.identity = identity
        with self.path.open('rb') as stream:
            stream.seek(self.offset)
            while True:
                # Inspect the header before reading image/tool payloads. Chunked
                # skipping also bounds memory for a partially written huge record.
                line = stream.readline(512)
                if not line:
                    break
                wanted = b'"event_msg"' in line[:160]
                complete = line.endswith(b'\n')
                while not complete:
                    chunk = stream.readline(READ_CHUNK)
                    if not chunk:
                        break
                    complete = chunk.endswith(b'\n')
                    if wanted:
                        if len(line) + len(chunk) <= MAX_RECORD:
                            line += chunk
                        else:
                            wanted = False
                            line = b''
                if not complete:
                    break  # Retry this record after the writer finishes it.
                self.offset = stream.tell()
                if not wanted:
                    continue
                if not any(word in line for word in (b'"task_started"', b'"task_complete"', b'"task_aborted"', b'"turn_aborted"', b'"UserMessage"', b'"AgentMessage"', b'"user_message"', b'"agent_message"')):
                    continue
                try:
                    event = json.loads(line)
                    if event.get('type') == 'event_msg':
                        self.consume(event)
                except (ValueError, UnicodeDecodeError, TypeError):
                    continue
        items = [dict(t) for t in self.turns.values() if t['question'] and t['status'] in ('running', 'completed')]
        return {'latest': self.latest, 'completed': self.completed, 'items': items}


def parse_rollout(path, tail_bytes=None):
    return RolloutReader(path).read()


class CodexCollector:
    def __init__(self, db=None):
        self.db = Path(db or Path.home() / '.codex/state_5.sqlite')
        self.cache = {}

    def snapshot(self, limit=12):
        missing = {'available': False, 'completed': [], 'active': [], 'items': []}
        if not self.db.exists():
            return {**missing, 'error': '未找到 Codex 本地记录'}
        try:
            connection = sqlite3.connect(self.db.as_uri() + '?mode=ro', uri=True, timeout=1)
            try:
                rows = connection.execute('SELECT id,title,rollout_path,source FROM threads '
                                          'WHERE archived=0 ORDER BY updated_at DESC LIMIT 60').fetchall()
            finally:
                connection.close()
            active_paths = {row[2] for row in rows}
            self.cache = {path: reader for path, reader in self.cache.items() if path in active_paths}
            items = []
            for thread_id, title, file, source in rows:
                try:
                    reader = self.cache.setdefault(file, RolloutReader(file))
                    parsed = reader.read()
                except (OSError, ValueError):
                    continue
                # The latest visible question per chat prevents one busy chat filling the board.
                if parsed['items']:
                    turn = parsed['items'][-1]
                    if turn['at']:
                        items.append({**turn, 'thread_id': thread_id, 'title': plain(title),
                                      'id': thread_id + '/' + turn['turn_id']})
            items.sort(key=lambda x: (x['updated_at'] or x['at']), reverse=True)
            items = items[:limit]
            return {'available': True, 'items': items,
                    'completed': [x for x in items if x['status'] == 'completed'],
                    'active': [x for x in items if x['status'] == 'running'],
                    'meaning': '最近对话的问题、回复与状态。'}
        except (sqlite3.Error, OSError) as exc:
            return {**missing, 'error': type(exc).__name__}
