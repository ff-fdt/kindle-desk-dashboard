"""Split bounded conversation text into prose and LaTeX math runs."""
import re

MAX_FORMULA_CHARS = 2048
MAX_FORMULAS = 32
_OPEN = re.compile(r'\\\[|\\\(|\$\$|\$')


def _escaped(text, at):
    start = at
    while start and text[start - 1] == '\\':
        start -= 1
    return (at - start) % 2 == 1


def split_math(text):
    text = str(text or '')
    runs, start, cursor, count = [], 0, 0, 0
    while count < MAX_FORMULAS:
        match = _OPEN.search(text, cursor)
        if not match:
            break
        at, opening = match.start(), match.group()
        cursor = match.end()
        if _escaped(text, at):
            continue
        closing = {'\\[': '\\]', '\\(': '\\)', '$$': '$$', '$': '$'}[opening]
        end = text.find(closing, cursor)
        while end >= 0 and _escaped(text, end):
            end = text.find(closing, end + len(closing))
        if end < 0:
            continue
        body = text[cursor:end]
        # Dollar-delimited inline math follows TeX's no-edge-whitespace rule;
        # this also keeps "$10 and $20" as currency.
        if not body.strip() or len(body) > MAX_FORMULA_CHARS:
            continue
        if opening == '$' and (body[0].isspace() or body[-1].isspace() or '\n' in body):
            continue
        if at > start:
            runs.append({'kind': 'text', 'text': text[start:at]})
        runs.append({'kind': 'math', 'text': body.strip(),
                     'display': opening in ('$$', '\\['), 'source': text[at:end+len(closing)]})
        start = cursor = end + len(closing)
        count += 1
    if start < len(text):
        runs.append({'kind': 'text', 'text': text[start:]})
    return runs


def protect_math(text, clean):
    """Keep TeX stars, braces and line breaks intact during Markdown cleanup."""
    runs = split_math(text)
    prefix = '\ue000M'
    while prefix in text:
        prefix += 'M'
    placeholders, pieces = {}, []
    for i, run in enumerate(runs):
        if run['kind'] == 'math':
            key = prefix + str(i) + '\ue001'
            placeholders[key] = run['source']
            pieces.append(key)
        else:
            pieces.append(run['text'])
    result = clean(''.join(pieces))
    for key, value in placeholders.items():
        result = result.replace(key, value)
    return result


def prepare_state(state):
    codex = state.get('codex', {})
    items = [{**item, 'question_runs': split_math(item.get('question', '')),
              'reply_runs': split_math(item.get('reply', ''))}
             for item in codex.get('items', [])[:3]]
    return {**state, 'codex': {**codex, 'items': items}}
